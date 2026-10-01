import ApplicationServices
import AppKit
import Foundation

enum AccessibilityController {
    enum ResetError: LocalizedError {
        case missingBundleIdentifier
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBundleIdentifier:
                L10n.string("error.missing_bundle_identifier", "The app's bundle identifier could not be found.")
            case let .commandFailed(message):
                message.isEmpty
                    ? L10n.string("error.accessibility_reset_denied", "macOS refused to reset Accessibility permission.")
                    : message
            }
        }
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func request() {
        // The exported constant is imported as mutable global state in Swift 6.
        // Its documented string value avoids crossing that concurrency boundary.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func reset() throws {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            throw ResetError.missingBundleIdentifier
        }

        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ResetError.commandFailed(message)
        }
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openTrackpadSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
