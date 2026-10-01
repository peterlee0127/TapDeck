import Foundation

enum L10n {
    static func string(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .main,
            value: fallback,
            comment: ""
        )
    }

    static func format(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, fallback),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func detectedFingers(_ count: Int) -> String {
        count == 1
            ? format("format.detected_fingers.one", "%d finger detected", count)
            : format("format.detected_fingers.other", "%d fingers detected", count)
    }

    static func currentFingers(_ count: Int) -> String {
        count == 1
            ? format("format.current_fingers.one", "Currently detecting %d finger", count)
            : format("format.current_fingers.other", "Currently detecting %d fingers", count)
    }

    static func eventCount(_ count: Int) -> String {
        count == 1
            ? format("format.event_count.one", "%d event", count)
            : format("format.event_count.other", "%d events", count)
    }
}
