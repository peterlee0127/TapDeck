import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let preferences: PreferencesStore
    let coordinator: GestureCoordinator

    private init() {
        let preferences = PreferencesStore()
        self.preferences = preferences
        coordinator = GestureCoordinator(preferences: preferences)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()
    private var launchedAsLoginItem = false
    private var handledInitialOpenApplicationEvent = false
    private var wakeRecoveryTask: Task<Void, Never>?

    override init() {
        super.init()
        // Observe the actual Open Application Apple event instead of polling
        // currentAppleEvent during lifecycle callbacks. The login-item marker is
        // only guaranteed to be present on this event.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the process out of the Dock and Command-Tab while still allowing
        // an explicitly opened settings window to become active.
        NSApp.setActivationPolicy(.accessory)
        observeWorkspacePowerEvents()
        AppModel.shared.coordinator.refresh()
        menuBar.start { [weak self] in self?.showSettings() }
#if DEBUG
        // Xcode launches the executable directly and may not send the Open
        // Application Apple event used by Finder and LaunchServices.
        showSettings()
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeRecoveryTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // A reopen event is generated when the user explicitly opens an app
        // that is already running in the background.
        showSettings()
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // AppKit may request an untitled window as part of initial launch.
        // Only honor it after the Open Application event has established that
        // this was an explicit user launch rather than a login-item launch.
        guard handledInitialOpenApplicationEvent, !launchedAsLoginItem else {
            return false
        }
        showSettings()
        return true
    }

    @objc
    private func handleOpenApplication(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        handledInitialOpenApplicationEvent = true
        launchedAsLoginItem = Self.isLoginItemLaunchEvent(event)
        guard !launchedAsLoginItem else { return }
        showSettings()
    }

    static func isLoginItemLaunchEvent(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }

    private func observeWorkspacePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidBecomeAvailable(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidBecomeAvailable(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidBecomeAvailable(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func systemWillSleep(_ notification: Notification) {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        // MultitouchSupport device references and event taps may be invalidated
        // while macOS sleeps. Release them before the hardware disappears.
        AppModel.shared.coordinator.activityLog.record(
            L10n.string("log.category.power", "Power"),
            L10n.string("log.power.sleep", "The Mac is going to sleep. Monitoring stopped.")
        )
        AppModel.shared.coordinator.stop()
    }

    @objc
    private func systemDidBecomeAvailable(_ notification: Notification) {
        AppModel.shared.coordinator.activityLog.record(
            L10n.string("log.category.power", "Power"),
            L10n.string("log.power.wake", "Wake or session-resume notification received. Preparing to reconnect.")
        )
        scheduleWakeRecovery()
    }

    private func scheduleWakeRecovery() {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = Task { @MainActor [weak self] in
            // Trackpad services can return before their devices are ready,
            // especially after hibernation. Retry only transient start failures.
            for delay in [Duration.seconds(1), .seconds(2), .seconds(4)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                let coordinator = AppModel.shared.coordinator
                coordinator.reconnect(reason: L10n.string(
                    "log.reconnect.after_wake",
                    "Re-establishing monitoring after wake."
                ))
                guard coordinator.status == .noTrackpad
                        || coordinator.status == .eventMonitorUnavailable else {
                    self.wakeRecoveryTask = nil
                    return
                }
            }
            self?.wakeRecoveryTask = nil
        }
    }

    private func showSettings() {
        DispatchQueue.main.async {
            // Finder and the status menu use the same command as Command-Comma.
            guard let menu = NSApp.mainMenu?.items.first?.submenu,
                  let index = menu.items.firstIndex(where: {
                      $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
                  }) else { return }
            NSApp.setActivationPolicy(.regular)
            menu.performActionForItem(at: index)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct TapDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.menuBar)
                .environmentObject(AppModel.shared.preferences)
                .environmentObject(AppModel.shared.coordinator)
        }
        .defaultSize(width: 680, height: 640)
        .windowResizability(.contentMinSize)
    }
}
