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

    @Test("A program inside the game's folder is kept relative to it, one elsewhere by its full path")
    func keepsTheProgramsPath() throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        var game = try GameStore.add(name: "Game", in: root)
        let exe = GameStore.folder(of: game.id, in: root).appending(path: "pfx/drive_c/Game/Game.exe")

        #expect(GameStore.relativePath(of: exe, in: game, root: root) == "pfx/drive_c/Game/Game.exe")
        #expect(GameStore.relativePath(of: root.appending(path: "Other.exe"), in: game, root: root) == nil)

        game.executable = "pfx/drive_c/Game/Game.exe"
        #expect(GameStore.executableURL(of: game, in: root)?.lastPathComponent == "Game.exe")
        for escaping in ["pfx/../../5000000002/pfx/x.exe", ""] {
            game.executable = escaping
            #expect(GameStore.executableURL(of: game, in: root) == nil)
        }

        let unpacked = root.appending(path: "Downloads/DMW/DMLauncher.exe")
        #expect(GameStore.storedPath(of: exe, in: game, root: root) == "pfx/drive_c/Game/Game.exe")
        #expect(GameStore.storedPath(of: unpacked, in: game, root: root) == unpacked.path(percentEncoded: false))
        game.executable = GameStore.storedPath(of: unpacked, in: game, root: root)
        #expect(GameStore.executableURL(of: game, in: root) == URL(filePath: unpacked.path(percentEncoded: false)))
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

        // A game unpacked outside the folder starts from where it is, with its arguments.
        let unpacked = work.appending(path: "Downloads/DMW/DMLauncher.exe")
        try FileManager.default.createDirectory(at: unpacked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: unpacked)
        var outside = game
        outside.executable = GameStore.storedPath(of: unpacked, in: game, root: root)
        let played = try GameStore.launch(outside, tool: tool, root: root, compatTools: tools, environment: inherited)
        #expect(played.arguments == ["waitforexitandrun", unpacked.path(percentEncoded: false), "-lang", "en"])
        #expect(played.environment["STEAM_COMPAT_INSTALL_PATH"] == unpacked.deletingLastPathComponent().path(percentEncoded: false))
        #expect(played.environment["STEAM_COMPAT_DATA_PATH"] == launch.environment["STEAM_COMPAT_DATA_PATH"])

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

    @Test("A program is kept from inside the game's prefix or from anywhere else, and Play starts the game")
    func choosesTheProgramAndPlays() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Started()
        let model = GamesModel(root: root, installedTools: { [] }, start: { game, program, _ in started.calls.append((game.id, program)) },
            defaults: try #require(UserDefaults(suiteName: "games-\(UUID().uuidString)")))

        let game = try #require(await model.add(name: "Game", tool: nil))
        #expect(model.games.map(\.id) == [game.id])
        #expect(model.selection == game.id)
        #expect(!model.hasPrefix(game))

        let inside = GameStore.folder(of: game.id, in: root).appending(path: "pfx/drive_c/Game/Launcher.exe")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: inside)

        let elsewhere = root.appending(path: "Downloads/DMW/DMLauncher.exe")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: elsewhere)
        await model.setProgram(elsewhere, for: game)
        #expect(model.report == nil)
        #expect(model.games[0].executable == elsewhere.path(percentEncoded: false))
        #expect(model.programFolder(for: model.games[0])?.path(percentEncoded: false)
            == elsewhere.deletingLastPathComponent().path(percentEncoded: false))

        await model.setProgram(inside, for: game)
        #expect(model.report == nil)
        let saved = model.games[0]
        #expect(saved.executable == "pfx/drive_c/Game/Launcher.exe")
        #expect(model.program(saved) == "Launcher.exe")
        #expect(model.programFolder(for: saved)?.path(percentEncoded: false)
            == inside.deletingLastPathComponent().path(percentEncoded: false))

        model.play(saved)
        #expect(started.calls.count == 1)
        #expect(started.calls.first?.0 == game.id)
        #expect(started.calls.first?.1 == nil)
    }

    @Test("Removing takes the confirmed game even after the dialog cleared it, and a refusal is reported")
    func removesAfterConfirming() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GamesModel(
            root: root, installedTools: { [] }, start: { _, _, _ in },
            remove: { game in
                if game.name == "Busy" { throw StepFailure(step: "Remove", detail: "running") }
                try FileManager.default.removeItem(at: GameStore.folder(of: game.id, in: root))
            })
        let busy = try #require(await model.add(name: "Busy", tool: nil))
        let gone = try #require(await model.add(name: "Gone", tool: nil))

        model.removing = busy
        await model.removeGame(busy)
        #expect(model.report != nil)
        #expect(model.games.count == 2)

        // The dialog clears `removing` as it closes, before its button's task runs.
        model.removing = gone
        model.removing = nil
        await model.removeGame(gone)
        #expect(model.report == nil)
        #expect(model.games.map(\.id) == [busy.id])
        #expect(model.removing == nil)
    }
}

@Suite("Force Quit")
struct ForceQuitTests {
    let prefix = WinePrefix(appID: "5000000001", name: "Game", library: GameStore.library(at: URL(filePath: "/nonexistent")), lastUsed: nil)

    final class Calls: @unchecked Sendable {
        var stops = 0
        var running = true
    }

    @Test("A prefix with nothing running is left alone")
    func leavesAnIdlePrefixAlone() throws {
        let calls = Calls()
        let stopped = try PrefixTools.forceQuit(prefix, isInUse: { _ in false }, stopServer: { _ in calls.stops += 1 })
        #expect(!stopped)
        #expect(calls.stops == 0)
    }

    @Test("A running prefix is stopped and waited for")
    func stopsARunningPrefix() throws {
        let calls = Calls()
        let stopped = try PrefixTools.forceQuit(
            prefix, isInUse: { _ in calls.running }, stopServer: { _ in calls.stops += 1; calls.running = false })
        #expect(stopped)
        #expect(calls.stops == 1)
    }

    @Test("A prefix still running afterwards is reported")
    func reportsAPrefixThatKeepsRunning() {
        let calls = Calls()
        #expect(throws: StepFailure.self) {
            try PrefixTools.forceQuit(prefix, isInUse: { _ in true }, stopServer: { _ in calls.stops += 1 }, settle: 0.3)
        }
        #expect(calls.stops == 1)
    }

    @MainActor
    @Test("The Games page says whether the game was stopped, and reports a failure")
    func reportsTheOutcome() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Calls()
        let model = GamesModel(
            root: root, installedTools: { [] }, start: { _, _, _ in }, remove: { _ in },
            stop: { game in
                if game.name == "Stuck" { throw StepFailure(step: "Force Quit", detail: "still running") }
                defer { calls.running = false }
                return calls.running
            })
        let game = try #require(await model.add(name: "Game", tool: nil))
        let stuck = try #require(await model.add(name: "Stuck", tool: nil))

        // The dialog clears `quitting` as it closes, before its button's task runs.
        model.quitting = game
        model.quitting = nil
        await model.forceQuit(game)
        #expect(model.outcome == String(localized: "Force quit \(game.name)."))
        await model.forceQuit(game)
        #expect(model.outcome == String(localized: "\(game.name) is not running."))
        await model.forceQuit(stuck)
        #expect(model.report != nil)
        #expect(model.quitting == nil)
    }
}

@Suite("FPS window")
struct WineFPSTests {
    @Test("Readings come only from the fps trace lines")
    func readsTheTraceLines() {
        let log = """
        014c:trace:fps:wglSwapBuffers @ approx 0.00fps, total 0.00fps
        014c:trace:fps:wined3d_cs_exec_present 014AF908 @ approx 112.29fps
        0250:err:d3d:wined3d_swapchain_resize_buffers Something's still holding back buffer 0 (12F5B1C0).
        info:  the game said @ approx 99.00fps
        014c:trace:fps:wined3d_cs_exec_present 014AF908 @ approx 117.80fps
        """
        #expect(WineFPS.readings(in: log) == [0, 112.29, 117.80])
    }

    @Test("WINEDEBUG keeps what the game gets and adds the fps channel once")
    func addsTheChannel() {
        #expect(WineFPS.debug(nil) == "err+all,fixme-all,trace+fps")
        #expect(WineFPS.debug("") == "err+all,fixme-all,trace+fps")
        #expect(WineFPS.debug("+loaddll") == "+loaddll,trace+fps")
        #expect(WineFPS.debug("err+all,+fps") == "err+all,+fps")
        #expect(WineFPS.debug("-fps") == "-fps")
    }

    @Test("The reader follows a growing log, skips what was there and starts over when the log is new")
    func followsTheLog() throws {
        let dir = try scratchDirectory("fps")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appending(path: "bridgeplay-wine.log")
        try Data("0001:trace:fps:x @ approx 30.00fps\n".utf8).write(to: log)

        var reader = WineFPS.Reader(url: log)
        #expect(reader.read().isEmpty)

        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("0001:trace:fps:x @ approx 58.10fps\n0001:trace:fps:x @ appr".utf8))
        #expect(reader.read() == [58.10])
        try handle.write(contentsOf: Data("ox 59.90fps\n".utf8))
        #expect(reader.read() == [59.90])
        try handle.close()

        // The next launch starts the log afresh.
        try Data("0001:trace:fps:x @ approx 12.50fps\n".utf8).write(to: log)
        #expect(reader.read() == [12.50])
    }

    @Test("Show FPS adds the channel to the WINEDEBUG the game's confs set")
    func launchesWithTheChannel() throws {
        let work = try scratchDirectory("fps")
        defer { try? FileManager.default.removeItem(at: work) }
        let root = work.appending(path: "games")
        let tools = work.appending(path: "compatibilitytools.d")
        let gamefixes = work.appending(path: "gamefixes")
        let tool = InstalledTool(tool: CompatTool(name: "t", flavor: .rosetta, display: "T"), build: "b")
        let run = tools.appending(path: "t/run")
        try FileManager.default.createDirectory(at: run.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: run)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)
        let exe = work.appending(path: "Game/Game.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        var game = try GameStore.add(name: "Game", in: root)
        game.executable = exe.path(percentEncoded: false)

        func debug(_ show: Bool, _ environment: [String: String] = [:]) throws -> String? {
            try GameStore.launch(game, tool: tool, root: root, compatTools: tools, environment: environment,
                                 showFPS: show, gamefixes: gamefixes).environment["WINEDEBUG"]
        }
        #expect(try debug(false) == nil)
        #expect(try debug(true) == "err+all,fixme-all,trace+fps")

        try FileManager.default.createDirectory(at: gamefixes, withIntermediateDirectories: true)
        try Data("WINEDEBUG=+seh\n".utf8).write(to: gamefixes.appending(path: "default.conf"))
        try Data("RETINA=0\nWINEDEBUG=+loaddll\n".utf8).write(to: gamefixes.appending(path: "\(game.id).conf"))
        #expect(try debug(true) == "+loaddll,trace+fps")
        #expect(try debug(true, ["WINEDEBUG": "warn+all"]) == "warn+all,trace+fps")
    }

    final class Calls: @unchecked Sendable {
        var flags: [Bool] = []
    }

    @MainActor
    @Test("Play opens the FPS window only when Show FPS is on, and the choice is kept")
    func opensTheWindow() async throws {
        let root = try scratchDirectory("games")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "games-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calls = Calls()
        var windows: [String] = []
        let model = GamesModel(
            root: root, installedTools: { [] }, start: { _, _, fps in calls.flags.append(fps) },
            showFPSWindow: { windows.append($0.id) }, defaults: defaults)
        let game = try #require(await model.add(name: "Game", tool: nil))

        #expect(!model.showFPS)
        model.play(game)
        model.showFPS = true
        model.play(game)
        #expect(calls.flags == [false, true])
        #expect(windows == [game.id])

        let again = GamesModel(root: root, installedTools: { [] }, defaults: defaults)
        #expect(again.showFPS)
    }
}
