@preconcurrency import AppKit
@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class GestureCoordinator: NSObject, ObservableObject {
    enum Status: Equatable {
        case stopped
        case needsPermission
        case noTrackpad
        case eventMonitorUnavailable
        case listening

        var title: String {
            switch self {
            case .stopped: L10n.string("status.stopped", "Paused")
            case .needsPermission: L10n.string("status.needs_permission", "Accessibility Permission Required")
            case .noTrackpad: L10n.string("status.no_trackpad", "Trackpad Not Found")
            case .eventMonitorUnavailable: L10n.string("status.event_monitor_unavailable", "Event Monitor Unavailable")
            case .listening: L10n.string("status.listening", "Listening for Gestures")
            }
        }

        var color: NSColor {
            switch self {
            case .stopped: .secondaryLabelColor
            case .needsPermission: .systemOrange
            case .noTrackpad, .eventMonitorUnavailable: .systemRed
            case .listening: .systemGreen
            }
        }
    }

    let activityLog = ActivityLog()

    @Published private(set) var status: Status = .stopped {
        didSet {
            if oldValue != status {
                activityLog.record(L10n.string("log.category.monitoring", "Monitoring"), status.title)
            }
        }
    }
    @Published private(set) var fingerCount = 0
    @Published private(set) var lastGesture: GestureKind?
    @Published private(set) var activityPulse = 0
    @Published private(set) var detectedGestures: Set<GestureKind> = []
    @Published private(set) var isTesting = false

    private let preferences: PreferencesStore
    private let bridge = MultitouchBridge()
    private let performer = ActionPerformer()
    private var recognizer = GestureRecognizer()
    private var pressureRecognizer = PressureStageRecognizer()
    private var physicalClickPressureRecognizer = PhysicalClickPressureRecognizer()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var globalPressureMonitor: Any?
    private var localPressureMonitor: Any?
    private var healthTask: Task<Void, Never>?
    @Published private(set) var lastRecovery: Date?
    private var permissionPollingTask: Task<Void, Never>?
    private var currentFingerCount = 0
    private var pendingPhysicalClickFingerCount: Int?
    private var suppressedMouseUpType: CGEventType?
    private var lastForceTouchTriggerTime = 0.0
    private var lastProcessedFrameTimestamp = -Double.infinity

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        super.init()
        bridge.delegate = self
    }

    func refresh() {
        stop()
        guard isTesting || preferences.value.isEnabled else { return }
        guard isTesting || hasEnabledGestures else { return }
        startHealthMonitoring()
        guard AccessibilityController.isTrusted else {
            status = .needsPermission
            startPermissionPolling()
            return
        }
        recognizer.tapDuration = preferences.value.tapDuration
        recognizer.movementTolerance = Float(preferences.value.movementTolerance)
        guard bridge.start() else {
            status = .noTrackpad
            return
        }
        let eventTapReady = !(isTesting || hasEnabledPhysicalClick) || installEventTap()
        let pressureMonitorReady = !(isTesting || hasEnabledPhysicalClick || isEnabled(.oneFingerForceTouch))
            || installPressureMonitors()
        guard eventTapReady, pressureMonitorReady else {
            bridge.stop()
            removeEventTap()
            removePressureMonitors()
            status = .eventMonitorUnavailable
            return
        }
        status = .listening
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil
        permissionPollingTask?.cancel()
        permissionPollingTask = nil
        bridge.stop()
        removeEventTap()
        removePressureMonitors()
        recognizer.reset()
        pressureRecognizer.reset()
        physicalClickPressureRecognizer.reset()
        fingerCount = 0
        currentFingerCount = 0
        lastProcessedFrameTimestamp = -Double.infinity
        suppressedMouseUpType = nil
        pendingPhysicalClickFingerCount = nil
        lastForceTouchTriggerTime = 0
        status = .stopped
    }

    func requestPermission() {
        AccessibilityController.request()
        status = .needsPermission
        startPermissionPolling()
    }

    func setTesting(_ enabled: Bool) {
        guard isTesting != enabled else { return }
        activityLog.record(
            L10n.string("log.category.testing", "Testing"),
            enabled
                ? L10n.string("log.testing.started", "Entered test mode. Configured actions will not run.")
                : L10n.string("log.testing.stopped", "Exited test mode.")
        )
        isTesting = enabled
        if enabled { clearTestResults() }
        refresh()
    }

    func clearTestResults() {
        detectedGestures.removeAll()
        lastGesture = nil
    }

    func reconnect(reason: String? = nil) {
        activityLog.record(
            L10n.string("log.category.reconnect", "Reconnect"),
            reason ?? L10n.string("log.reconnect.manual", "Manual reconnect")
        )
        lastRecovery = Date()
        refresh()
    }

    func updateSensitivity() {
        recognizer.tapDuration = preferences.value.tapDuration
        recognizer.movementTolerance = Float(preferences.value.movementTolerance)
        recognizer.reset()
    }

    private func startHealthMonitoring() {
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if !AccessibilityController.isTrusted {
                    refresh()
                    return
                }
                // Silence is also normal on an idle trackpad. Reopen conservatively
                // after a minute, without treating silence as an error in the UI.
                if status == .noTrackpad || status == .eventMonitorUnavailable
                    || bridge.secondsSinceLastCallback >= 60 {
                    reconnect(reason: L10n.string(
                        "log.reconnect.health_check",
                        "Health check: monitoring was unavailable or no touch data arrived for 60 seconds (the trackpad may simply be idle)."
                    ))
                    return
                }
                if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    if !CGEvent.tapIsEnabled(tap: eventTap) {
                        reconnect(reason: L10n.string(
                            "log.reconnect.event_monitor_failed",
                            "The event monitor could not be re-enabled."
                        ))
                        return
                    }
                }
            }
        }
    }

    private func startPermissionPolling() {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                if AccessibilityController.isTrusted {
                    refresh()
                    return
                }
            }
        }
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            activityLog.record(
                L10n.string("log.category.monitoring", "Monitoring"),
                type == .tapDisabledByTimeout
                    ? L10n.string("log.monitoring.timeout", "The event monitor timed out. Attempting to re-enable it.")
                    : L10n.string("log.monitoring.disabled", "The system disabled the event monitor. Attempting to re-enable it.")
            )
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != 0x5450434C else { return Unmanaged.passUnretained(event) }

        if type == .leftMouseDown || type == .rightMouseDown {
            let fingerCount = bridge.latestFingerCount
            guard let gesture = physicalClickGesture(for: fingerCount), canRecognize(gesture) else {
                return Unmanaged.passUnretained(event)
            }
            pendingPhysicalClickFingerCount = fingerCount
            suppressedMouseUpType = type == .rightMouseDown ? .rightMouseUp : .leftMouseUp
            triggerPhysicalClickIfConfirmed(fingerCount: fingerCount)
            return nil
        }
        if type == suppressedMouseUpType {
            suppressedMouseUpType = nil
            pendingPhysicalClickFingerCount = nil
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    private func installEventTap() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, opaque in
                guard let opaque else { return Unmanaged.passUnretained(event) }
                let coordinator = Unmanaged<GestureCoordinator>.fromOpaque(opaque).takeUnretainedValue()
                return MainActor.assumeIsolated { coordinator.handleEvent(type: type, event: event) }
            },
            userInfo: opaque
        )
        guard let eventTap else { return false }
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    @discardableResult
    private func installPressureMonitors() -> Bool {
        localPressureMonitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePressure(event) }
            return event
        }
        globalPressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .pressure) { [weak self] event in
            // AppKit documents global monitor handlers as running on the main thread.
            MainActor.assumeIsolated { self?.handlePressure(event) }
        }
        return localPressureMonitor != nil && globalPressureMonitor != nil
    }

    private func handlePressure(_ event: NSEvent) {
        let fingerCount = bridge.latestFingerCount
        physicalClickPressureRecognizer.process(stage: event.stage, fingerCount: fingerCount)
        if pendingPhysicalClickFingerCount == fingerCount {
            triggerPhysicalClickIfConfirmed(fingerCount: fingerCount)
        }

        guard let detection = pressureRecognizer.process(
            stage: event.stage,
            fingerCount: fingerCount,
            timestamp: event.timestamp
        ) else { return }
        trigger(detection.gesture)
    }

    private func triggerPhysicalClickIfConfirmed(fingerCount: Int) {
        guard physicalClickPressureRecognizer.consume(fingerCount: fingerCount),
              let detection = recognizer.physicalClick(
                fingerCount: fingerCount,
                timestamp: ProcessInfo.processInfo.systemUptime
              )
        else { return }
        pendingPhysicalClickFingerCount = nil
        trigger(detection.gesture)
    }

    private func removeEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
    }

    private func removePressureMonitors() {
        if let globalPressureMonitor { NSEvent.removeMonitor(globalPressureMonitor) }
        if let localPressureMonitor { NSEvent.removeMonitor(localPressureMonitor) }
        globalPressureMonitor = nil
        localPressureMonitor = nil
    }

    private func isEnabled(_ gesture: GestureKind) -> Bool {
        let binding = preferences.value.binding(for: gesture)
        return preferences.value.isEnabled && binding.isEnabled && binding.action != .none
    }

    private var hasEnabledGestures: Bool {
        GestureKind.allCases.contains(where: isEnabled)
    }

    private var hasEnabledPhysicalClick: Bool {
        [.twoFingerClick, .threeFingerClick, .fourFingerClick].contains(where: isEnabled)
    }

    private func physicalClickGesture(for fingerCount: Int) -> GestureKind? {
        switch fingerCount {
        case 2: .twoFingerClick
        case 3: .threeFingerClick
        case 4: .fourFingerClick
        default: nil
        }
    }

    private func canRecognize(_ gesture: GestureKind) -> Bool {
        isTesting || isEnabled(gesture)
    }

    private func trigger(_ gesture: GestureKind) {
        guard canRecognize(gesture) else { return }
        if gesture == .oneFingerForceTouch {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastForceTouchTriggerTime > 0.5 else { return }
            lastForceTouchTriggerTime = now
        }
        lastGesture = gesture
        detectedGestures.insert(gesture)
        activityPulse += 1
        activityLog.record(
            L10n.string("log.category.gesture", "Gesture"),
            isTesting
                ? L10n.format("log.gesture.detected_testing", "Detected %@ (test only; no action)", gesture.title)
                : L10n.format("log.gesture.detected", "Detected %@", gesture.title)
        )
        guard !isTesting else { return }
        let binding = preferences.value.binding(for: gesture)
        activityLog.record(
            L10n.string("log.category.action", "Action"),
            L10n.format(
                "log.action.requested",
                "Requested: %@ (this does not confirm that the target app completed the action)",
                binding.action.title
            )
        )
        performer.perform(binding, haptic: preferences.value.hapticFeedback)
    }
}

extension GestureCoordinator: MultitouchBridgeDelegate {
    nonisolated func multitouchBridge(_ bridge: MultitouchBridge, received frame: TouchFrame) {
        let sessionID = bridge.sessionID
        Task { @MainActor [weak self] in
            guard let self, status == .listening, self.bridge.sessionID == sessionID else { return }
            if lastProcessedFrameTimestamp == -Double.infinity {
                activityLog.record(
                    L10n.string("log.category.trackpad", "Trackpad"),
                    L10n.string("log.trackpad.received_data", "Touch data received for this connection.")
                )
            }
            if frame.timestamp < lastProcessedFrameTimestamp - 1 {
                activityLog.record(
                    L10n.string("log.category.trackpad", "Trackpad"),
                    L10n.string("log.trackpad.timestamp_reset", "The device timestamp reset. Gesture recognition state was reset.")
                )
                recognizer.reset()
                pressureRecognizer.reset()
                physicalClickPressureRecognizer.reset()
                pendingPhysicalClickFingerCount = nil
                lastProcessedFrameTimestamp = -Double.infinity
            }
            guard frame.timestamp >= lastProcessedFrameTimestamp else { return }
            lastProcessedFrameTimestamp = frame.timestamp
            currentFingerCount = frame.touches.count
            if fingerCount != frame.touches.count {
                fingerCount = frame.touches.count
            }
            if frame.touches.isEmpty {
                pressureRecognizer.reset()
                physicalClickPressureRecognizer.reset()
            }
            for detection in recognizer.process(frame: frame) where canRecognize(detection.gesture) {
                trigger(detection.gesture)
            }
        }
    }
}
