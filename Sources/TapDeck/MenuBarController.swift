import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, ObservableObject, NSMenuDelegate {
    private static let visibilityKey = "settings.showsMenuBarIcon"

    @Published var isVisible = UserDefaults.standard.object(forKey: MenuBarController.visibilityKey) as? Bool ?? true {
        didSet {
            guard oldValue != isVisible else { return }
            UserDefaults.standard.set(isVisible, forKey: Self.visibilityKey)
            updateStatusItem()
        }
    }

    private var statusItem: NSStatusItem?
    private var showSettings: (() -> Void)?

    func start(showSettings: @escaping () -> Void) {
        self.showSettings = showSettings
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard showSettings != nil else { return }
        if isVisible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "TapDeck")
            item.button?.toolTip = "TapDeck"
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            menuNeedsUpdate(menu)
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = AppModel.shared
        let status = model.coordinator.isTesting
            ? L10n.string("status.testing", "Testing")
            : model.coordinator.status.title

        menu.removeAllItems()
        let statusLabel = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())

        let recognition = addItem(
            to: menu,
            title: L10n.string("menu.enable_gestures", "Enable Trackpad Gestures"),
            action: #selector(toggleRecognition)
        )
        recognition.state = model.preferences.value.isEnabled ? .on : .off

        addItem(to: menu, title: L10n.string("menu.open_settings", "Open Settings…"),
                action: #selector(openSettings), key: ",")
        addItem(to: menu, title: L10n.string("menu.hide_icon", "Hide Menu Bar Icon"),
                action: #selector(hideIcon))

        menu.addItem(.separator())
        addItem(to: menu, title: L10n.string("menu.quit", "Quit TapDeck"), action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleRecognition() {
        let model = AppModel.shared
        model.preferences.value.isEnabled.toggle()
        model.coordinator.refresh()
    }

    @objc private func openSettings() { showSettings?() }
    @objc private func hideIcon() { isVisible = false }
    @objc private func quit() { NSApp.terminate(nil) }
}
