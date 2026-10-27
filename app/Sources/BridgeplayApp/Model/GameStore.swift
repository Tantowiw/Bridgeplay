// Games Bridgeplay starts itself, with no Steam involved. Each game has a folder under
// SupportPaths.games named by its ID and laid out like a Steam compatdata entry, so the run
// script takes it as one: pfx/ is the prefix the run script clones on first launch, its logs
// land beside it, and game.json holds what Bridgeplay knows about the game.

import Foundation

struct StandaloneGame: Sendable, Hashable, Identifiable {
    let id: String
    var name: String
    // The program Play starts. Inside the game's folder it is kept relative to it
    // (pfx/drive_c/…), so the folder can move with the game in it. A game unpacked somewhere
    // else, such as Downloads, is kept by its absolute path.
    var executable: String?
    var arguments: [String] = []
    // The compatibility tool Play runs the game with, by name.
    var tool: String?
}

enum GameStore {

    // Above every 32-bit Steam app and shortcut ID, so a game's gamefixes/<id>.conf and
    // launchers/<id> never meet a Steam game's.
    static let firstID: UInt64 = 5_000_000_001
    static let recordName = "game.json"

    static var library: SteamLibrary { library(at: SupportPaths.games) }

    static func library(at root: URL) -> SteamLibrary {
        SteamLibrary(root: root, isBridgeplay: true)
    }

    static func isGameID(_ name: String) -> Bool {
        name.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(name).map { $0 >= firstID } ?? false)
    }

    static func folder(of id: String, in root: URL = SupportPaths.games) -> URL {
        root.appending(path: id)
    }

    static func prefix(of game: StandaloneGame, in root: URL = SupportPaths.games) -> WinePrefix {
        WinePrefix(appID: game.id, name: game.name, library: library(at: root), lastUsed: nil)
    }

    private struct Record: Codable {
        var name: String
        var executable: String?
        var arguments: [String]?
        var tool: String?
    }

    static func game(id: String, in root: URL = SupportPaths.games) -> StandaloneGame? {
        guard isGameID(id),
              let data = try? Data(contentsOf: folder(of: id, in: root).appending(path: recordName)),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        return StandaloneGame(
            id: id, name: record.name, executable: record.executable, arguments: record.arguments ?? [],
            tool: record.tool)
    }

    static func all(in root: URL = SupportPaths.games) -> [StandaloneGame] {
        ids(in: root).compactMap { game(id: $0, in: root) }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private static func ids(in root: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? [])
            .filter(isGameID)
    }

    // The next ID is one past the highest folder, including one a failed add left without a
    // record. Making the folder is what claims it. Removing the newest game frees its ID
    // again, which is why remove also takes what Bridgeplay keeps elsewhere under that ID.
    static func add(name: String, tool: String? = nil, in root: URL = SupportPaths.games) throws -> StandaloneGame {
        let step = String(localized: "Add game")
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StepFailure(step: step, detail: String(localized: "Give the game a name.")) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var next = max(firstID, (ids(in: root).compactMap { UInt64($0) }.max() ?? 0) + 1)
        for _ in 0..<100 {
            let id = String(next)
            do {
                try FileManager.default.createDirectory(at: folder(of: id, in: root), withIntermediateDirectories: false)
            } catch CocoaError.fileWriteFileExists {
                next += 1
                continue
            }
            let game = StandaloneGame(id: id, name: name, tool: tool)
            try save(game, in: root)
            AppLog.note("games: added \(id)")
            return game
        }
        throw StepFailure(step: step, detail: String(localized: "No free game ID was found in \(root.path(percentEncoded: false))."))
    }

    static func save(_ game: StandaloneGame, in root: URL = SupportPaths.games) throws {
        let record = Record(
            name: game.name, executable: game.executable, arguments: game.arguments.isEmpty ? nil : game.arguments,
            tool: game.tool)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try atomicReplace(
            folder(of: game.id, in: root).appending(path: recordName), with: encoder.encode(record),
            step: String(localized: "Save \(game.name)"))
    }

    // The game's folder, with the game installed in its prefix and its saves, then its launcher
    // bundle and Game Settings, which a later game given the same ID must not inherit.
    static func remove(
        _ game: StandaloneGame, in root: URL = SupportPaths.games,
        launchers: URL = SupportPaths.launchers, gamefixes: URL = SupportPaths.gamefixes
    ) throws {
        let prefix = prefix(of: game, in: root)
        guard let claim = PrefixStore.claim(prefix) else {
            throw StepFailure(
                step: String(localized: "Remove \(game.name)"),
                detail: String(localized: "\(prefix.title) is running. Quit the game first.")
            )
        }
        defer { claim.release() }
        let folder = folder(of: game.id, in: root)
        try WriteRefused.catching(folder) { try FileManager.default.removeItem(at: folder) }
        for leftover in [launchers.appending(path: game.id), gamefixes.appending(path: "\(game.id).conf")] {
            try? FileManager.default.removeItem(at: leftover)
        }
        AppLog.note("games: removed \(game.id)")
    }

    // nil when a relative path climbs out of the game's folder.
    static func executableURL(of game: StandaloneGame, in root: URL = SupportPaths.games) -> URL? {
        guard let path = game.executable, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(filePath: path, directoryHint: .notDirectory) }
        guard !path.split(separator: "/").contains("..") else { return nil }
        return folder(of: game.id, in: root).appending(path: path, directoryHint: .notDirectory)
    }

    // How a program the user picked is stored: relative inside the game's folder, absolute
    // anywhere else.
    static func storedPath(of executable: URL, in game: StandaloneGame, root: URL = SupportPaths.games) -> String {
        relativePath(of: executable, in: game, root: root)
            ?? executable.standardizedFileURL.path(percentEncoded: false)
    }

    // The part of the path to store for a program the user picked inside the game's folder.
    static func relativePath(of executable: URL, in game: StandaloneGame, root: URL = SupportPaths.games) -> String? {
        var base = folder(of: game.id, in: root).resolvingSymlinksInPath().path(percentEncoded: false)
        if !base.hasSuffix("/") { base += "/" }
        let path = executable.resolvingSymlinksInPath().path(percentEncoded: false)
        guard path.hasPrefix(base), path.count > base.count else { return nil }
        return String(path.dropFirst(base.count))
    }

    struct Launch: Equatable {
        let run: URL
        let arguments: [String]
        let environment: [String: String]
        let directory: URL
    }

    // The run script launch Play makes: the tool's run script, as Steam would call it, with the
    // game's folder as its compatdata and BRIDGEPLAY_STANDALONE set. Steam's own variables are
    // dropped, so nothing the app inherited points the run script at Steam or at another game.
    // `program` is for one that is not the game's own, such as its installer; the game's
    // arguments are only passed to its own.
    static func launch(
        _ game: StandaloneGame, program: URL? = nil, tool: InstalledTool, root: URL = SupportPaths.games,
        compatTools: URL = SupportPaths.Steam.compatTools,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Launch {
        let step = String(localized: "Play \(game.name)")
        guard let executable = program ?? executableURL(of: game, in: root) else {
            throw StepFailure(step: step, detail: String(localized: "Choose the program that starts \(game.name) first."))
        }
        guard FileManager.default.fileExists(atPath: executable.path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: String(localized: "No file at \(executable.path(percentEncoded: false))."))
        }
        let run = compatTools.appending(path: tool.name).appending(path: "run")
        guard FileManager.default.isExecutableFile(atPath: run.path(percentEncoded: false)) else {
            throw StepFailure(
                step: step,
                detail: String(localized: "\(tool.display) has no run script at \(run.path(percentEncoded: false)). Set up the compatibility tool again."))
        }
        var env = environment.filter { key, _ in
            !key.hasPrefix("STEAM_") && !key.hasPrefix("Steam") && !key.hasPrefix("NOTPROTON_")
                && !key.hasPrefix("BRIDGEPLAY_")
        }
        env["BRIDGEPLAY_STANDALONE"] = "1"
        env["STEAM_COMPAT_DATA_PATH"] = folder(of: game.id, in: root).path(percentEncoded: false)
        env["STEAM_COMPAT_INSTALL_PATH"] = executable.deletingLastPathComponent().path(percentEncoded: false)
        return Launch(
            run: run, arguments: ["waitforexitandrun", executable.path(percentEncoded: false)] + (program == nil ? game.arguments : []),
            environment: env, directory: executable.deletingLastPathComponent())
    }

    // The game's own tool while it is installed, otherwise the one the prefix was last run by.
    static func tool(for game: StandaloneGame, among tools: [InstalledTool] = CompatToolList.installed()) throws -> InstalledTool {
        if let named = tools.first(where: { $0.name == game.tool }) { return named }
        return try PrefixTools.resolvedTool(step: String(localized: "Play \(game.name)"), for: prefix(of: game), among: tools)
    }

    static func play(_ game: StandaloneGame, program: URL? = nil) throws {
        let tool = try tool(for: game)
        let launch = try launch(game, program: program, tool: tool)
        AppLog.note("games: play \(game.id) with \(tool.name)\(program == nil ? "" : ", running another program")")
        try Shell.detach(
            launch.run.path(percentEncoded: false), launch.arguments,
            environment: launch.environment, currentDirectory: launch.directory)
    }
}
