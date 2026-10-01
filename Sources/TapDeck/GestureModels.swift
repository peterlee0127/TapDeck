import AppKit
import Foundation

enum GestureKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case twoFingerClick
    case twoFingerTap
    case threeFingerClick
    case threeFingerTap
    // Kept only so preferences written by older builds can still be decoded.
    case threeFingerLongTouch
    case fourFingerClick
    case fourFingerTap
    case oneFingerForceTouch

    static var allCases: [GestureKind] {
        [
            .oneFingerForceTouch,
            .twoFingerClick, .twoFingerTap,
            .threeFingerClick, .threeFingerTap,
            .fourFingerClick, .fourFingerTap,
        ]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoFingerClick: L10n.string("gesture.two_finger_click.title", "Two-finger Click")
        case .twoFingerTap: L10n.string("gesture.two_finger_tap.title", "Two-finger Tap")
        case .threeFingerClick: L10n.string("gesture.three_finger_click.title", "Three-finger Click")
        case .threeFingerTap: L10n.string("gesture.three_finger_tap.title", "Three-finger Tap")
        case .threeFingerLongTouch: L10n.string("gesture.three_finger_long_touch.title", "Three-finger Hold (Removed)")
        case .fourFingerClick: L10n.string("gesture.four_finger_click.title", "Four-finger Click")
        case .fourFingerTap: L10n.string("gesture.four_finger_tap.title", "Four-finger Tap")
        case .oneFingerForceTouch: L10n.string("gesture.force_touch.title", "One-finger Force Click")
        }
    }

    var subtitle: String {
        switch self {
        case .twoFingerClick: L10n.string("gesture.two_finger_click.subtitle", "Physically press the trackpad with two fingers")
        case .twoFingerTap: L10n.string("gesture.two_finger_tap.subtitle", "Quickly touch and release with two fingers")
        case .threeFingerClick: L10n.string("gesture.three_finger_click.subtitle", "Physically press the trackpad with three fingers")
        case .threeFingerTap: L10n.string("gesture.three_finger_tap.subtitle", "Quickly touch and release with three fingers")
        case .threeFingerLongTouch: L10n.string("gesture.three_finger_long_touch.subtitle", "Legacy compatibility item; no longer recognized")
        case .fourFingerClick: L10n.string("gesture.four_finger_click.subtitle", "Physically press the trackpad with four fingers")
        case .fourFingerTap: L10n.string("gesture.four_finger_tap.subtitle", "Quickly touch and release with four fingers")
        case .oneFingerForceTouch: L10n.string("gesture.force_touch.subtitle", "Press through to the second Force Touch pressure stage")
        }
    }

    var symbol: String {
        switch self {
        case .twoFingerClick: "hand.point.up.left.fill"
        case .twoFingerTap: "hand.tap.fill"
        case .threeFingerClick: "hand.point.up.left.fill"
        case .threeFingerTap: "hand.tap.fill"
        case .threeFingerLongTouch: "hand.raised.slash.fill"
        case .fourFingerClick: "hand.point.up.braille.fill"
        case .fourFingerTap: "hand.raised.fingers.spread.fill"
        case .oneFingerForceTouch: "hand.press.fill"
        }
    }
}

enum GestureAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case middleClick
    case leftClick
    case rightClick
    case quickLook
    case missionControl
    case appExpose
    case showDesktop
    case openApplication
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .middleClick: L10n.string("action.middle_click", "Middle Click")
        case .leftClick: L10n.string("action.left_click", "Left Click")
        case .rightClick: L10n.string("action.right_click", "Right Click")
        case .quickLook: L10n.string("action.quick_look", "Quick Look")
        case .missionControl: "Mission Control"
        case .appExpose: L10n.string("action.app_expose", "App Exposé")
        case .showDesktop: L10n.string("action.show_desktop", "Show Desktop")
        case .openApplication: L10n.string("action.open_application", "Open or Switch to App")
        case .none: L10n.string("action.none", "No Action")
        }
    }

    var symbol: String {
        switch self {
        case .middleClick: "computermouse.fill"
        case .leftClick: "cursorarrow.click"
        case .rightClick: "contextualmenu.and.cursorarrow"
        case .quickLook: "eye.fill"
        case .missionControl: "rectangle.3.group.fill"
        case .appExpose: "rectangle.stack.fill"
        case .showDesktop: "macwindow.on.rectangle"
        case .openApplication: "app.badge"
        case .none: "minus.circle"
        }
    }
}

struct GestureBinding: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var action: GestureAction
    var application: ApplicationTarget? = nil
}

struct ApplicationTarget: Codable, Equatable, Sendable {
    var bundleIdentifier: String?
    var path: String
    var displayName: String
}

struct AppPreferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var launchAtLogin = false
    var tapDuration = 0.36
    var movementTolerance = 0.045
    var hapticFeedback = true
    var bindings: [GestureKind: GestureBinding] = [
        .twoFingerClick: .init(isEnabled: false, action: .none),
        .twoFingerTap: .init(isEnabled: false, action: .none),
        .threeFingerClick: .init(isEnabled: true, action: .middleClick),
        .threeFingerTap: .init(isEnabled: true, action: .middleClick),
        .fourFingerClick: .init(isEnabled: false, action: .none),
        .fourFingerTap: .init(isEnabled: true, action: .missionControl),
        .oneFingerForceTouch: .init(isEnabled: true, action: .quickLook)
    ]

    func binding(for gesture: GestureKind) -> GestureBinding {
        bindings[gesture] ?? .init(isEnabled: false, action: .none)
    }
}

struct TouchPoint: Sendable, Equatable {
    var id: Int32
    var x: Float
    var y: Float
    var pressure: Float
}

struct TouchFrame: Sendable, Equatable {
    var timestamp: Double
    var touches: [TouchPoint]
}
