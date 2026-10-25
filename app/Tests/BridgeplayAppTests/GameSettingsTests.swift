import Foundation
import Testing
@testable import BridgeplayApp

@Suite struct GameSettingsTests {
    @Test func readsTheLastAssignmentInEitherSpelling() {
        #expect(GameSettings.value(.graphics, in: "BACKEND=dxmt\nBACKEND=dxvk\n") == "dxvk")
        #expect(GameSettings.value(.frameGeneration, in: "  BRIDGEPLAY_FRAMEGEN=3  \n") == "3")
        #expect(GameSettings.value(.highResolution, in: "RETINA=1\nBRIDGEPLAY_RETINA=0\n") == "0")
        #expect(GameSettings.value(.metalHUD, in: "# MTL_HUD_ENABLED=1\n") == nil)
        // BRIDGEPLAY_ is only a spelling of the keys that set a BRIDGEPLAY_ variable.
        #expect(GameSettings.value(.graphics, in: "BRIDGEPLAY_BACKEND=dxmt\n") == nil)
    }

    @Test func readsTheFirstReleasesFrameGenerationOneAsTwo() {
        #expect(GameSettings.value(.frameGeneration, in: "FRAMEGEN=1\n") == "2")
    }

    @Test func inheritsTheShippedConfOverDefaultConf() {
        let global = "MTL_HUD_ENABLED=1\nBACKEND=dxmt\n"
        let shipped = "BACKEND=d3dmetal\n"
        #expect(GameSettings.inherited(.graphics, from: [global, shipped]) == "d3dmetal")
        #expect(GameSettings.inherited(.metalHUD, from: [global, shipped]) == "1")
        #expect(GameSettings.inherited(.msync, from: [global, shipped]) == nil)
    }

    @Test func keepsEveryOtherLineAndReplacesOnlyItsOwn() {
        let text = "# mine\nBACKEND=dxmt\nFRAMEGEN=2\nBRIDGEPLAY_FRAMEGEN=3\nNVAPI=1\n"
        let changed = GameSettings.setting(.frameGeneration, to: "adaptive", in: text)
        #expect(changed == "# mine\nBACKEND=dxmt\nNVAPI=1\nFRAMEGEN=adaptive\n")
        let cleared = GameSettings.setting(.graphics, to: nil, in: changed)
        #expect(cleared == "# mine\nNVAPI=1\nFRAMEGEN=adaptive\n")
    }

    @Test func startsANewFileWithItsHeaderAndEmptiesItWhenAllIsDefault() {
        let set = GameSettings.setting(.graphics, to: "dxmt", in: "")
        #expect(set == GameSettings.header + "\nBACKEND=dxmt\n")
        #expect(GameSettings.setting(.graphics, to: nil, in: set) == "")
        #expect(GameSettings.setting(.metalHUD, to: "0", in: "") == GameSettings.header + "\nMTL_HUD_ENABLED=0\n")
    }

    @Test func offersOnlyValuesTheRunScriptAccepts() {
        #expect(GameSettings.Setting.graphics.values == ["d3dmetal", "dxmt", "dxvk", "wined3d"])
        #expect(GameSettings.Setting.frameGeneration.values == ["0", "2", "3", "adaptive"])
        #expect(GameSettings.Setting.frameGenerationEngine.values == ["own", "metalfx"])
        for setting in GameSettings.Setting.allCases {
            if let builtIn = setting.builtInDefault { #expect(setting.values.contains(builtIn)) }
        }
    }

    @Test func readsLaunchOptionsAsTheRunScriptDoes() {
        func read(_ options: String) -> [GameSettings.Setting: String] { GameSettings.launchOptionValues(options) }
        #expect(read("BRIDGEPLAY_FRAMEGEN=2 %command%") == [.frameGeneration: "2"])
        #expect(read("BRIDGEPLAY_FRAMEGEN=2 BRIDGEPLAY_FRAMEGEN=3 %command%") == [.frameGeneration: "3"])
        #expect(read("BRIDGEPLAY_FRAMEGEN=2 NOTPROTON_FRAMEGEN=Adaptive %command%") == [.frameGeneration: "adaptive"])
        #expect(read("BRIDGEPLAY_FRAMEGEN=1 %command%") == [.frameGeneration: "2"])
        #expect(read("BRIDGEPLAY_FRAMEGEN=off BRIDGEPLAY_FRAMEGEN_QUALITY=Quality %command%")
            == [.frameGeneration: "0", .frameGenerationQuality: "quality"])
        #expect(read("WINEMSYNC=0 MTL_HUD_ENABLED=1 BRIDGEPLAY_RETINA=0 %command%")
            == [.msync: "0", .metalHUD: "1", .highResolution: "0"])
        // Quotes and arguments after %command% are the shell's and the game's.
        #expect(read(#""BRIDGEPLAY_FRAMEGEN=3" FOO='a b' %command% -title "x y" WINEMSYNC=0"#) == [.frameGeneration: "3"])
    }

    @Test func readsTheGraphicsChoiceInTheRunScriptsOrder() {
        func graphics(_ options: String) -> String? { GameSettings.launchOptionValues(options)[.graphics] }
        #expect(graphics("CX_GRAPHICS_BACKEND=DXMT %command%") == "dxmt")
        #expect(graphics("BRIDGEPLAY_BACKEND=dxvk CX_GRAPHICS_BACKEND=dxmt %command%") == "dxvk")
        // A BRIDGEPLAY_BACKEND the run script ignores leaves the panel's choice in charge.
        #expect(graphics("BRIDGEPLAY_BACKEND=metal CX_GRAPHICS_BACKEND=opengl %command%") == "wined3d")
        #expect(graphics("CX_GRAPHICS_BACKEND=vulkan %command%") == nil)
    }

    @Test func ignoresLaunchOptionsWithoutCommand() {
        #expect(GameSettings.launchOptionValues("BRIDGEPLAY_FRAMEGEN=2 -novid").isEmpty)
        #expect(GameSettings.launchOptionValues("%command% BRIDGEPLAY_FRAMEGEN=2").isEmpty)
        #expect(GameSettings.launchOptionValues("").isEmpty)
    }

    @Test func writesReadsBackAndRemovesAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gamesettings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "gamefixes/3795902015.conf")
        try GameSettings.set(.graphics, to: "dxmt", at: url)
        try GameSettings.set(.frameGeneration, to: "2", at: url)
        #expect(GameSettings.value(.graphics, in: GameSettings.text(at: url)) == "dxmt")
        #expect(GameSettings.value(.frameGeneration, in: GameSettings.text(at: url)) == "2")
        try GameSettings.set(.graphics, to: nil, at: url)
        try GameSettings.set(.frameGeneration, to: nil, at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
