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

    var selectedGame: StandaloneGame? { games.first { $0.id == selection } }

    private let root: URL
    private let installedTools: @Sendable () -> [InstalledTool]
    private let start: @Sendable (StandaloneGame, URL?) throws -> Void
    private let remove: @Sendable (StandaloneGame) throws -> Void

    init(
        root: URL = SupportPaths.games,
        installedTools: @escaping @Sendable () -> [InstalledTool] = { CompatToolList.installed() },
        start: @escaping @Sendable (StandaloneGame, URL?) throws -> Void = { try GameStore.play($0, program: $1) },
        remove: @escaping @Sendable (StandaloneGame) throws -> Void = { try GameStore.remove($0) }
    ) {
        self.root = root
        self.installedTools = installedTools
        self.start = start
        self.remove = remove
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
            try start(game, picked)
            return String(localized: "Started \(picked.lastPathComponent) in \(game.name). When it has finished, choose the program that starts the game.")
        }
    }

    // The program Play starts, inside the game's prefix, where its installer put it.
    func chooseProgram(for game: StandaloneGame) async {
        let prefix = GameStore.prefix(of: game, in: root)
        guard hasPrefix(game) else {
            report = FailureReport([StepFailure(
                step: String(localized: "Choose Program"),
                detail: String(localized: "\(game.name) has no prefix yet. Run its installer first."))])
            return
        }
        let panel = Self.programPanel()
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the program that starts \(game.name).")
        let programs = prefix.pfx.appending(path: "drive_c/Program Files (x86)")
        panel.directoryURL = FileManager.default.fileExists(atPath: programs.path(percentEncoded: false))
            ? programs : prefix.pfx.appending(path: "drive_c")
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        await setProgram(picked, for: game)
    }

    func setProgram(_ picked: URL, for game: StandaloneGame) async {
        forgetOutcome()
        guard let path = GameStore.relativePath(of: picked, in: game, root: root) else {
            report = FailureReport([StepFailure(
                step: String(localized: "Choose Program"),
                detail: String(localized: "\(picked.lastPathComponent) is not inside the prefix of \(game.name). Choose a program its installer put there."))])
            return
        }
        var changed = game
        changed.executable = path
        act {
            try GameStore.save(changed, in: root)
            return String(localized: "Play now starts \(picked.lastPathComponent).")
        }
        await load()
    }

    func play(_ game: StandaloneGame) {
        act {
            try start(game, nil)
            return String(localized: "Started \(game.name).")
        }
    }

    func confirmRemove() async {
        guard let game = removing else { return }
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
