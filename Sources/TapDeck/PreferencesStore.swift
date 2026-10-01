import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var value: AppPreferences {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "trackpadClicker.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            var migrated = decoded
            migrated.bindings.removeValue(forKey: .threeFingerLongTouch)
            // Migrate the original, overly strict default while preserving values
            // that the user has deliberately adjusted.
            if abs(migrated.tapDuration - 0.28) < 0.000_001 {
                migrated.tapDuration = 0.36
            }
            value = migrated
        } else {
            value = AppPreferences()
        }
    }

    func binding(for gesture: GestureKind) -> GestureBinding {
        value.binding(for: gesture)
    }

    func update(_ gesture: GestureKind, enabled: Bool? = nil, action: GestureAction? = nil) {
        var binding = value.binding(for: gesture)
        if let enabled { binding.isEnabled = enabled }
        if let action { binding.action = action }
        value.bindings[gesture] = binding
    }

    func setApplication(_ application: ApplicationTarget?, for gesture: GestureKind) {
        var binding = value.binding(for: gesture)
        binding.application = application
        value.bindings[gesture] = binding
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
