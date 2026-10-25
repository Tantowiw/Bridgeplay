// Game Settings…: one game's own Bridgeplay settings, kept in its gamefixes/<appid>.conf (see
// GameSettings). A game that is not from Steam has no Steam panel to set them in.

import SwiftUI
import BridgeplayUI

struct GameSettingsView: View {
    let prefix: WinePrefix
    @Environment(\.dismiss) private var dismiss
    @State private var values: [GameSettings.Setting: String] = [:]
    @State private var inherited: [GameSettings.Setting: String] = [:]
    @State private var steam: [GameSettings.Setting: String] = [:]
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Settings")
                .font(BP.sans(17, .semibold))
            Text(prefix.title)
                .foregroundStyle(BP.fg2)
            Form {
                Section {
                    picker(.graphics, Text("Graphics"))
                    picker(.metalHUD, Text("Metal HUD"))
                    picker(.msync, Text(verbatim: "MSync"))
                    picker(.highResolution, Text("High Resolution"))
                }
                Section("Frame Generation (Experimental. Adds input lag)") {
                    picker(.frameGeneration, Text("Mode"))
                    if !["0", "off"].contains(effective(.frameGeneration)) {
                        picker(.frameGenerationQuality, Text("Quality"))
                        picker(.frameGenerationUI, Text("Protect UI (keeps static HUD and menus sharp)"))
                        picker(.frameGenerationFallback, Text("Fast-motion fallback (skips frames that would smear)"))
                        picker(.frameGenerationEngine, Text("Engine"))
                    }
                }
                if let saveError {
                    StatusRow(title: String(localized: "Something went wrong"), value: saveError, tone: .bad,
                              menu: ErrorReport.actions(saveError, in: "Game settings"))
                }
            }
            .formStyle(.grouped)
            Text("Saved in gamefixes/\(prefix.appID).conf. Launch options set for this game in Steam win over these.")
                .font(BP.sans(11))
                .foregroundStyle(BP.fg3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear(perform: load)
    }

    private func picker(_ setting: GameSettings.Setting, _ title: Text) -> some View {
        Picker(selection: Binding(get: { values[setting] ?? "" }, set: { save(setting, $0.isEmpty ? nil : $0) })) {
            Text(defaultLabel(setting)).tag("")
            ForEach(setting.values, id: \.self) { value in
                Text(Self.label(setting, value)).tag(value)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                title
                if let value = steam[setting] {
                    Text("Set to \(Self.label(setting, value)) by this game's Steam launch options, which win over this choice.")
                        .font(BP.sans(11))
                        .foregroundStyle(BP.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func effective(_ setting: GameSettings.Setting) -> String? {
        steam[setting] ?? values[setting] ?? inherited[setting] ?? setting.builtInDefault
    }

    // The choice that writes no line, named after what the game then gets.
    private func defaultLabel(_ setting: GameSettings.Setting) -> String {
        if let value = inherited[setting] ?? setting.builtInDefault {
            return String(localized: "Default (\(Self.label(setting, value)))")
        }
        return setting == .graphics ? String(localized: "Automatic") : String(localized: "Default")
    }

    private static func label(_ setting: GameSettings.Setting, _ value: String) -> String {
        switch (setting, value) {
        case (.graphics, "d3dmetal"): "D3DMetal"
        case (.graphics, "dxmt"): "DXMT"
        case (.graphics, "dxvk"): "DXVK"
        case (.graphics, "wined3d"): "WineD3D"
        case (.frameGeneration, "2"): "2x"
        case (.frameGeneration, "3"): "3x"
        case (.frameGeneration, "adaptive"): String(localized: "Adaptive (fills to display refresh)")
        case (.frameGenerationQuality, "performance"): String(localized: "Performance")
        case (.frameGenerationQuality, "balanced"): String(localized: "Balanced")
        case (.frameGenerationQuality, "quality"): String(localized: "Quality")
        case (.frameGenerationEngine, "own"): String(localized: "Built-in optical flow")
        case (.frameGenerationEngine, "metalfx"): "MetalFX"
        case (_, "1"): String(localized: "On")
        case (_, "0"), (_, "off"): String(localized: "Off")
        default: value
        }
    }

    // A value the pickers do not offer shows as Default, and stays in the file until changed.
    private func load() {
        let own = GameSettings.text(at: GameSettings.file(for: prefix.appID))
        let lower = [GameDefaults.file, GameSettings.shippedFile(for: prefix.appID)].map(GameSettings.text(at:))
        steam = GameSettings.launchOptionValues(PrefixStore.launchOptions(appID: prefix.appID) ?? "")
        for setting in GameSettings.Setting.allCases {
            values[setting] = GameSettings.value(setting, in: own).flatMap { setting.values.contains($0) ? $0 : nil }
            inherited[setting] = GameSettings.inherited(setting, from: lower)
        }
    }

    private func save(_ setting: GameSettings.Setting, _ value: String?) {
        values[setting] = value
        do {
            try GameSettings.set(setting, to: value, at: GameSettings.file(for: prefix.appID))
            saveError = nil
        } catch {
            saveError = String(localized: "Bridgeplay could not save this setting. \(error.localizedDescription)")
        }
    }
}
