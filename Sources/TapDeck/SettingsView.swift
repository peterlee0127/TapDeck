import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var coordinator: GestureCoordinator

    @EnvironmentObject private var menuBar: MenuBarController

    @AppStorage("settings.selectedPage") private var selectedPage = SettingsPage.settings
    @State private var settingsWindow: NSWindow?
    @State private var showsPermissionResetConfirmation = false
    @State private var showsRestoreDefaultsConfirmation = false
    @State private var permissionResetErrorMessage: String?

    private enum SettingsPage: String, CaseIterable, Hashable, Identifiable {
        case general
        case settings
        case test
        case diagnostics

        var id: Self { self }

        var windowHeight: CGFloat {
            switch self {
            case .general: 330
            case .settings, .test, .diagnostics: 680
            }
        }

        var title: String {
            switch self {
            case .general: L10n.string("navigation.general", "General")
            case .settings: L10n.string("navigation.gestures", "Gestures")
            case .test: L10n.string("navigation.test", "Test")
            case .diagnostics: L10n.string("navigation.diagnostics", "Diagnostics")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .settings: "hand.tap"
            case .test: "waveform.path.ecg"
            case .diagnostics: "stethoscope"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            generalPage
                .tabItem { tabLabel(.general) }
                .tag(SettingsPage.general)
            settingsPage
                .tabItem { tabLabel(.settings) }
                .tag(SettingsPage.settings)
            testPage
                .tabItem { tabLabel(.test) }
                .tag(SettingsPage.test)
            diagnosticsPage
                .tabItem { tabLabel(.diagnostics) }
                .tag(SettingsPage.diagnostics)
        }
        .frame(minWidth: 620, minHeight: 260)
        .background {
            SettingsWindowReader { window in
                guard settingsWindow !== window else { return }
                settingsWindow = window
                if let window {
                    resize(window, for: selectedPage, animate: false)
                }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
            if selectedPage == .test { selectedPage = .settings }
            coordinator.setTesting(false)
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: selectedPage) { _, page in
            coordinator.setTesting(page == .test)
        }
        .task(id: selectedPage) {
            // Let the native settings tab finish its layout before resizing the window.
            await Task.yield()
            guard !Task.isCancelled, let settingsWindow else { return }
            resize(settingsWindow, for: selectedPage, animate: settingsWindow.isVisible && !reduceMotion)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            coordinator.setTesting(selectedPage == .test)
        }
        .onDisappear { coordinator.setTesting(false) }
        .alert(
            L10n.string("dialog.reset_accessibility.title", "Reset Accessibility Permission?"),
            isPresented: $showsPermissionResetConfirmation
        ) {
            Button(L10n.string("dialog.reset_accessibility.action", "Reset and Open System Settings"), role: .destructive) {
                resetAccessibilityPermission()
            }
            Button(L10n.string("common.cancel", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string(
                "dialog.reset_accessibility.message",
                "The current authorization will be removed. You will need to allow this app again in System Settings."
            ))
        }
        .alert(
            L10n.string("dialog.restore_defaults.title", "Restore All Defaults?"),
            isPresented: $showsRestoreDefaultsConfirmation
        ) {
            Button(L10n.string("dialog.restore_defaults.action", "Restore Defaults"), role: .destructive) {
                preferences.value = AppPreferences()
                coordinator.refresh()
            }
            Button(L10n.string("common.cancel", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string(
                "dialog.restore_defaults.message",
                "All gestures, actions, and sensitivity settings will return to their original values."
            ))
        }
        .alert(
            L10n.string("alert.accessibility_reset_failed.title", "Could Not Reset Accessibility Permission"),
            isPresented: Binding(
                get: { permissionResetErrorMessage != nil },
                set: { if !$0 { permissionResetErrorMessage = nil } }
            )
        ) {
            Button(L10n.string("common.ok", "OK"), role: .cancel) {}
        } message: {
            Text(permissionResetErrorMessage ?? L10n.string("common.unknown_error", "Unknown error"))
        }
    }

    private func resize(_ window: NSWindow, for page: SettingsPage, animate: Bool) {
        let frame = window.frame
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let height = min(page.windowHeight, visibleFrame?.height ?? page.windowHeight)
        let top = if let visibleFrame {
            max(visibleFrame.minY + height, min(frame.maxY, visibleFrame.maxY))
        } else {
            frame.maxY
        }
        let target = NSRect(x: frame.minX, y: top - height, width: frame.width, height: height)
        guard target != frame else { return }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
    }

    private func tabLabel(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.symbol)
    }

    private var settingsPage: some View {
        SettingsPane {
            statusContent
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.string("section.gestures.title", "Gestures and Actions"))
                    Spacer()
                    Text(L10n.string("gesture_row.action", "Action"))
                        .frame(width: GestureRow.actionWidth, alignment: .trailing)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 6)
                ForEach(GestureKind.allCases) { gesture in
                    Divider()
                        .padding(.top, [.twoFingerClick, .threeFingerClick, .fourFingerClick].contains(gesture) ? 6 : 0)
                    GestureRow(gesture: gesture)
                        .padding(.vertical, 5)
                }
            }
            Text(L10n.string(
                "gesture_group.two_finger.note",
                "Two-finger gestures are disabled by default to avoid overriding system assistive controls."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            sensitivitySettings

            Label(
                L10n.string(
                    "footer.gesture_explanation",
                    "Taps trigger after a quick touch and release; physical clicks require pressing the trackpad down."
                ),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var testPage: some View {
        SettingsPane {
            statusContent
            testTrackpad
            testResults
        }
    }

    private var generalPage: some View {
        SettingsPane {
            statusContent
            HStack(alignment: .top, spacing: 24) {
                generalGroup(L10n.string("settings.group.recognition", "Gesture Recognition")) {
                    Toggle(L10n.string("page.gestures.enable", "Enable Recognition"), isOn: masterEnabled)
                    Toggle(L10n.string("advanced.haptic_feedback.title", "Haptic Feedback"), isOn: Binding(
                        get: { preferences.value.hapticFeedback },
                        set: { preferences.value.hapticFeedback = $0 }
                    ))
                }
                generalGroup(L10n.string("settings.group.launch_and_display", "Launch and Display")) {
                    Toggle(L10n.string("settings.show_menu_bar_icon", "Show in Menu Bar"), isOn: $menuBar.isVisible)
                    if LaunchAtLoginController.isAvailable {
                        Toggle(L10n.string("advanced.launch_at_login.title", "Launch at Login"), isOn: Binding(
                            get: { preferences.value.launchAtLogin },
                            set: {
                                preferences.value.launchAtLogin = $0
                                LaunchAtLoginController.setEnabled($0)
                            }
                        ))
                    } else {
                        Toggle(L10n.string("advanced.launch_at_login.title", "Launch at Login"), isOn: .constant(false))
                            .disabled(true)
                        Text(L10n.string("advanced.launch_at_login.debug_unavailable", "Unavailable in debug builds"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Divider()
            Label(
                L10n.string(
                    "footer.privacy",
                    "All recognition happens locally, with no networking, analytics, or telemetry."
                ),
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func generalGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            activityStatus
            HStack {
                Button(L10n.string("permission.open_system_settings", "Open System Settings")) {
                    if coordinator.status == .needsPermission {
                        coordinator.requestPermission()
                    }
                    AccessibilityController.openSettings()
                }
                Button(L10n.string("advanced.open_trackpad_settings", "Open Trackpad Settings")) {
                    AccessibilityController.openTrackpadSettings()
                }
                Spacer()
                Menu(L10n.string("section.maintenance", "Permissions and Maintenance")) {
                    Button(L10n.string("advanced.reset_accessibility", "Reset Accessibility Permission"), role: .destructive) {
                        showsPermissionResetConfirmation = true
                    }
                    Button(L10n.string("advanced.restore_defaults", "Restore All Defaults"), role: .destructive) {
                        showsRestoreDefaultsConfirmation = true
                    }
                }
                .fixedSize()
            }

            Divider()

            ActivityLogView(log: coordinator.activityLog)
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusContent: some View {
        if coordinator.status == .needsPermission {
            permissionNotice
        } else if let warningMessage {
            warningNotice(message: warningMessage)
        } else {
            activityStatus
        }
    }

    private var masterEnabled: Binding<Bool> {
        Binding(
            get: { preferences.value.isEnabled },
            set: {
                preferences.value.isEnabled = $0
                coordinator.refresh()
            }
        )
    }

    private var activityStatus: some View {
        HStack(spacing: 12) {
            StatusDot(color: Color(nsColor: coordinator.status.color), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.isTesting && coordinator.status == .listening
                     ? L10n.string("status.testing_gestures", "Testing Gestures")
                     : coordinator.status.title)
                    .fontWeight(.semibold)
                Text(activityDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                coordinator.reconnect()
            } label: {
                Label(L10n.string("common.reconnect", "Reconnect"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help(coordinator.lastRecovery.map {
                L10n.format(
                    "help.last_reconnect",
                    "Last reconnect: %@",
                    $0.formatted(date: .omitted, time: .standard)
                )
            } ?? L10n.string(
                "help.reconnect",
                "Reconnect the trackpad and event monitor without changing settings."
            ))
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var activityDetail: String {
        if coordinator.status == .needsPermission { return permissionMessage }
        if let warningMessage { return warningMessage }
        if coordinator.status == .stopped {
            return L10n.string("status.gesture_recognition_paused", "Gesture recognition is paused")
        }
        if coordinator.fingerCount > 0 {
            return L10n.currentFingers(coordinator.fingerCount)
        }
        if let lastGesture = coordinator.lastGesture {
            return L10n.format("format.last_recognized", "Last recognized: %@", lastGesture.title)
        }
        return coordinator.isTesting
            ? L10n.string("status.waiting_test_input", "Waiting for trackpad input; configured actions will not run")
            : L10n.string("status.ready_for_input", "Ready for trackpad input")
    }

    private var sensitivitySettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("section.sensitivity", "Recognition Sensitivity"))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            SliderSetting(
                title: L10n.string("advanced.tap_duration.title", "Maximum Tap Duration"),
                detail: L10n.string("advanced.tap_duration.subtitle", "Longest contact time before fingers lift"),
                value: Binding(get: { preferences.value.tapDuration }, set: {
                    preferences.value.tapDuration = $0
                    coordinator.updateSensitivity()
                }),
                range: 0.18...0.55,
                valueText: "\(Int(preferences.value.tapDuration * 1000)) ms"
            )
            SliderSetting(
                title: L10n.string("advanced.movement_tolerance.title", "Movement Tolerance"),
                detail: L10n.string("advanced.movement_tolerance.subtitle", "Allowed finger movement during a tap"),
                value: Binding(get: { preferences.value.movementTolerance }, set: {
                    preferences.value.movementTolerance = $0
                    coordinator.updateSensitivity()
                }),
                range: 0.015...0.09,
                valueText: String(format: "%.1f%%", preferences.value.movementTolerance * 100)
            )
        }
    }

    private func resetAccessibilityPermission() {
        coordinator.stop()
        do {
            try AccessibilityController.reset()
            coordinator.requestPermission()
            AccessibilityController.openSettings()
        } catch {
            permissionResetErrorMessage = error.localizedDescription
            coordinator.refresh()
        }
    }

    private var permissionNotice: some View {
        StatusNotice(
            symbol: "lock.shield.fill",
            color: .orange,
            title: L10n.string("permission.title", "Accessibility Permission Required"),
            message: permissionMessage
        ) {
            Button(L10n.string("permission.reset", "Reset Permission")) {
                showsPermissionResetConfirmation = true
            }
            Button(L10n.string("permission.open_system_settings", "Open System Settings")) {
                coordinator.requestPermission()
                AccessibilityController.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionMessage: String {
        L10n.string(
            "permission.message",
            "This permission is used only to emit mouse and keyboard actions. Touch data never leaves this Mac."
        )
    }

    private var warningMessage: String? {
        switch coordinator.status {
        case .noTrackpad:
            L10n.string("warning.no_trackpad.message", "Make sure a trackpad is connected, then reconnect.")
        case .eventMonitorUnavailable:
            L10n.string("warning.event_monitor.message", "Make sure Accessibility permission is allowed, then reconnect.")
        default:
            nil
        }
    }

    private func warningNotice(message: String) -> some View {
        StatusNotice(
            symbol: "exclamationmark.triangle.fill",
            color: .orange,
            title: coordinator.status == .noTrackpad
                ? L10n.string("warning.no_trackpad.title", "Trackpad Not Found")
                : L10n.string("warning.event_monitor.title", "Could Not Start Event Monitoring"),
            message: message
        ) {
            Button(L10n.string("common.reconnect", "Reconnect")) { coordinator.refresh() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var testTrackpad: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.separator.opacity(0.65), lineWidth: 1)
                    }

                HStack(spacing: 20) {
                    ForEach(0..<coordinator.fingerCount, id: \.self) { index in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 18, height: 18)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel(
                            L10n.format("accessibility.finger_number", "Finger %d", index + 1)
                        )
                    }
                }
            }
            .frame(width: 300, height: 124)
            .padding(.horizontal, 24)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: coordinator.fingerCount)

            VStack(spacing: 3) {
                Text(coordinator.fingerCount == 0
                     ? L10n.string("test.waiting_for_input", "Waiting for Trackpad Input")
                     : L10n.detectedFingers(coordinator.fingerCount))
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(coordinator.fingerCount == 0
                     ? L10n.string("test.place_fingers", "Place your fingers on the trackpad to begin testing.")
                     : L10n.string("test.complete_gesture", "Keep contact or finish the press to test the gesture."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(
                L10n.string("test.actions_not_run", "Test mode only — configured actions will not run."),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var testResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("test.results.title", "Recognition Results"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L10n.string("test.clear_results", "Clear Results")) {
                    coordinator.clearTestResults()
                }
                .disabled(coordinator.detectedGestures.isEmpty && coordinator.lastGesture == nil)
            }
            .padding(.bottom, 6)

            ForEach(GestureKind.allCases) { gesture in
                let recognized = coordinator.detectedGestures.contains(gesture)
                Divider()
                HStack {
                    Text(gesture.title)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: recognized ? "checkmark.circle.fill" : "circle")
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(recognized
                            ? L10n.string("test.result.recognized", "Recognized")
                            : L10n.string("test.result.waiting", "Waiting"))
                    }
                    .frame(width: 120, alignment: .leading)
                    .foregroundStyle(recognized ? .green : .secondary)
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            Text(L10n.format("format.last_recognized", "Last recognized: %@", coordinator.lastGesture?.title ?? "—"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

private struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct StatusNotice<Actions: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    let actions: Actions

    init(
        symbol: String,
        color: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GestureRow: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var coordinator: GestureCoordinator
    let gesture: GestureKind

    static let actionWidth: CGFloat = 190

    private var binding: GestureBinding { preferences.binding(for: gesture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Toggle(gesture.title, isOn: Binding(get: { binding.isEnabled }, set: {
                    preferences.update(gesture, enabled: $0)
                    coordinator.refresh()
                }))
                .toggleStyle(.checkbox)
                .help(gesture.subtitle)

                Spacer(minLength: 12)

                Picker(
                    L10n.format("gesture_row.action_for", "Action for %@", gesture.title),
                    selection: Binding(get: { binding.action }, set: { action in
                        preferences.update(gesture, action: action)
                        coordinator.refresh()
                    })
                ) {
                    ForEach(GestureAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: Self.actionWidth, alignment: .trailing)
                .disabled(!binding.isEnabled)
            }

            if binding.action == .openApplication {
                HStack(spacing: 8) {
                    if let application = binding.application {
                        Label(application.displayName, systemImage: "app.fill")
                            .lineLimit(1)
                            .help(application.path)
                    } else {
                        Label(
                            L10n.string("gesture_row.no_app_selected", "No App Selected"),
                            systemImage: "exclamationmark.circle.fill"
                        )
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(binding.application == nil
                           ? L10n.string("gesture_row.choose_app", "Choose App")
                           : L10n.string("gesture_row.change_app", "Change App")) {
                        chooseApplication()
                    }
                    .disabled(!binding.isEnabled)
                }
                .font(.subheadline)
                .padding(.leading, 20)
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.string(
            "app_picker.title",
            "Choose an App to Open or Bring Forward"
        )
        panel.prompt = L10n.string("app_picker.prompt", "Choose")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let choose: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let target = ApplicationTarget(
                bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
                path: url.path,
                displayName: url.deletingPathExtension().lastPathComponent
            )
            preferences.setApplication(target, for: gesture)
            coordinator.refresh()
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: choose)
        } else {
            panel.begin(completionHandler: choose)
        }
    }
}

private struct SliderSetting: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Slider(value: $value, in: range) { Text(title) }
                .labelsHidden()
                .frame(width: 150)
            Text(valueText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

private struct ActivityLogView: View {
    @ObservedObject var log: ActivityLog
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("navigation.activity_log", "Activity Log"))
                    .font(.headline)
                Spacer()
                Toggle(L10n.string("activity_log.enable", "Enable Logging"), isOn: Binding(
                    get: { log.isEnabled },
                    set: { log.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .help(L10n.string(
                    "activity_log.retention",
                    "Keeps up to 1,000 recent events from the current app session."
                ))
            }

            if log.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(log.isEnabled
                         ? L10n.string("activity_log.empty.title", "No Events Yet")
                         : L10n.string("activity_log.disabled.title", "Logging Is Disabled"))
                        .font(.headline)
                    Text(log.isEnabled
                         ? L10n.string("activity_log.empty.description", "Events will appear here after you perform a gesture or reconnect.")
                         : L10n.string("activity_log.disabled.description", "Enable logging to record gestures, monitoring state, and sleep or wake events."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Table(log.entries.reversed()) {
                    TableColumn(L10n.string("activity_log.column.time", "Time")) { entry in
                        Text(entry.date.formatted(date: .numeric, time: .standard))
                            .monospacedDigit()
                    }
                    .width(min: 105, ideal: 165)
                    TableColumn(L10n.string("activity_log.column.category", "Category"), value: \.category)
                        .width(min: 75, ideal: 100)
                    TableColumn(L10n.string("activity_log.column.event", "Event")) { entry in
                        Text(entry.message)
                            .lineLimit(1)
                            .help(entry.message)
                    }
                    .width(min: 140, ideal: 270)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }

            HStack {
                Text(L10n.eventCount(log.entries.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied
                       ? L10n.string("activity_log.copied", "Copied")
                       : L10n.string("activity_log.copy_all", "Copy All")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.plainText, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .disabled(log.entries.isEmpty)
                Button(L10n.string("activity_log.clear", "Clear Log"), role: .destructive) {
                    log.clear()
                }
                .disabled(log.entries.isEmpty)
            }
        }
    }
}

private struct SettingsWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let attachedWindow = window
            DispatchQueue.main.async { [weak self] in
                self?.onWindow?(attachedWindow)
            }
        }
    }
}
