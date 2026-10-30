// A small window over the game with the frame rate wined3d writes to its Wine log, see
// WineFPS. It belongs to Bridgeplay, not to the game's process, so nothing is added to the
// game itself. It closes once the game's prefix has nothing running.

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FPSReading {
    var fps: Double?
    // No frame for a while after the first: the game is loading or hangs.
    var stalled = false
}

@MainActor
final class FPSWindow {
    static let shared = FPSWindow()

    private var panels: [String: NSPanel] = [:]
    private var watchers: [String: Task<Void, Never>] = [:]

    func show(for game: StandaloneGame, root: URL = SupportPaths.games) {
        close(game.id)
        let reading = FPSReading()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 30),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the game's own windows, a full-screen one included, and on every Space.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: FPSView(reading: reading, game: game.name))
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.minX + 12, y: screen.maxY - 12))
        }
        panel.orderFrontRegardless()
        panels[game.id] = panel

        let prefix = GameStore.prefix(of: game, in: root)
        let log = PrefixLog.wine.url(for: prefix)
        let id = game.id
        watchers[id] = Task { [weak self] in
            var reader = WineFPS.Reader(url: log)
            let started = Date.now
            var lastFrame: Date?
            var seenRunning = false
            var tick = 0
            while !Task.isCancelled {
                let (readings, next) = await Task.detached { [reader] in
                    var copy = reader
                    return (copy.read(), copy)
                }.value
                reader = next
                if let latest = readings.last {
                    reading.fps = latest
                    lastFrame = .now
                }
                reading.stalled = lastFrame.map { Date.now.timeIntervalSince($0) > 2.5 } ?? false
                // lsof is slower than reading the log, so the session is checked less often.
                if tick % 5 == 0 {
                    let running = await Task.detached { PrefixStore.isInUse(prefix) }.value
                    if running {
                        seenRunning = true
                    } else if seenRunning || Date.now.timeIntervalSince(started) > 120 {
                        break
                    }
                }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
            self?.close(id)
        }
    }

    func close(_ id: String) {
        watchers.removeValue(forKey: id)?.cancel()
        panels.removeValue(forKey: id)?.close()
    }
}

private struct FPSView: View {
    let reading: FPSReading
    let game: String

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "FPS")
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .foregroundStyle(reading.stalled ? .orange : .primary)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help(String(localized: "Frame rate of \(game), from Wine's own Direct3D (wined3d). Drag to move."))
    }

    private var value: String {
        if reading.stalled { return "0" }
        guard let fps = reading.fps else { return "–" }
        return String(format: "%.0f", fps)
    }
}
