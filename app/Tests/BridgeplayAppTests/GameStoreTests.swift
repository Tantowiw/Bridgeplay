import Foundation
import Testing

@testable import BridgeplayApp

@Suite("Game store")
struct GameStoreTests {
    let tool = InstalledTool(tool: CompatTool(name: "bridgeplay-proton-winecx-11.17", flavor: .rosetta, display: "WineCX 11.17"), build: "winecx-11.17")

    @Test("IDs start above every Steam app and shortcut ID and are never handed out twice")
    func allocatesIDs() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try GameStore.add(name: "  Digimon Masters Online ", in: root)
        #expect(first.id == "5000000001")
        #expect(first.name == "Digimon Masters Online")
        #expect(UInt64(first.id)! > UInt64(UInt32.max))

        // A folder an add left without a record still holds its ID.
        try FileManager.default.createDirectory(at: root.appending(path: "5000000002"), withIntermediateDirectories: false)
        let second = try GameStore.add(name: "Second", in: root)
        #expect(second.id == "5000000003")

        #expect(GameStore.all(in: root).map(\.id) == ["5000000001", "5000000003"])
        #expect(throws: StepFailure.self) { try GameStore.add(name: " \n", in: root) }
    }

    @Test("Only numeric folders from the first ID up are games")
    func recognisesGameIDs() {
        #expect(GameStore.isGameID("5000000001"))
        #expect(!GameStore.isGameID("5000000000"))
        #expect(!GameStore.isGameID("3795902015"))
        #expect(!GameStore.isGameID("5000000001a"))
        #expect(!GameStore.isGameID("+5000000001"))
        #expect(!GameStore.isGameID(""))
    }

    @Test("A saved game reads back, sorted by name")
    func savesAndReads() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }

        var zeta = try GameStore.add(name: "zeta", in: root)
        _ = try GameStore.add(name: "Alpha", in: root)
        zeta.executable = "pfx/drive_c/Program Files/Zeta/Launcher.exe"
        zeta.arguments = ["-windowed"]
        try GameStore.save(zeta, in: root)

        #expect(GameStore.all(in: root).map(\.name) == ["Alpha", "zeta"])
        #expect(GameStore.game(id: zeta.id, in: root) == zeta)
        #expect(GameStore.game(id: "5000000099", in: root) == nil)
    }

    @Test("The program is kept relative to the game's folder and cannot leave it")
    func keepsTheProgramInsideTheFolder() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        var game = try GameStore.add(name: "Game", in: root)
        let exe = GameStore.folder(of: game.id, in: root).appending(path: "pfx/drive_c/Game/Game.exe")

        #expect(GameStore.relativePath(of: exe, in: game, root: root) == "pfx/drive_c/Game/Game.exe")
        #expect(GameStore.relativePath(of: root.appending(path: "Other.exe"), in: game, root: root) == nil)

        game.executable = "pfx/drive_c/Game/Game.exe"
        #expect(GameStore.executableURL(of: game, in: root)?.lastPathComponent == "Game.exe")
        for escaping in ["/Applications/Game.exe", "pfx/../../5000000002/pfx/x.exe", ""] {
            game.executable = escaping
            #expect(GameStore.executableURL(of: game, in: root) == nil)
        }
    }

    @Test("Play runs the tool's run script standalone, with the game's folder as compatdata")
    func buildsTheLaunch() throws {
        let work = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: work) }
        let root = work.appending(path: "games")
        let tools = work.appending(path: "compatibilitytools.d")
        var game = try GameStore.add(name: "Game", in: root)

        #expect(throws: StepFailure.self) { try GameStore.launch(game, tool: tool, root: root, compatTools: tools) }
        game.executable = "pfx/drive_c/Game/Launcher.exe"
        #expect(throws: StepFailure.self) { try GameStore.launch(game, tool: tool, root: root, compatTools: tools) }

        let exe = try #require(GameStore.executableURL(of: game, in: root))
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        #expect(throws: StepFailure.self) { try GameStore.launch(game, tool: tool, root: root, compatTools: tools) }

        let run = tools.appending(path: "\(tool.name)/run")
        try FileManager.default.createDirectory(at: run.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: run)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)

        game.arguments = ["-lang", "en"]
        let inherited = [
            "HOME": "/Users/tester", "STEAM_COMPAT_CLIENT_INSTALL_PATH": "/Steam", "STEAM_COMPAT_APP_ID": "480",
            "SteamAppId": "480", "SteamGameId": "480", "NOTPROTON_STANDALONE": "0", "BRIDGEPLAY_BACKEND": "dxvk",
        ]
        let launch = try GameStore.launch(game, tool: tool, root: root, compatTools: tools, environment: inherited)
        #expect(launch.run == run)
        #expect(launch.arguments == ["waitforexitandrun", exe.path(percentEncoded: false), "-lang", "en"])
        #expect(launch.directory == exe.deletingLastPathComponent())
        #expect(launch.environment == [
            "HOME": "/Users/tester",
            "BRIDGEPLAY_STANDALONE": "1",
            "STEAM_COMPAT_DATA_PATH": GameStore.folder(of: game.id, in: root).path(percentEncoded: false),
            "STEAM_COMPAT_INSTALL_PATH": exe.deletingLastPathComponent().path(percentEncoded: false),
        ])

        // An installer from outside the folder runs in the same prefix, without the game's arguments.
        let installer = work.appending(path: "Downloads/Setup.exe")
        try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: installer)
        let install = try GameStore.launch(game, program: installer, tool: tool, root: root, compatTools: tools, environment: inherited)
        #expect(install.arguments == ["waitforexitandrun", installer.path(percentEncoded: false)])
        #expect(install.environment["STEAM_COMPAT_DATA_PATH"] == launch.environment["STEAM_COMPAT_DATA_PATH"])
        #expect(install.directory == installer.deletingLastPathComponent())
    }

    @Test("Prefixes lists a game's prefix under Bridgeplay, by the game's name")
    func listsTheGamesPrefixes() throws {
        let work = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: work) }
        let library = GameStore.library(at: work.appending(path: "games"))
        let steam = SteamLibrary(root: work.appending(path: "steam"))

        let game = try GameStore.add(name: "Digimon Masters Online", in: library.root)
        _ = try GameStore.add(name: "Not run yet", in: library.root)
        try FileManager.default.createDirectory(
            at: GameStore.folder(of: game.id, in: library.root).appending(path: "pfx"), withIntermediateDirectories: true)
        // Anything else in the folder is not a game.
        try FileManager.default.createDirectory(
            at: library.root.appending(path: "480/pfx"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: steam.compatdata.appending(path: "480/pfx"), withIntermediateDirectories: true)

        let prefixes = PrefixStore.all(libraries: [steam, library])
        #expect(Set(prefixes.map(\.appID)) == ["480", game.id])
        let found = try #require(prefixes.first { $0.appID == game.id })
        #expect(found.title == "Digimon Masters Online")
        #expect(found.library.displayName == "Bridgeplay")
        #expect(found.root == GameStore.folder(of: game.id, in: library.root))
        #expect(found.pfx == GameStore.prefix(of: game, in: library.root).pfx)
    }

    @Test("Delete and Rebuild leave a game's prefix alone, since the game is installed in it")
    func refusesToRemoveTheGame() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let game = try GameStore.add(name: "Game", in: root)
        let prefix = GameStore.prefix(of: game, in: root)
        let installed = prefix.pfx.appending(path: "drive_c/Game/Game.exe")
        try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: installed)

        #expect(throws: StepFailure.self) { try PrefixTools.delete(prefix) }
        #expect(throws: StepFailure.self) { try PrefixTools.recreate(prefix, runner: root.appending(path: "runner")) }
        #expect(FileManager.default.fileExists(atPath: installed.path))
        #expect(GameStore.game(id: game.id, in: root) == game)
    }
}

@Suite("Game store: removing and tools")
struct GameStoreRemoveTests {
    @Test("Removing a game takes its folder and what Bridgeplay keeps under its ID, and nothing else")
    func removesTheGame() throws {
        let work = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: work) }
        let root = work.appending(path: "games")
        let launchers = work.appending(path: "launchers")
        let gamefixes = work.appending(path: "gamefixes")
        let game = try GameStore.add(name: "Gone", in: root)
        let kept = try GameStore.add(name: "Kept", in: root)
        for id in [game.id, kept.id] {
            try FileManager.default.createDirectory(at: launchers.appending(path: id), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: gamefixes, withIntermediateDirectories: true)
            try Data("BACKEND=dxmt\n".utf8).write(to: gamefixes.appending(path: "\(id).conf"))
        }

        try GameStore.remove(game, in: root, launchers: launchers, gamefixes: gamefixes)
        #expect(GameStore.all(in: root).map(\.id) == [kept.id])
        #expect(!FileManager.default.fileExists(atPath: launchers.appending(path: game.id).path))
        #expect(!FileManager.default.fileExists(atPath: gamefixes.appending(path: "\(game.id).conf").path))
        #expect(FileManager.default.fileExists(atPath: launchers.appending(path: kept.id).path))
        #expect(FileManager.default.fileExists(atPath: gamefixes.appending(path: "\(kept.id).conf").path))
    }

    @Test("Play uses the game's own tool while it is installed")
    func picksTheGamesTool() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = InstalledTool(tool: CompatTool(name: "first", flavor: .rosetta, display: "First"), build: "a")
        let chosen = InstalledTool(tool: CompatTool(name: "chosen", flavor: .rosetta, display: "Chosen"), build: "b")
        var game = try GameStore.add(name: "Game", tool: "chosen", in: root)
        #expect(GameStore.game(id: game.id, in: root)?.tool == "chosen")
        #expect(try GameStore.tool(for: game, among: [first, chosen]) == chosen)
        game.tool = "uninstalled"
        #expect(try GameStore.tool(for: game, among: [first, chosen]) == first)
    }
}

@MainActor
@Suite("Games page")
struct GamesModelTests {
    final class Started: @unchecked Sendable {
        var calls: [(String, URL?)] = []
    }

    @Test("A program is kept only from inside the game's prefix, and Play starts the game")
    func choosesTheProgramAndPlays() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Started()
        let model = GamesModel(root: root, installedTools: { [] }, start: { started.calls.append(($0.id, $1)) })

        let game = try #require(await model.add(name: "Game", tool: nil))
        #expect(model.games.map(\.id) == [game.id])
        #expect(model.selection == game.id)
        #expect(!model.hasPrefix(game))

        let inside = GameStore.folder(of: game.id, in: root).appending(path: "pfx/drive_c/Game/Launcher.exe")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: inside)

        await model.setProgram(root.appending(path: "Elsewhere.exe"), for: game)
        #expect(model.report != nil)
        #expect(model.program(model.games[0]) == nil)

        await model.setProgram(inside, for: game)
        #expect(model.report == nil)
        let saved = model.games[0]
        #expect(saved.executable == "pfx/drive_c/Game/Launcher.exe")
        #expect(model.program(saved) == "Launcher.exe")

        model.play(saved)
        #expect(started.calls.count == 1)
        #expect(started.calls.first?.0 == game.id)
        #expect(started.calls.first?.1 == nil)
    }

    @Test("Removing asks first, and a refusal is reported")
    func removesAfterConfirming() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GamesModel(
            root: root, installedTools: { [] }, start: { _, _ in },
            remove: { game in
                if game.name == "Busy" { throw StepFailure(step: "Remove", detail: "running") }
                try FileManager.default.removeItem(at: GameStore.folder(of: game.id, in: root))
            })
        let busy = try #require(await model.add(name: "Busy", tool: nil))
        let gone = try #require(await model.add(name: "Gone", tool: nil))

        await model.confirmRemove()
        #expect(model.games.count == 2)

        model.removing = busy
        await model.confirmRemove()
        #expect(model.report != nil)
        #expect(model.games.count == 2)

        model.removing = gone
        await model.confirmRemove()
        #expect(model.report == nil)
        #expect(model.games.map(\.id) == [busy.id])
        #expect(model.removing == nil)
    }
}
