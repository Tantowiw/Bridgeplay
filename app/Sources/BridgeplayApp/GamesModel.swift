// Drives the Games page: the games Bridgeplay starts without Steam, see GameStore.

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class GamesModel {

    private(set) var games: [StandaloneGame] = []
    private(set) var tools: [InstalledTool] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    var outcome: String?
    private(set) var report: FailureReport?

    var selection: StandaloneGame.ID?
    var removing: StandaloneGame?
    var quitting: StandaloneGame?

    static let showFPSKey = "GamesShowFPS"

    // Play opens the FPS window over the game. Kept between launches of the app.
    var showFPS: Bool {
        didSet { defaults.set(showFPS, forKey: Self.showFPSKey) }
    }

    var selectedGame: StandaloneGame? { games.first { $0.id == selection } }

    private let root: URL
    private let installedTools: @Sendable () -> [InstalledTool]
    private let start: @Sendable (StandaloneGame, URL?, Bool) throws -> Void
    private let showFPSWindow: @MainActor (StandaloneGame) -> Void
    private let defaults: UserDefaults
    private let remove: @Sendable (StandaloneGame) throws -> Void
    private let stop: @Sendable (StandaloneGame) throws -> Bool

    init(
        root: URL = SupportPaths.games,
        installedTools: @escaping @Sendable () -> [InstalledTool] = { CompatToolList.installed() },
        start: @escaping @Sendable (StandaloneGame, URL?, Bool) throws -> Void = {
            try GameStore.play($0, program: $1, showFPS: $2)
        },
        remove: @escaping @Sendable (StandaloneGame) throws -> Void = { try GameStore.remove($0) },
        stop: @escaping @Sendable (StandaloneGame) throws -> Bool = { try PrefixTools.forceQuit(GameStore.prefix(of: $0)) },
        showFPSWindow: @escaping @MainActor (StandaloneGame) -> Void = { FPSWindow.shared.show(for: $0) },
        defaults: UserDefaults = .standard
    ) {
        self.root = root
        self.installedTools = installedTools
        self.start = start
        self.remove = remove
        self.stop = stop
        self.showFPSWindow = showFPSWindow
        self.defaults = defaults
        showFPS = defaults.bool(forKey: Self.showFPSKey)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let root = root
        let listTools = installedTools
        (games, tools) = await Task.detached { (GameStore.all(in: root), listTools()) }.value
        if games.allSatisfy({ $0.id != selection }) { selection = nil }
        hasLoaded = true
    }

    func forgetOutcome() {
        report = nil
        outcome = nil
    }

    func hasPrefix(_ game: StandaloneGame) -> Bool {
        FileManager.default.fileExists(atPath: GameStore.prefix(of: game, in: root).pfx.path(percentEncoded: false))
    }

    func toolName(_ game: StandaloneGame) -> String? {
        tools.first { $0.name == game.tool }?.display
    }

    func program(_ game: StandaloneGame) -> String? {
        GameStore.executableURL(of: game, in: root)?.lastPathComponent
    }

    @discardableResult
    func add(name: String, tool: String?) async -> StandaloneGame? {
        var added: StandaloneGame?
        act {
            let game = try GameStore.add(name: name, tool: tool, in: root)
            added = game
            return String(localized: "Added \(game.name). Run its installer to install it in its own prefix.")
        }
        await load()
        selection = added?.id
        return added
    }

    func setTool(_ tool: String?, for game: StandaloneGame) async {
        var changed = game
        changed.tool = tool
        act {
            try GameStore.save(changed, in: root)
            return nil
        }
        await load()
    }

    // The installer the user downloaded, from wherever it is.
    func chooseInstaller(for game: StandaloneGame) {
        let panel = Self.programPanel()
        panel.prompt = String(localized: "Install")
        panel.message = String(localized: "Choose the installer for \(game.name). It runs in the game's own prefix.")
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        act {
            try start(game, picked, false)
            return String(localized: "Started \(picked.lastPathComponent) in \(game.name). When it has finished, choose the program that starts the game.")
        }
    }

    // The program Play starts: where the game's installer put it in its prefix, or a game
    // folder that was unpacked somewhere else.
    func chooseProgram(for game: StandaloneGame) async {
        let panel = Self.programPanel()
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the program that starts \(game.name).")
        panel.directoryURL = programFolder(for: game)
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        await setProgram(picked, for: game)
    }

    // The current program's folder, then the prefix's Program Files, then Downloads.
    func programFolder(for game: StandaloneGame) -> URL? {
        let files = FileManager.default
        if let current = GameStore.executableURL(of: game, in: root)?.deletingLastPathComponent(),
           files.fileExists(atPath: current.path(percentEncoded: false)) {
            return current
        }
        let programs = GameStore.prefix(of: game, in: root).pfx.appending(path: "drive_c/Program Files (x86)")
        if files.fileExists(atPath: programs.path(percentEncoded: false)) { return programs }
        return files.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func setProgram(_ picked: URL, for game: StandaloneGame) async {
        var changed = game
        changed.executable = GameStore.storedPath(of: picked, in: game, root: root)
        act {
            try GameStore.save(changed, in: root)
            return String(localized: "Play now starts \(picked.lastPathComponent).")
        }
        await load()
    }

    func play(_ game: StandaloneGame) {
        let fps = showFPS
        var started = false
        act {
            try start(game, nil, fps)
            started = true
            return String(localized: "Started \(game.name).")
        }
        if started, fps { showFPSWindow(game) }
    }

    // Takes the game rather than reading `quitting`, which the dialog clears as it closes.
    func forceQuit(_ game: StandaloneGame) async {
        quitting = nil
        forgetOutcome()
        isLoading = true
        let stop = stop
        do {
            let stopped = try await Task.detached { try stop(game) }.value
            outcome = stopped
                ? String(localized: "Force quit \(game.name).")
                : String(localized: "\(game.name) is not running.")
        } catch {
            report = FailureReport([error])
        }
        isLoading = false
    }

    // Takes the game rather than reading `removing`: the dialog clears that as it closes,
    // before its button's task runs.
    func removeGame(_ game: StandaloneGame) async {
        removing = nil
        forgetOutcome()
        isLoading = true
        let remove = remove
        do {
            try await Task.detached { try remove(game) }.value
            outcome = String(localized: "Removed \(game.name).")
        } catch {
            report = FailureReport([error])
        }
        isLoading = false
        await load()
    }

    private static func programPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let types = PrefixTools.runnableTypes
        if !types.isEmpty { panel.allowedContentTypes = types }
        return panel
    }

    private func act(_ body: () throws -> String?) {
        forgetOutcome()
        do {
            outcome = try body()
        } catch {
            report = FailureReport([error])
        }
    }
}
