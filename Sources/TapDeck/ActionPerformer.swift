import AppKit
import CoreGraphics
import Foundation

enum ActionCommand: Equatable {
    case mouse(button: CGMouseButton, down: CGEventType, up: CGEventType)
    case key(keyCode: CGKeyCode, flags: CGEventFlags)
    case systemApplication(bundleIdentifier: String, fallbackPath: String)
    case application
    case none
}

extension GestureAction {
    var command: ActionCommand {
        switch self {
        case .middleClick: .mouse(button: .center, down: .otherMouseDown, up: .otherMouseUp)
        case .leftClick: .mouse(button: .left, down: .leftMouseDown, up: .leftMouseUp)
        case .rightClick: .mouse(button: .right, down: .rightMouseDown, up: .rightMouseUp)
        case .quickLook: .key(keyCode: 49, flags: [])
        case .missionControl: .systemApplication(
            bundleIdentifier: "com.apple.exposelauncher",
            fallbackPath: "/System/Applications/Mission Control.app"
        )
        case .appExpose: .key(keyCode: 125, flags: .maskControl)
        case .showDesktop: .key(keyCode: 103, flags: [])
        case .openApplication: .application
        case .none: .none
        }
    }
}

final class ActionPerformer: @unchecked Sendable {
    private let source = CGEventSource(stateID: .privateState)
    private let queue = DispatchQueue(label: "app.trackpadclicker.actions", qos: .userInteractive)
    private let eventMarker: Int64 = 0x5450434C // TPCL

    func perform(_ binding: GestureBinding, haptic: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            switch binding.action.command {
            case let .mouse(button, down, up): self.click(button: button, down: down, up: up)
            case let .key(keyCode, flags): self.keyPress(keyCode: keyCode, flags: flags)
            case let .systemApplication(bundleIdentifier, fallbackPath):
                DispatchQueue.main.async { [weak self] in
                    self?.openSystemApplication(
                        bundleIdentifier: bundleIdentifier,
                        fallbackPath: fallbackPath
                    )
                    if haptic { self?.performHapticFeedback() }
                }
                return
            case .application:
                guard let application = binding.application else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.openOrActivate(application)
                    if haptic { self?.performHapticFeedback() }
                }
                return
            case .none: break
            }

            if haptic {
                DispatchQueue.main.async {
                    self.performHapticFeedback()
                }
            }
        }
    }

    @MainActor
    private func openSystemApplication(bundleIdentifier: String, fallbackPath: String) {
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) ?? URL(fileURLWithPath: fallbackPath)
        openApplication(at: applicationURL)
    }

    @MainActor
    private func openOrActivate(_ application: ApplicationTarget) {
        if let bundleIdentifier = application.bundleIdentifier,
           let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
           ).first {
            runningApplication.activate(options: [.activateAllWindows])
            return
        }

        let storedURL = application.path.isEmpty ? nil : URL(fileURLWithPath: application.path)
        let applicationURL = application.bundleIdentifier.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        } ?? storedURL
        guard let applicationURL else { return }

        openApplication(at: applicationURL)
    }

    @MainActor
    private func openApplication(at applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    @MainActor
    private func performHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func click(button: CGMouseButton, down: CGEventType, up: CGEventType) {
        let position = CGEvent(source: nil)?.location ?? .zero
        guard let downEvent = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: position, mouseButton: button),
              let upEvent = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: position, mouseButton: button)
        else { return }
        for event in [downEvent, upEvent] {
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        }
        downEvent.post(tap: .cghidEventTap)
        usleep(10_000)
        upEvent.post(tap: .cghidEventTap)
    }

    private func keyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        down.post(tap: .cghidEventTap)
        usleep(8_000)
        up.post(tap: .cghidEventTap)
    }
}
