<p align="center">
  <a href="https://bridgeplay.dev"><img src="docs/readme/banner-v6.png" alt="Bridgeplay: Windows games, in your Mac's Steam" width="100%"></a>
</p>

<p align="center">
  <b>Windows-only Steam games on Apple Silicon, right inside the Steam you already use.</b><br>
  Same library. Same Play button. No bottles, no second launcher.
</p>

<p align="center">
  <a href="https://bridgeplay.dev"><img alt="Website" src="https://img.shields.io/badge/bridgeplay.dev-000?style=for-the-badge&logo=safari&logoColor=white"></a>
  <a href="https://github.com/raymondchins/Bridgeplay/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/raymondchins/Bridgeplay?style=for-the-badge&logo=github&color=000&labelColor=1c1c1e"></a>
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-M1_or_later-000?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000?style=for-the-badge">
  <a href="LICENSE"><img alt="License GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-000?style=for-the-badge"></a>
</p>

> **Bridgeplay is a fork of [NotProton](https://github.com/NotProtonNot/NotProton)** by NotProtonNot. Games run on CodeWeavers' open-source Wine, the engine behind [CrossOver](https://www.codeweavers.com/crossover), and Apple's Game Porting Toolkit. I'm not affiliated with either. If CrossOver works for you, buy it: that money is a big part of what keeps Wine on the Mac moving. Bridgeplay is a hobby project I maintain part-time, so support is best-effort. Full list in [Credits](#credits) and [Support Wine](#support-wine).

> [!NOTE]
> **This is a personal fork of [raymondchins/Bridgeplay](https://github.com/raymondchins/Bridgeplay).** It adds a Games page for Windows games that are not on Steam, plus a few WineCX fixes. See [About this fork](#about-this-fork). It has no signed download: you build it yourself. For everything else, use the official Bridgeplay from [bridgeplay.dev](https://bridgeplay.dev).

<br>

<p align="center">
  <img src="docs/readme/bento-v5.png" alt="What Bridgeplay does: plays inside Mac Steam, experimental frame generation, DLSS answered by MetalFX, DirectX 12 on Metal, any controller, full Retina one switch away, guided install" width="100%">
</p>

## About this fork

This fork lets Bridgeplay play Windows games that are not on Steam, and fixes a few things in the WineCX engine found along the way. Everything else is upstream Bridgeplay. The fork's commits are rebased onto each upstream release. The current branch is [`feat/standalone-ui-main`](https://github.com/Tantowiw/Bridgeplay/tree/feat/standalone-ui-main), based on upstream `main` after 0.7.67.

| | |
|---|---|
| **Games page** (⌘2) | Windows games that are not on Steam. **New Game** takes a name and a compatibility tool, then runs the game's installer in its own prefix. **Choose Program** sets what **Play** starts, from inside the prefix or from a folder unpacked anywhere. Games are kept in `~/Library/Application Support/bridgeplay-games`, which **Remove Everything** leaves alone. |
| **Game Settings** | Graphics backend, Metal HUD, MSync, high resolution and frame generation for a game that has no Bridgeplay panel in Steam. The settings go into the game's `gamefixes/<appid>.conf`, and the sheet says where a Steam launch option overrides one of them. |
| **Force Quit** | Stops every process in a hung game's prefix (`wineserver -k`). It is on the Games page, and on the Prefixes page for Steam games and shortcuts. |
| **FPS window** | A small frame counter over the game, for games that wined3d draws through OpenGL. Metal HUD and DXVK's HUD can't see those games. |
| **Standalone run script** | `BRIDGEPLAY_STANDALONE=1` runs a game without Steam's client. Steamclient, the overlay and `Steam.dll` are left out; only `steam.exe` is staged, so the script can wait for every process the game starts. |
| **WineCX 11.17 fixes** | Legacy OpenGL contexts now get their extensions: Wine commit 1c2d9098 is backported into `win32u`. WMI now reports a system-managed page file (patched `wbemprox`), so games that refused to start with "Insufficient memory or disk space" can start. Sources, recipes and pins are in [`win32u-patch/`](win32u-patch/), [`wbemprox-patch/`](wbemprox-patch/) and [docs/WINECX.md](docs/WINECX.md). |

The fork's strings are translated like the rest of the app: English, Italian, Russian and Simplified Chinese.

### Installing this fork

1. Build it on an Apple Silicon Mac with Xcode 27 ([docs/BUILD-LOCAL.md](docs/BUILD-LOCAL.md)):
   ```sh
   git clone -b feat/standalone-ui-main https://github.com/Tantowiw/Bridgeplay.git
   cd Bridgeplay
   scripts/build-local.sh
   ```
2. Quit Steam. Replace `/Applications/Bridgeplay.app` with `build/Bridgeplay.app`, then open it.
3. The build is signed ad hoc, so macOS forgets its App Management permission after every new build. In **System Settings › Privacy & Security › App Management**, remove Bridgeplay with − and add it again with +. Then click **Install** on the Status page. With Steam closed, `/Applications/Bridgeplay.app/Contents/MacOS/BridgeplayApp --install-into-steam` does the same thing.

Things to know:

- **Upstream updates replace the fork.** The app keeps upstream's update feed. When upstream releases a new version, Sparkle installs the official app over this one, and the Games page disappears. Your games and their prefixes stay in `bridgeplay-games`, but you can't play them until you rebuild from this fork, after it has been rebased onto that release.
- **Report problems with the fork's features here**, in this repository's issues, not upstream's. Upstream has nothing to do with them.

## What it does

| | |
|---|---|
| **Plays inside Mac Steam** | Windows games sit in your Mac Steam library and start with Play. They run in Wine under Rosetta 2. |
| **DirectX 12 on Metal** | Apple's D3DMetal runs DirectX 11 and 12 on your Mac's GPU. |
| **DLSS, answered by MetalFX** | Games on D3DMetal see an NVIDIA card by default, so DLSS shows up. Apple's toolkit runs it on MetalFX. |
| **Frame generation (experimental)** | Up to 3× displayed frames, with a little added latency. Off by default; turn it on per game. |
| **Any controller** | DualSense, Xbox, GameSir and more, with no mapping screen. |
| **Full Retina, one switch away** | Off by default because it's slower. Turn on High Resolution to draw at your display's real resolution. |
| **Guided install** | A Setup Assistant walks you through Rosetta, Steam and permissions. |

<p align="center">
  <img src="docs/readme/tour-v6.png" alt="Mac gaming, unleashed: 007 First Light running on Direct3D 12 through D3DMetal, with the Metal HUD at 90 fps" width="100%">
</p>
<p align="center"><sub>Illustrations of the real screens.</sub></p>

## Already playing

<p align="center">
  <img src="docs/readme/games-v6.png" alt="Games running with Bridgeplay: Resident Evil Requiem, Marvel's Spider-Man 2, 007 First Light and more" width="100%">
</p>

Developer's tests on an M5 Max MacBook Pro with Game Porting Toolkit 4.0 beta 3: 90+ fps, with MetalFX upscaling and frame generation where listed. Settings come from each game's launch log.

| Game | Launch settings |
|---|---|
| Resident Evil Requiem | D3DMetal · DLSS → MetalFX · DLSS Frame Gen (experimental) · Retina · V-Sync forced |
| Marvel's Spider-Man 2 | D3DMetal · Retina · MSync |
| 007 First Light | D3DMetal · DLSS → MetalFX · DLSS Frame Gen (experimental) · Retina |

Also running on the same setup: Mortal Kombat 1, The Last of Us Part I, Death Stranding Director's Cut, Horizon Zero Dawn, Split Fiction, It Takes Two, A Way Out, Batman: Arkham Knight, Sifu, Ghostrunner, Ravenswatch, Megabonk, PowerWash Simulator 2, The Witcher 3.

<sub>Most games with kernel-level anti-cheat won't run.</sub>

### Compatibility list

Every game tested so far, and the Mac it ran on, is at [bridgeplay.dev/compatibility](https://bridgeplay.dev/compatibility). It combines results a maintainer checked ([`compat/`](compat/)), one-tap reports from players, and CrossOver ratings from AppleGamingWiki for games nobody has tried with Bridgeplay yet.

To add yours: after you play, Bridgeplay asks once per game *How did it run?* One tap posts the result, with your Mac and the game's log, to [Compatibility reports](https://github.com/raymondchins/Bridgeplay/discussions/categories/compatibility-reports). No GitHub account needed, and the log is stripped of your user, computer and Steam account details. **Report Your Games…** in the Prefix menu covers everything you've already played, and [bridgeplay.dev/privacy](https://bridgeplay.dev/privacy) lists what a report contains. Without the app, use the [Game report form](https://github.com/raymondchins/Bridgeplay/issues/new?template=game-report.yml).

## Install

1. **Download Bridgeplay** from [bridgeplay.dev](https://bridgeplay.dev): `Bridgeplay.dmg`, notarized by Apple.
2. **Drag Bridgeplay into Applications** and open it. macOS asks once whether to open an app downloaded from the internet: click **Open**. It needs an admin account.
3. **Follow the Setup Assistant**: Rosetta, Apple's graphics (Download fetches them, and Steam from Valve if it's missing), Steam sign-in, App Management and a couple of other standard macOS prompts. Every download is verified: Bridgeplay's signature or pinned hashes for its own files and the engine, Apple's signature for the toolkit's files, Valve's for Steam. Setup modifies your Steam app; see [What Bridgeplay changes in Steam](#what-bridgeplay-changes-in-steam).
4. **Press Play** on any Windows game in Steam. The first time you use a controller, allow Steam's Input Monitoring request.

Each game's Bridgeplay settings (graphics backend, performance overlay, frame rate limit, scaling filter, DLSS, frame generation, controllers) are in Steam: right-click the game, **Properties… › Bridgeplay**.

Updates install themselves: Bridgeplay, its patch in Steam and the engine. **Refresh** on the Status page checks on demand.

The Setup Assistant's graphics download carries Apple's Game Porting Toolkit redistributables, unmodified, under Apple's own license; [docs/GPTK-LICENSE.md](docs/GPTK-LICENSE.md) records how Bridgeplay handles it. You can use your own copy from Apple instead. Bridgeplay is free and non-commercial.

<p align="center">
  <img src="docs/readme/install-v6.png" alt="The Setup Assistant working through Your Mac, Rosetta, Graphics, Steam and Set Up" width="100%">
</p>

## Requirements

<p align="center">
  <a href="https://bridgeplay.dev/#specs"><img src="docs/readme/specs-v6.png" alt="Check your Mac in one click on bridgeplay.dev, next to the minimum requirements" width="100%"></a>
</p>

| | |
|---|---|
| Mac | Apple Silicon, M1 or later. Intel Macs are not supported. |
| macOS | 26 or later ([macOS version guide](https://bridgeplay.dev/guides/macos-version-requirements)) |
| Steam | A Steam account. Windows games install from Steam as usual. |
| Download | About 550 MB: a 19 MB disk image, then about 530 MB, most of it the engine, that the Setup Assistant fetches. Installing Rosetta 2 and Steam, and signing in to Steam, need internet. |

## Guides and help

The [guides on bridgeplay.dev](https://bridgeplay.dev/guides) cover installing Bridgeplay, troubleshooting, DirectX 12, DLSS and frame generation, and anti-cheat. The [FAQ](https://bridgeplay.dev/faq) answers common questions, and the [compatibility list](https://bridgeplay.dev/compatibility) shows which games other players got running.

## How it works

Bridgeplay runs inside the native macOS Steam client and registers itself as a Steam Play compatibility tool. Under the hood:

- **Engine:** dappermint's prebuilt runtime ([winecx-gptk](https://github.com/dappermint/winecx-gptk)) of CodeWeavers' open-source WineCX 11.17 ([dappermint/winecx](https://github.com/dappermint/winecx)) with MSync, running under Rosetta 2. Bridgeplay does not include CrossOver. If you own CrossOver, Bridgeplay can run games on your copy instead.
- **Graphics:** Apple's Game Porting Toolkit 4.0 beta 3 (D3DMetal). It is not stored in this repository; the Setup Assistant downloads its redistributables, which stay under Apple's own license (see Install). DXMT and DXVK are available for games that prefer them.
- **Extras:** NVAPI/NGX routing for DLSS on Apple's MetalFX, in-process frame generation on `CAMetalLayer`, per-game Game Mode, Retina back buffers and a controller layer for HID pads.

<p align="center">
  <img src="docs/readme/architecture-v5.png" alt="How a Windows game reaches the Mac's GPU: Steam, Bridgeplay, the WineCX and Wine engines, D3DMetal, DXMT, DXVK and MoltenVK, then Metal, with the open-source project behind each piece" width="100%">
</p>

Building from source: see [docs/DEVELOPING.md](docs/DEVELOPING.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/BUILD-LOCAL.md](docs/BUILD-LOCAL.md). The graphics download (`Bridgeplay-Installer.zip`) is built from [`installer/`](installer/) by `scripts/package-installer.sh`.

## What Bridgeplay changes in Steam

Bridgeplay modifies your Steam app. It copies a library (`notproton.dylib`) into `/Applications/Steam.app`, makes Steam load it at startup through `Info.plist`, and re-signs Steam on your Mac, replacing Valve's signature. The library hooks Steam's compatibility tool, shortcut and launch option code, and edits Steam's interface in memory to show Steam Play.

Also changed:

- Steam's default compatibility tool is set in `config.vdf`, and Bridgeplay's tools go in `compatibilitytools.d`.
- Steam's Accessibility and input permissions are reset (`tccutil`), so macOS asks again.
- Steam is signed with a local "NotProton Local Signing" keychain identity, or ad hoc, and loses Valve's hardened runtime.
- The quarantine flag is removed from the Wine engines once they match their pins, and from a CrossOver clone once its Wine loader and `ntdll.dll` match theirs (the rest of the clone isn't checked file by file). Wine loaders are re-signed ad hoc where needed. The older `Install.command` installer also removes it from Bridgeplay.app and Steam.app.
- Optional **Block Steam client updates** (`steam.cfg`) also blocks Steam's security fixes.
- The library loads for every macOS user of a shared `/Applications/Steam.app`.
- In games, Steam calls reach your Mac Steam through Proton's lsteamclient, via an in-memory redirect (`ntdll-patch/`).
- Games on D3DMetal see an NVIDIA GeForce RTX 4090 by default, so DLSS shows up. `NVAPI=0` turns that off.
- For Apple's MetalFX DLSS only, patched `crypt32` and `wintrust` pass NVIDIA's signature check on Apple's `nvngx.dll` (`ngx-signer-patch/`).
- Some gamefixes turn off a game's Wine check to unlock DLSS, for example in Resident Evil Requiem and The Witcher 3.

Valve doesn't support or endorse Bridgeplay, and modifying Steam may go against the [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/). Use it at your own risk. **Repair Steam** or **Remove Everything** on the Status page restores Steam's `Info.plist`; if Valve's signature isn't back, reinstall Steam from Valve.

## Online games and anti-cheat

Online games with anti-cheat (Easy Anti-Cheat, BattlEye and others) often won't start, and Bridgeplay can't promise that anti-cheat, VAC included, won't flag it. Counter-Strike 2 and Dota 2 run, but VAC keeps them off its secure servers. Play online at your own risk. The [compatibility list](compat/README.md) shows what other players found.

## Credits

Bridgeplay is a fork of [NotProton](https://github.com/NotProtonNot/NotProton) by [NotProtonNot](https://github.com/NotProtonNot) and [its contributors](https://github.com/NotProtonNot/NotProton/graphs/contributors) (GPL-3.0), by way of [Leon Seemann](https://github.com/leonseemann)'s NotProton-WineHQ. The Steam hooks, the Steam Play interface patches, the run script and the steamclient bridge all started as their work. Copyright and license details are in [NOTICE](NOTICE).

- **Engine:** CodeWeavers' [WineCX](https://www.codeweavers.com/crossover) (LGPL-2.1-or-later), their branch of [Wine](https://www.winehq.org), as rebased by [dappermint](https://github.com/dappermint/winecx) and packaged with [winecx-gptk](https://github.com/dappermint/winecx-gptk).
- **Graphics:** Apple's [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) (Apple's license), [DXMT](https://github.com/3Shain/dxmt) by 3Shain and [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx.
- **Steam bridge:** `lsteamclient` and `steam.exe` come from Valve's [Proton](https://github.com/ValveSoftware/Proton).
- **Controllers and Game Mode:** [sn0wst0rm](https://github.com/sn0wst0rm) wrote the DualSense Bluetooth bridge, Steam rumble forwarding and game-mode host that Bridgeplay 0.7.51 and earlier shipped. They are paused until NotProton merges the same work ([NotProton#90](https://github.com/NotProtonNot/NotProton/pull/90)).
- **Libraries:** [Dobby](https://github.com/jmpews/Dobby) (Apache-2.0), [Sparkle](https://sparkle-project.org) (MIT), [SDL](https://www.libsdl.org) (zlib) and [cJSON](https://github.com/DaveGamble/cJSON) (MIT).
- **Bridgeplay:** [everyone who has contributed](https://github.com/raymondchins/Bridgeplay/graphs/contributors).

NotProton in turn thanks the people who came before it, among them Nat Brown's Kaon, mont127's Neutron and Gio's work on Steam Play in Mac Steam; see [docs/UPSTREAM.md](docs/UPSTREAM.md).

## Support Wine

Wine on the Mac exists largely because of [CodeWeavers](https://www.codeweavers.com), the biggest contributor to the Wine project. They fund that work by selling [CrossOver](https://www.codeweavers.com/crossover). Bridgeplay's free engine comes from the WineCX code CodeWeavers publishes, so every game it runs also stands on their work.

If you can, buy CrossOver.

## License

Bridgeplay is licensed under the [GPL-3.0](LICENSE). Third-party licenses, and the source for the patched Wine files the app ships (LGPL-2.1-or-later), are listed in [NOTICE](NOTICE).

<p>
  <a href="https://github.com/raymondchins"><img src="https://github.com/raymondchins.png?size=64" width="32" height="32" alt="" align="left" style="border-radius:50%"></a>
  &nbsp;Built by <a href="https://github.com/raymondchins"><b>Raymond Chin</b></a>, Jakarta.
</p>

<sub>Bridgeplay is built on NotProton and is not affiliated with or endorsed by Apple, Valve, Microsoft, NVIDIA, Sony, CodeWeavers or any game publisher. Steam is a trademark of Valve Corporation; Mac, macOS, Metal, MetalFX and Rosetta of Apple Inc.; Windows, DirectX and Xbox of Microsoft; CrossOver of CodeWeavers; DLSS and GeForce of NVIDIA; DualSense of Sony Interactive Entertainment. Game names, game art and other product names belong to their owners and are used only to identify them.</sub>
