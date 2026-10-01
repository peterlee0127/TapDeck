import CoreGraphics
import Foundation
import Testing
@testable import TapDeck

struct GestureRecognizerTests {
    private func frame(_ time: Double, count: Int, x: Float = 0.5, pressure: Float = 0.4) -> TouchFrame {
        TouchFrame(timestamp: time, touches: (0..<count).map {
            TouchPoint(id: Int32($0), x: x + Float($0) * 0.01, y: 0.5, pressure: pressure)
        })
    }

    @Test @MainActor func loggingTogglePersistsAndStopsNewEntries() throws {
        let suite = "ActivityLogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ActivityLog(defaults: defaults)
        #expect(!log.isEnabled)
        log.record("測試", "不應記錄")
        #expect(log.entries.isEmpty)
        log.setEnabled(true)
        log.record("手勢", "三指輕點")
        #expect(log.plainText.contains("三指輕點"))
        #expect(ActivityLog(defaults: defaults).isEnabled)
        log.setEnabled(false)
        let count = log.entries.count
        log.record("測試", "不應新增")
        #expect(log.entries.count == count)
        #expect(!ActivityLog(defaults: defaults).isEnabled)
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test @MainActor func loggingKeepsOnlyRecentEntriesAndClearsWhileEnabled() throws {
        let suite = "ActivityLogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ActivityLog(defaults: defaults)
        log.setEnabled(true)
        for index in 0...ActivityLog.capacity { log.record("測試", "事件 \(index)") }
        #expect(log.entries.count == ActivityLog.capacity)
        #expect(log.entries.first?.message == "事件 1")
        #expect(log.entries.last?.message == "事件 1000")
        log.clear()
        #expect(log.entries.isEmpty)
        #expect(log.isEnabled)
        log.record("測試", "繼續記錄")
        #expect(log.entries.count == 1)
    }

    @Test func frameDeliveryResumesAfterDeviceClockRestarts() {
        var gate = TouchFrameDeliveryGate()
        let beforeSleep = gate.shouldDeliver(frame(9000, count: 3))
        let restarted = gate.shouldDeliver(frame(0.1, count: 3))
        let nextFrame = gate.shouldDeliver(frame(0.12, count: 3))
        let released = gate.shouldDeliver(frame(0.13, count: 0))
        #expect(beforeSleep && restarted && nextFrame && released)
    }

    @Test func slightlyOutOfOrderFramesStayThrottled() {
        var gate = TouchFrameDeliveryGate()
        let first = gate.shouldDeliver(frame(10, count: 3))
        let stale = gate.shouldDeliver(frame(9.99, count: 3))
        let next = gate.shouldDeliver(frame(10.02, count: 3))
        #expect(first && !stale && next)
    }

    @Test func recognizesThreeFingerTap() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.process(frame: frame(1, count: 3)).isEmpty)
        #expect(recognizer.process(frame: frame(1.12, count: 0)).isEmpty)
        #expect(recognizer.process(frame: frame(1.13, count: 0)) == [
            GestureDetection(gesture: .threeFingerTap, timestamp: 1.13)
        ])
    }

    @Test func recognizesTwoFingerTap() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.process(frame: frame(0.5, count: 2)).isEmpty)
        #expect(recognizer.process(frame: frame(0.62, count: 0)).isEmpty)
        #expect(recognizer.process(frame: frame(0.63, count: 0)).first?.gesture == .twoFingerTap)
    }

    @Test func staggeredThirdFingerPromotesTwoFingerCandidate() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(0.7, count: 2))
        _ = recognizer.process(frame: frame(0.75, count: 3))
        _ = recognizer.process(frame: frame(0.85, count: 0))
        let result = recognizer.process(frame: frame(0.86, count: 0))
        #expect(result.map(\.gesture) == [.threeFingerTap])
    }

    @Test func recognizesFourFingerTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2, count: 4))
        _ = recognizer.process(frame: frame(2.18, count: 0))
        #expect(recognizer.process(frame: frame(2.19, count: 0)).first?.gesture == .fourFingerTap)
    }

    @Test func recognizesAsynchronousFourFingerLandingAndLift() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2.00, count: 1))
        _ = recognizer.process(frame: frame(2.02, count: 2))
        _ = recognizer.process(frame: frame(2.04, count: 3))
        _ = recognizer.process(frame: frame(2.06, count: 4))
        _ = recognizer.process(frame: frame(2.12, count: 3))
        #expect(recognizer.process(frame: frame(2.14, count: 2)).first?.gesture == .fourFingerTap)
        _ = recognizer.process(frame: frame(2.16, count: 1))
        #expect(recognizer.process(frame: frame(2.18, count: 0)).isEmpty)
    }

    @Test func recognizesAsynchronousThreeFingerLandingAndLift() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2.5, count: 1))
        _ = recognizer.process(frame: frame(2.52, count: 2))
        _ = recognizer.process(frame: frame(2.54, count: 3))
        _ = recognizer.process(frame: frame(2.62, count: 2))
        #expect(recognizer.process(frame: frame(2.64, count: 1)).first?.gesture == .threeFingerTap)
        #expect(recognizer.process(frame: frame(2.66, count: 0)).isEmpty)
    }

    @Test func liftingContactsDoNotConsumeTapDuration() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2.7, count: 3))
        _ = recognizer.process(frame: frame(2.8, count: 2))
        #expect(recognizer.process(frame: frame(2.81, count: 2)).first?.gesture == .threeFingerTap)
        _ = recognizer.process(frame: frame(3.2, count: 1))
        #expect(recognizer.process(frame: frame(3.3, count: 0)).isEmpty)
    }

    @Test func oneFrameFingerDropDoesNotEndTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(3.4, count: 3))
        _ = recognizer.process(frame: frame(3.45, count: 2))
        _ = recognizer.process(frame: frame(3.46, count: 3))
        _ = recognizer.process(frame: frame(3.5, count: 0))
        #expect(recognizer.process(frame: frame(3.51, count: 0)).first?.gesture == .threeFingerTap)
    }

    @Test func staggeredLandingDoesNotConsumeThreeFingerTapWindow() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2.7, count: 1))
        _ = recognizer.process(frame: frame(2.85, count: 2))
        _ = recognizer.process(frame: frame(3.0, count: 3))
        _ = recognizer.process(frame: frame(3.2, count: 0))
        #expect(recognizer.process(frame: frame(3.21, count: 0)).first?.gesture == .threeFingerTap)
    }

    @Test func movementBeforeAllFingersLandDoesNotRejectTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(3.3, count: 1, x: 0.2))
        _ = recognizer.process(frame: frame(3.4, count: 2, x: 0.4))
        _ = recognizer.process(frame: frame(3.5, count: 3, x: 0.5))
        _ = recognizer.process(frame: frame(3.6, count: 3, x: 0.51))
        _ = recognizer.process(frame: frame(3.65, count: 0))
        #expect(recognizer.process(frame: frame(3.66, count: 0)).first?.gesture == .threeFingerTap)
    }

    @Test func rejectsFiveFingerSequence() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(2.8, count: 4))
        _ = recognizer.process(frame: frame(2.82, count: 5))
        _ = recognizer.process(frame: frame(2.9, count: 0))
        #expect(recognizer.process(frame: frame(2.91, count: 0)).isEmpty)
    }

    @Test func rejectsSlowOrMovingTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(3, count: 3))
        _ = recognizer.process(frame: frame(3.4, count: 0))
        #expect(recognizer.process(frame: frame(3.41, count: 0)).isEmpty)

        _ = recognizer.process(frame: frame(4, count: 3, x: 0.2))
        _ = recognizer.process(frame: frame(4.1, count: 3, x: 0.4))
        _ = recognizer.process(frame: frame(4.15, count: 0))
        #expect(recognizer.process(frame: frame(4.16, count: 0)).isEmpty)
    }

    @Test func emptyFrameDropoutDoesNotPrematurelyFinishTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(4.5, count: 3))
        #expect(recognizer.process(frame: frame(4.52, count: 0)).isEmpty)
        _ = recognizer.process(frame: frame(4.53, count: 3))
        #expect(recognizer.process(frame: frame(4.6, count: 0)).isEmpty)
        #expect(recognizer.process(frame: frame(4.61, count: 0)).first?.gesture == .threeFingerTap)
    }

    @Test func oneNoisyFingerDoesNotRejectOtherwiseStableTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(4.7, count: 3))
        var noisyFrame = frame(4.75, count: 3)
        noisyFrame.touches[0].x += 0.06
        _ = recognizer.process(frame: noisyFrame)
        _ = recognizer.process(frame: frame(4.8, count: 0))
        #expect(recognizer.process(frame: frame(4.81, count: 0)).first?.gesture == .threeFingerTap)
    }

    @Test func centroidMovementStillRejectsSwipe() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(4.9, count: 3))
        _ = recognizer.process(frame: frame(4.95, count: 3, x: 0.56))
        _ = recognizer.process(frame: frame(5.0, count: 0))
        #expect(recognizer.process(frame: frame(5.01, count: 0)).isEmpty)
    }

    @Test func shapeChangeStillRejectsPinchWithStableCentroid() {
        var recognizer = GestureRecognizer()
        var initialFrame = frame(5.1, count: 3)
        initialFrame.touches[0].x = 0.3
        initialFrame.touches[1].x = 0.5
        initialFrame.touches[2].x = 0.7
        _ = recognizer.process(frame: initialFrame)

        var pinchedFrame = initialFrame
        pinchedFrame.timestamp = 5.15
        pinchedFrame.touches[0].x += 0.15
        pinchedFrame.touches[2].x -= 0.15
        _ = recognizer.process(frame: pinchedFrame)
        _ = recognizer.process(frame: frame(5.2, count: 0))
        #expect(recognizer.process(frame: frame(5.21, count: 0)).isEmpty)
    }

    @Test func physicalClickDoesNotAlsoBecomeTap() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(5, count: 3))
        #expect(recognizer.physicalClick(fingerCount: 3, timestamp: 5.05)?.gesture == .threeFingerClick)
        #expect(recognizer.process(frame: frame(5.1, count: 0)).isEmpty)
    }

    @Test func recognizesTwoThreeAndFourFingerPhysicalClicks() {
        let expectations: [(Int, GestureKind)] = [
            (2, .twoFingerClick),
            (3, .threeFingerClick),
            (4, .fourFingerClick),
        ]
        for (fingerCount, gesture) in expectations {
            var recognizer = GestureRecognizer()
            _ = recognizer.process(frame: frame(5.5, count: fingerCount))
            #expect(recognizer.physicalClick(
                fingerCount: fingerCount,
                timestamp: 5.55
            )?.gesture == gesture)
            #expect(recognizer.physicalClick(fingerCount: fingerCount, timestamp: 5.56) == nil)
        }
    }

    @Test func holdingThreeFingersDoesNotProduceRemovedLongTouch() {
        var recognizer = GestureRecognizer()
        _ = recognizer.process(frame: frame(8, count: 3))
        #expect(recognizer.process(frame: frame(8.7, count: 3)).isEmpty)
        #expect(recognizer.process(frame: frame(8.75, count: 3)).isEmpty)
        #expect(recognizer.process(frame: frame(8.8, count: 0)).isEmpty)
    }

    @Test func forceTouchLatchesUntilRelease() {
        var recognizer = PressureStageRecognizer()
        #expect(recognizer.process(stage: 1, fingerCount: 1, timestamp: 6) == nil)
        #expect(recognizer.process(stage: 2, fingerCount: 1, timestamp: 6.1)?.gesture == .oneFingerForceTouch)
        #expect(recognizer.process(stage: 2, fingerCount: 1, timestamp: 6.2) == nil)
        #expect(recognizer.process(stage: 0, fingerCount: 1, timestamp: 6.3) == nil)
        #expect(recognizer.process(stage: 2, fingerCount: 1, timestamp: 6.4)?.gesture == .oneFingerForceTouch)
    }

    @Test func forceTouchRequiresExactlyOneFinger() {
        var recognizer = PressureStageRecognizer()
        #expect(recognizer.process(stage: 2, fingerCount: 2, timestamp: 7) == nil)
        #expect(recognizer.process(stage: 2, fingerCount: 0, timestamp: 7.1) == nil)
    }

    @Test func physicalClickPressureRequiresStageOneAndExactCount() {
        var recognizer = PhysicalClickPressureRecognizer()
        recognizer.process(stage: 0, fingerCount: 3)
        let stageZeroResult = recognizer.consume(fingerCount: 3)
        #expect(!stageZeroResult)
        recognizer.process(stage: 1, fingerCount: 3)
        let wrongCountResult = recognizer.consume(fingerCount: 2)
        let firstConsumeResult = recognizer.consume(fingerCount: 3)
        let duplicateResult = recognizer.consume(fingerCount: 3)
        #expect(!wrongCountResult)
        #expect(firstConsumeResult)
        #expect(!duplicateResult)
        recognizer.process(stage: 0, fingerCount: 0)
        recognizer.process(stage: 1, fingerCount: 3)
        let afterResetResult = recognizer.consume(fingerCount: 3)
        #expect(afterResetResult)
    }

    @Test func frameDeliveryGateThrottlesSteadyFramesButNotContactChanges() {
        var gate = TouchFrameDeliveryGate(minimumInterval: 1.0 / 60.0)
        let first = gate.shouldDeliver(frame(10, count: 3))
        let throttled = gate.shouldDeliver(frame(10.008, count: 3))
        let fingerLift = gate.shouldDeliver(frame(10.009, count: 2))
        let fullLift = gate.shouldDeliver(frame(10.010, count: 0))
        let earlyEmpty = gate.shouldDeliver(frame(10.018, count: 0))
        let debouncedEmpty = gate.shouldDeliver(frame(10.030, count: 0))
        #expect(first)
        #expect(!throttled)
        #expect(fingerLift)
        #expect(fullLift)
        #expect(!earlyEmpty)
        #expect(debouncedEmpty)
    }

    @Test func everyConfiguredActionMapsToExpectedSystemEvent() {
        #expect(GestureAction.middleClick.command == .mouse(
            button: .center,
            down: .otherMouseDown,
            up: .otherMouseUp
        ))
        #expect(GestureAction.leftClick.command == .mouse(
            button: .left,
            down: .leftMouseDown,
            up: .leftMouseUp
        ))
        #expect(GestureAction.rightClick.command == .mouse(
            button: .right,
            down: .rightMouseDown,
            up: .rightMouseUp
        ))
        #expect(GestureAction.quickLook.command == .key(keyCode: 49, flags: []))
        #expect(GestureAction.missionControl.command == .systemApplication(
            bundleIdentifier: "com.apple.exposelauncher",
            fallbackPath: "/System/Applications/Mission Control.app"
        ))
        #expect(GestureAction.appExpose.command == .key(keyCode: 125, flags: .maskControl))
        #expect(GestureAction.showDesktop.command == .key(keyCode: 103, flags: []))
        #expect(GestureAction.openApplication.command == .application)
        #expect(GestureAction.none.command == .none)
    }

    @Test func defaultPreferencesCoverAllRequestedGestures() {
        let defaults = AppPreferences()
        #expect(defaults.binding(for: .twoFingerClick) == .init(isEnabled: false, action: .none))
        #expect(defaults.binding(for: .twoFingerTap) == .init(isEnabled: false, action: .none))
        #expect(defaults.binding(for: .threeFingerClick) == .init(isEnabled: true, action: .middleClick))
        #expect(defaults.binding(for: .threeFingerTap) == .init(isEnabled: true, action: .middleClick))
        #expect(defaults.binding(for: .threeFingerLongTouch) == .init(isEnabled: false, action: .none))
        #expect(defaults.binding(for: .fourFingerTap) == .init(isEnabled: true, action: .missionControl))
        #expect(defaults.binding(for: .fourFingerClick) == .init(isEnabled: false, action: .none))
        #expect(defaults.binding(for: .oneFingerForceTouch) == .init(isEnabled: true, action: .quickLook))
    }

    @Test func testPageGesturesAreOrderedByFingerCount() {
        #expect(GestureKind.allCases == [
            .oneFingerForceTouch,
            .twoFingerClick, .twoFingerTap,
            .threeFingerClick, .threeFingerTap,
            .fourFingerClick, .fourFingerTap,
        ])
    }

    @Test
    @MainActor
    func gestureBindingsPersistIndependently() throws {
        let suiteName = "TapDeckTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = PreferencesStore(defaults: defaults)
        firstStore.update(.threeFingerTap, enabled: false, action: .rightClick)
        firstStore.update(.fourFingerTap, enabled: true, action: .showDesktop)
        let application = ApplicationTarget(
            bundleIdentifier: "com.apple.TextEdit",
            path: "/System/Applications/TextEdit.app",
            displayName: "TextEdit"
        )
        firstStore.update(.twoFingerTap, enabled: true, action: .openApplication)
        firstStore.setApplication(application, for: .twoFingerTap)

        let reloadedStore = PreferencesStore(defaults: defaults)
        #expect(reloadedStore.binding(for: .threeFingerTap) == .init(isEnabled: false, action: .rightClick))
        #expect(reloadedStore.binding(for: .fourFingerTap) == .init(isEnabled: true, action: .showDesktop))
        #expect(reloadedStore.binding(for: .twoFingerTap) == .init(
            isEnabled: true,
            action: .openApplication,
            application: application
        ))
        #expect(reloadedStore.binding(for: .threeFingerClick) == .init(isEnabled: true, action: .middleClick))
    }

    @Test
    @MainActor
    func existingPreferencesLoseRemovedLongTouchBinding() throws {
        let suiteName = "TapDeckTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previousPreferences = AppPreferences()
        previousPreferences.bindings[.threeFingerLongTouch] = .init(isEnabled: true, action: .middleClick)
        defaults.set(try JSONEncoder().encode(previousPreferences), forKey: "trackpadClicker.preferences.v1")

        let migratedStore = PreferencesStore(defaults: defaults)
        #expect(migratedStore.binding(for: .threeFingerLongTouch) == .init(isEnabled: false, action: .none))
    }

    @Test
    @MainActor
    func originalTapDurationMigratesToForgivingDefault() throws {
        let suiteName = "TapDeckTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previousPreferences = AppPreferences()
        previousPreferences.tapDuration = 0.28
        defaults.set(try JSONEncoder().encode(previousPreferences), forKey: "trackpadClicker.preferences.v1")

        let migratedStore = PreferencesStore(defaults: defaults)
        #expect(migratedStore.value.tapDuration == 0.36)
    }

    @Test
    @MainActor
    func classifiesLoginItemOpenApplicationEvent() {
        let target = NSAppleEventDescriptor.currentProcess()
        let loginEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        loginEvent.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: keyAELaunchedAsLogInItem
        )

        let explicitOpenEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        #expect(AppDelegate.isLoginItemLaunchEvent(loginEvent))
        #expect(!AppDelegate.isLoginItemLaunchEvent(explicitOpenEvent))
        #expect(!AppDelegate.isLoginItemLaunchEvent(nil))
    }
}
