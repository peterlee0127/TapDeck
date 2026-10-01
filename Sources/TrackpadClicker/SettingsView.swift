import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var coordinator: GestureCoordinator

    @State private var showsAdvancedSettings = false
    @State private var selectedPage = SettingsPage.settings
    @State private var showsPermissionResetConfirmation = false
    @State private var showsRestoreDefaultsConfirmation = false
    @State private var permissionResetErrorMessage: String?

    private enum SettingsPage: String, CaseIterable, Hashable, Identifiable {
        case settings
        case test
        case logs

        var id: Self { self }

        var title: String {
            switch self {
            case .settings: L10n.string("navigation.gestures", "Gestures")
            case .test: L10n.string("navigation.test", "Test")
            case .logs: L10n.string("navigation.activity_log", "Activity Log")
            }
        }

        var subtitle: String {
            switch self {
            case .settings: L10n.string("navigation.gestures.subtitle", "Configure gestures and actions")
            case .test: L10n.string("navigation.test.subtitle", "Verify recognition in real time")
            case .logs: L10n.string("navigation.activity_log.subtitle", "Inspect monitoring and action events")
            }
        }

        var symbol: String {
            switch self {
            case .settings: "hand.tap"
            case .test: "waveform.path.ecg"
            case .logs: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 600)
        .onChange(of: selectedPage) { _, page in
            coordinator.setTesting(page == .test)
        }
        .onAppear { coordinator.setTesting(selectedPage == .test) }
        .onDisappear { coordinator.setTesting(false) }
        .onChange(of: coordinator.isTesting) { _, testing in
            if !testing && selectedPage == .test { selectedPage = .settings }
        }
        .confirmationDialog(
            L10n.string("dialog.reset_accessibility.title", "Reset Accessibility Permission?"),
            isPresented: $showsPermissionResetConfirmation,
            titleVisibility: .visible
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
        .confirmationDialog(
            L10n.string("dialog.restore_defaults.title", "Restore All Defaults?"),
            isPresented: $showsRestoreDefaultsConfirmation,
            titleVisibility: .visible
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

    private var sidebar: some View {
        List(selection: $selectedPage) {
            Section {
                ForEach(SettingsPage.allCases) { page in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title)
                            Text(page.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: page.symbol)
                            .symbolVariant(selectedPage == page ? .fill : .none)
                    }
                    .tag(page)
                    .padding(.vertical, 4)
                }
            } header: {
                Text(verbatim: "TapDeck")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarStatus
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 225)
    }

    private var sidebarStatus: some View {
        HStack(spacing: 9) {
            StatusDot(color: Color(nsColor: coordinator.status.color))
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.isTesting
                     ? L10n.string("status.testing", "Testing")
                     : coordinator.status.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(preferences.value.isEnabled
                     ? L10n.string("status.gesture_recognition_enabled", "Gesture recognition is enabled")
                     : L10n.string("status.gesture_recognition_paused", "Gesture recognition is paused"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedPage {
        case .settings: settingsPage
        case .test: testPage
        case .logs: logsPage
        }
    }

    private var settingsPage: some View {
        PageScrollView {
            pageHeader(
                title: L10n.string("page.gestures.title", "Gesture Settings"),
                subtitle: L10n.string(
                    "page.gestures.subtitle",
                    "Choose which trackpad gestures to recognize and what each gesture should do."
                ),
                symbol: "hand.tap.fill"
            ) {
                Toggle(L10n.string("page.gestures.enable", "Enable Recognition"), isOn: masterEnabled)
                    .toggleStyle(.switch)
            }

            statusContent
            gestureList
            advancedSettings
            footer
        }
    }

    private var testPage: some View {
        PageScrollView {
            pageHeader(
                title: L10n.string("page.test.title", "Gesture Test"),
                subtitle: L10n.string(
                    "page.test.subtitle",
                    "Gestures performed here show recognition results without running configured actions."
                ),
                symbol: "waveform.path.ecg"
            )

            statusContent
            testTrackpad
            testResults
        }
    }

    private var logsPage: some View {
        PageScrollView {
            pageHeader(
                title: L10n.string("page.activity_log.title", "Activity Log"),
                subtitle: L10n.string(
                    "page.activity_log.subtitle",
                    "Review recognition, monitoring, and system events from this app session."
                ),
                symbol: "list.bullet.rectangle.fill"
            )
            ActivityLogView(log: coordinator.activityLog)
                .cardSurface(padding: 16)
        }
    }

    private func pageHeader<Trailing: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.accentColor.opacity(0.18), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .tracking(-0.35)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func pageHeader(title: String, subtitle: String, symbol: String) -> some View {
        pageHeader(title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }

    @ViewBuilder
    private var statusContent: some View {
        if coordinator.status == .needsPermission {
            permissionCard
        } else if coordinator.status == .noTrackpad || coordinator.status == .eventMonitorUnavailable {
            warningCard
        } else {
            activityCard
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

    private var activityCard: some View {
        HStack(spacing: 12) {
            StatusDot(color: Color(nsColor: coordinator.status.color), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.isTesting
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
        .cardSurface(padding: 14, tint: Color(nsColor: coordinator.status.color).opacity(0.055))
    }

    private var activityDetail: String {
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

    private var gestureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: L10n.string("section.gestures.title", "Gestures and Actions"),
                detail: L10n.string("section.gestures.subtitle", "Enable a gesture, then choose the action it should perform.")
            )

            gestureGroup(
                title: L10n.string("gesture_group.two_finger", "Two Fingers"),
                note: L10n.string(
                    "gesture_group.two_finger.note",
                    "Disabled by default to avoid overriding system assistive controls"
                ),
                gestures: [.twoFingerClick, .twoFingerTap]
            )
            gestureGroup(
                title: L10n.string("gesture_group.three_finger", "Three Fingers"),
                gestures: [.threeFingerClick, .threeFingerTap]
            )
            gestureGroup(
                title: L10n.string("gesture_group.four_finger", "Four Fingers"),
                gestures: [.fourFingerClick, .fourFingerTap]
            )
            gestureGroup(
                title: L10n.string("gesture_group.force_touch", "Force Touch"),
                gestures: [.oneFingerForceTouch]
            )
        }
    }

    private func gestureGroup(
        title: String,
        note: String? = nil,
        gestures: [GestureKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.format(
                    "gesture_group.enabled_count",
                    "%lld / %lld",
                    Int64(gestures.filter { preferences.binding(for: $0).isEnabled }.count),
                    Int64(gestures.count)
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 6)

            ForEach(Array(gestures.enumerated()), id: \.element.id) { index, gesture in
                GestureRow(gesture: gesture)
                if index < gestures.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .cardSurface(padding: 0)
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $showsAdvancedSettings) {
            VStack(spacing: 0) {
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
                Divider().padding(.leading, 42)
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
                Divider().padding(.leading, 42)
                SettingsToggleRow(
                    symbol: "waveform",
                    title: L10n.string("advanced.haptic_feedback.title", "Haptic Feedback"),
                    detail: L10n.string("advanced.haptic_feedback.subtitle", "Provide one tactile confirmation after recognition"),
                    isOn: Binding(get: { preferences.value.hapticFeedback }, set: {
                        preferences.value.hapticFeedback = $0
                    })
                )

                Divider().padding(.leading, 42)
                if LaunchAtLoginController.isAvailable {
                    SettingsToggleRow(
                        symbol: "power",
                        title: L10n.string("advanced.launch_at_login.title", "Launch at Login"),
                        detail: L10n.string("advanced.launch_at_login.subtitle", "Start recognizing in the background after you sign in"),
                        isOn: Binding(get: { preferences.value.launchAtLogin }, set: {
                            preferences.value.launchAtLogin = $0
                            LaunchAtLoginController.setEnabled($0)
                        })
                    )
                } else {
                    SettingsInfoRow(
                        symbol: "hammer",
                        title: L10n.string("advanced.launch_at_login.title", "Launch at Login"),
                        detail: L10n.string("advanced.launch_at_login.debug_unavailable", "Unavailable in debug builds")
                    )
                }

                Divider().padding(.leading, 42)
                HStack(spacing: 8) {
                    Button(L10n.string("advanced.open_trackpad_settings", "Open Trackpad Settings")) {
                        AccessibilityController.openTrackpadSettings()
                    }
                    Button(L10n.string("advanced.reset_accessibility", "Reset Accessibility Permission"), role: .destructive) {
                        showsPermissionResetConfirmation = true
                    }
                    Spacer()
                    Menu {
                        Button(L10n.string("advanced.restore_defaults", "Restore All Defaults"), role: .destructive) {
                            showsRestoreDefaultsConfirmation = true
                        }
                        Divider()
                        Button(L10n.string("advanced.quit", "Quit TapDeck"), role: .destructive) {
                            NSApp.terminate(nil)
                        }
                    } label: {
                        Label(L10n.string("common.more", "More"), systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .padding(.top, 8)
        } label: {
            Label(L10n.string("advanced.title", "Advanced Settings"), systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(16)
        .cardSurface(padding: 0)
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

    private var permissionCard: some View {
        NoticeCard(
            symbol: "lock.shield.fill",
            color: .orange,
            title: L10n.string("permission.title", "Accessibility Permission Required"),
            message: L10n.string(
                "permission.message",
                "This permission is used only to emit mouse and keyboard actions. Touch data never leaves this Mac."
            )
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

    private var warningCard: some View {
        NoticeCard(
            symbol: "exclamationmark.triangle.fill",
            color: .orange,
            title: coordinator.status == .noTrackpad
                ? L10n.string("warning.no_trackpad.title", "Trackpad Not Found")
                : L10n.string("warning.event_monitor.title", "Could Not Start Event Monitoring"),
            message: coordinator.status == .noTrackpad
                ? L10n.string("warning.no_trackpad.message", "Make sure a trackpad is connected, then reconnect.")
                : L10n.string(
                    "warning.event_monitor.message",
                    "Make sure Accessibility permission is allowed, then reconnect."
                )
        ) {
            Button(L10n.string("common.reconnect", "Reconnect")) { coordinator.refresh() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var testTrackpad: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.separator.opacity(0.65), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 7)

                HStack(spacing: 20) {
                    ForEach(0..<coordinator.fingerCount, id: \.self) { index in
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.16))
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(Color.accentColor.gradient)
                                .frame(width: 22, height: 22)
                                .shadow(color: Color.accentColor.opacity(0.28), radius: 5)
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel(
                            L10n.format("accessibility.finger_number", "Finger %d", index + 1)
                        )
                    }
                }
            }
            .frame(maxWidth: 430)
            .aspectRatio(2.35, contentMode: .fit)
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
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 22)
    }

    private var testResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeading(
                    title: L10n.string("test.results.title", "Recognition Results"),
                    detail: L10n.string("test.results.subtitle", "This test session")
                )
                Spacer()
                Button(L10n.string("test.clear_results", "Clear Results")) {
                    coordinator.clearTestResults()
                }
                    .disabled(coordinator.detectedGestures.isEmpty && coordinator.lastGesture == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()

            ForEach(Array(GestureKind.allCases.enumerated()), id: \.element.id) { index, gesture in
                let recognized = coordinator.detectedGestures.contains(gesture)
                HStack(spacing: 12) {
                    Image(systemName: gesture.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(recognized ? Color.accentColor : .secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            recognized ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    Text(gesture.title)
                        .fontWeight(.medium)
                    Spacer()
                    Label(
                        recognized
                            ? L10n.string("test.result.recognized", "Recognized")
                            : L10n.string("test.result.waiting", "Waiting"),
                        systemImage: recognized ? "checkmark.circle.fill" : "circle.dotted"
                    )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(recognized ? .green : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: recognized)

                if index < GestureKind.allCases.count - 1 {
                    Divider().padding(.leading, 58)
                }
            }

            if let lastGesture = coordinator.lastGesture {
                Divider()
                Label(
                    L10n.format("format.last_recognized", "Last recognized: %@", lastGesture.title),
                    systemImage: "clock.arrow.circlepath"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
        .cardSurface(padding: 0)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                L10n.string(
                    "footer.gesture_explanation",
                    "Taps trigger after a quick touch and release; physical clicks require pressing the trackpad down."
                ),
                systemImage: "info.circle"
            )
            Label(
                L10n.string(
                    "footer.privacy",
                    "All recognition happens locally, with no networking, analytics, or telemetry."
                ),
                systemImage: "hand.raised.fill"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 2)
    }
}

private struct PageScrollView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SectionHeading: View {
    let title: String
    let detail: String

    init(title: String, detail: String = "") {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            .overlay {
                Circle().stroke(color.opacity(0.22), lineWidth: 4)
            }
            .padding(3)
            .accessibilityHidden(true)
    }
}

private struct NoticeCard<Actions: View>: View {
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
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
        }
        .cardSurface(padding: 14, tint: color.opacity(0.065))
    }
}

private struct GestureRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var coordinator: GestureCoordinator
    let gesture: GestureKind

    private var binding: GestureBinding { preferences.binding(for: gesture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: gesture.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(binding.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        binding.isEnabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.title)
                        .fontWeight(.medium)
                    Text(gesture.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker(L10n.string("gesture_row.action", "Action"), selection: Binding(get: { binding.action }, set: { action in
                    preferences.update(gesture, action: action)
                    coordinator.refresh()
                })) {
                    ForEach(GestureAction.allCases) { action in
                        Label(action.title, systemImage: action.symbol).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 182)
                .disabled(!binding.isEnabled)

                Toggle(
                    L10n.format("gesture_row.enable", "Enable %@", gesture.title),
                    isOn: Binding(get: { binding.isEnabled }, set: {
                    preferences.update(gesture, enabled: $0)
                    coordinator.refresh()
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
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
                .padding(.leading, 46)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(binding.isEnabled ? 1 : 0.72)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: binding.action)
        .animation(.easeOut(duration: 0.12), value: binding.isEnabled)
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
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let target = ApplicationTarget(
                bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
                path: url.path,
                displayName: url.deletingPathExtension().lastPathComponent
            )
            preferences.setApplication(target, for: gesture)
            coordinator.refresh()
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
            Image(systemName: "dial.low")
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Slider(value: $value, in: range)
                .frame(width: 150)
            Text(valueText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsToggleRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsInfoRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ActivityLogView: View {
    @ObservedObject var log: ActivityLog
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(L10n.string("activity_log.enable", "Enable Logging"), isOn: Binding(
                        get: { log.isEnabled },
                        set: { log.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    Text(L10n.string(
                        "activity_log.retention",
                        "Keeps up to 1,000 recent events from the current app session."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusDot(color: log.isEnabled ? .green : .secondary)
                Text(log.isEnabled
                     ? L10n.string("activity_log.recording", "Recording")
                     : L10n.string("activity_log.paused", "Paused"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(L10n.eventCount(log.entries.count))
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.plainText, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(
                        copied
                            ? L10n.string("activity_log.copied", "Copied")
                            : L10n.string("activity_log.copy_all", "Copy All"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .disabled(log.entries.isEmpty)
                Button(L10n.string("activity_log.clear", "Clear Log"), role: .destructive) {
                    log.clear()
                }
                    .disabled(log.entries.isEmpty)
            }

            Divider()

            if log.entries.isEmpty {
                ContentUnavailableView(
                    log.isEnabled
                        ? L10n.string("activity_log.empty.title", "No Events Yet")
                        : L10n.string("activity_log.disabled.title", "Logging Is Disabled"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(log.isEnabled
                        ? L10n.string(
                            "activity_log.empty.description",
                            "Events will appear here after you perform a gesture or reconnect."
                        )
                        : L10n.string(
                            "activity_log.disabled.description",
                            "Enable logging to record gestures, monitoring state, and sleep or wake events."
                        ))
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(log.entries.reversed()) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 12, height: 18)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.category).fontWeight(.semibold)
                                    Spacer()
                                    Text(entry.date.formatted(date: .numeric, time: .standard))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                Text(entry.message)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 10)
                        Divider().padding(.leading, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func cardSurface(padding: CGFloat, tint: Color = .clear) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.separator.opacity(0.48), lineWidth: 0.75)
                    }
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}
