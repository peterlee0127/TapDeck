import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var coordinator: GestureCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "TapDeck")
                        .font(.headline)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(nsColor: coordinator.status.color))
                            .frame(width: 6, height: 6)
                        Text(coordinator.status.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Toggle(L10n.string("menu.enable_gestures", "Enable Trackpad Gestures"), isOn: Binding(get: {
                preferences.value.isEnabled
            }, set: {
                preferences.value.isEnabled = $0
                coordinator.refresh()
            }))
            .toggleStyle(.switch)

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(L10n.string("menu.open_settings", "Open Settings…"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut(",")

            Divider()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(L10n.string("menu.quit", "Quit TapDeck"), systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 270)
    }
}
