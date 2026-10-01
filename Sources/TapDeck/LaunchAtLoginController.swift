import ServiceManagement

enum LaunchAtLoginController {
    static var isAvailable: Bool {
#if DEBUG
        false
#else
        true
#endif
    }

    static func setEnabled(_ enabled: Bool) {
#if DEBUG
        // Never register an app launched from Xcode's DerivedData as a login item.
        // Debug and release builds also use different bundle identifiers, but this
        // guard prevents a development path from being persisted at all.
        return
#else
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The UI remains usable when running as a raw SwiftPM executable; registration
            // becomes available once built as the included .app bundle.
        }
#endif
    }
}
