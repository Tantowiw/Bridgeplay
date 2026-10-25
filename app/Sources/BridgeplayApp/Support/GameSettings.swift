import Foundation

// One game's own settings, the ones the Bridgeplay panel in Steam Properties also offers, in
// the user's gamefixes/<appid>.conf. The run script reads that file after default.conf and the
// shipped per-game conf, so it wins over both, and Steam launch options still win over it. A
// game that is not from Steam has no Steam panel, so this is where its settings live. As in
// GameDefaults, only the lines for these keys are rewritten, and a setting left at its
// default has no line at all.
enum GameSettings {

    enum Setting: String, CaseIterable, Sendable {
        case graphics = "BACKEND"
        case metalHUD = "MTL_HUD_ENABLED"
        case msync = "MSYNC"
        case highResolution = "RETINA"
        case frameGeneration = "FRAMEGEN"
        case frameGenerationQuality = "FRAMEGEN_QUALITY"
        case frameGenerationUI = "FRAMEGEN_UI"
        case frameGenerationFallback = "FRAMEGEN_FALLBACK"
        case frameGenerationEngine = "FRAMEGEN_ENGINE"

        // The first spelling is the one written; the others are read and replaced.
        var keys: [String] {
            switch self {
            case .graphics, .metalHUD, .msync: [rawValue]
            default: [rawValue, "BRIDGEPLAY_" + rawValue]
            }
        }

        // The values offered, all of which the run script's gamefix_reason accepts.
        var values: [String] {
            switch self {
            case .graphics: ["d3dmetal", "dxmt", "dxvk", "wined3d"]
            case .metalHUD, .msync, .highResolution, .frameGenerationUI, .frameGenerationFallback: ["1", "0"]
            case .frameGeneration: ["0", "2", "3", "adaptive"]
            case .frameGenerationQuality: ["performance", "balanced", "quality"]
            case .frameGenerationEngine: ["own", "metalfx"]
            }
        }

        // What the run script and the overlay shim use when no conf sets it. nil where the
        // engine or the game decides (graphics, MSync).
        var builtInDefault: String? {
            switch self {
            case .graphics, .msync: nil
            case .metalHUD, .highResolution, .frameGeneration: "0"
            case .frameGenerationQuality: "balanced"
            case .frameGenerationUI, .frameGenerationFallback: "1"
            case .frameGenerationEngine: "own"
            }
        }
    }

    static func file(for appID: String) -> URL { SupportPaths.gamefixes.appending(path: "\(appID).conf") }

    static func shippedFile(for appID: String) -> URL {
        SupportPaths.gamefixesDefault.appending(path: "\(appID).conf")
    }

    static let header = "# This game's settings from Bridgeplay's Game Settings. Steam launch options win over these."

    // Last assignment wins, as in the run script. nil when the text leaves the setting out.
    static func value(_ setting: Setting, in text: String) -> String? {
        var found: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let (key, value) = GameDefaults.assignment(line), setting.keys.contains(key) else { continue }
            found = value
        }
        // FRAMEGEN=1 is the 2x of the first release.
        if setting == .frameGeneration, found == "1" { return "2" }
        return found
    }

    // What the game gets when its own file leaves the setting out: the last of the lower
    // layers that sets it, default.conf first and the shipped per-game conf after it.
    static func inherited(_ setting: Setting, from layers: [String]) -> String? {
        layers.compactMap { value(setting, in: $0) }.last
    }

    static func setting(_ setting: Setting, to value: String?, in text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { line in GameDefaults.assignment(Substring(line)).map { setting.keys.contains($0.0) } ?? false }
        if let value {
            if lines.isEmpty { lines.append(header) }
            lines.append("\(setting.keys[0])=\(value)")
        }
        if lines == [header] { lines = [] }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // What Steam launch options set, read as the run script reads them: the NAME=value words
    // before %command%, the last of a name winning, NOTPROTON_<X> over BRIDGEPLAY_<X>, and
    // BRIDGEPLAY_BACKEND over the panel's CX_GRAPHICS_BACKEND. Values the run script would
    // ignore are left out; frame generation is spelled as the pickers spell it.
    static func launchOptionValues(_ options: String) -> [Setting: String] {
        let words = shellWords(options)
        guard let command = words.firstIndex(of: "%command%") else { return [:] }
        var env: [String: String] = [:]
        for word in words[..<command] {
            guard let equals = word.firstIndex(of: "="),
                  word[..<equals].wholeMatch(of: #/[A-Za-z_][A-Za-z0-9_]*/#) != nil
            else { continue }
            let value = String(word[word.index(after: equals)...])
            env[String(word[..<equals])] = value.isEmpty ? nil : value
        }
        func bridgeplay(_ name: String) -> String? { env["NOTPROTON_" + name] ?? env["BRIDGEPLAY_" + name] }

        var found: [Setting: String] = [:]
        if let backend = bridgeplay("BACKEND"), Setting.graphics.values.contains(backend) {
            found[.graphics] = backend
        } else if let raw = env["CX_GRAPHICS_BACKEND"]?.lowercased() {
            let backend = ["opengl", "wine"].contains(raw) ? "wined3d" : raw
            if Setting.graphics.values.contains(backend) { found[.graphics] = backend }
        }
        found[.metalHUD] = env["MTL_HUD_ENABLED"]
        found[.msync] = env["WINEMSYNC"]
        found[.highResolution] = bridgeplay("RETINA").map { $0 == "1" ? "1" : "0" }
        found[.frameGeneration] = bridgeplay("FRAMEGEN").map {
            let mode = $0.lowercased()
            return mode == "1" ? "2" : ["off", "false", "no"].contains(mode) ? "0" : mode
        }
        for setting in [Setting.frameGenerationQuality, .frameGenerationUI, .frameGenerationFallback, .frameGenerationEngine] {
            found[setting] = bridgeplay(setting.rawValue)?.lowercased()
        }
        return found
    }

    // Shell words as Steam's launch hook splits them: blanks separate, '…' is literal, and
    // "…" or a bare backslash quote what follows.
    static func shellWords(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for c in line {
            if escaped {
                word.append(c)
                escaped = false
            } else if quote == "'" {
                if c == "'" { quote = nil } else { word.append(c) }
            } else if quote == "\"" {
                if c == "\"" { quote = nil } else if c == "\\" { escaped = true } else { word.append(c) }
            } else if c == "'" || c == "\"" {
                quote = c
                inWord = true
            } else if c == "\\" {
                escaped = true
                inWord = true
            } else if c == " " || c == "\t" || c == "\n" {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(c)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }

    static func text(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // A file left with nothing in it is removed rather than kept empty.
    static func set(_ setting: Setting, to value: String?, at url: URL) throws {
        let current = text(at: url)
        let updated = Self.setting(setting, to: value, in: current)
        guard updated != current else { return }
        if updated.isEmpty {
            try FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(updated.utf8).write(to: url, options: .atomic)
        }
        AppLog.note("game settings: \(url.lastPathComponent) \(setting.keys[0])=\(value ?? "default")")
    }
}
