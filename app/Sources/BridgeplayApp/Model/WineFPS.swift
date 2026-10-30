// wined3d's own frame counter. With Wine's fps trace channel on, a game wined3d or Wine's
// OpenGL draws writes lines like
//   014c:trace:fps:wined3d_cs_exec_present 014AF908 @ approx 117.80fps
// to its Wine log about once a second. The FPS window reads them from outside the game.

import Foundation

enum WineFPS {

    static let channel = "trace+fps"
    // What the run script exports when nothing sets WINEDEBUG; keep in step with compat_run.sh.
    static let runScriptDefault = "err+all,fixme-all"

    // WINEDEBUG for a launch: what the game would get anyway, with the fps channel added. A
    // value that already names the fps channel, on or off, is left as it is.
    static func debug(_ current: String?) -> String {
        let base = current.flatMap { $0.isEmpty ? nil : $0 } ?? runScriptDefault
        let names = base.split(separator: ",").map { $0.split(separator: "+").last ?? $0 }
            .map { $0.split(separator: "-").last ?? $0 }
        return names.contains("fps") ? base : base + "," + channel
    }

    // The WINEDEBUG the game's confs set, as the run script reads them: the global conf, then
    // the game's own, the last line winning.
    static func confDebug(for id: String, gamefixes: URL = SupportPaths.gamefixes) -> String? {
        var found: String?
        for file in [gamefixes.appending(path: "default.conf"), gamefixes.appending(path: "\(id).conf")] {
            let text = GameSettings.text(at: file)
            for line in text.split(separator: "\n") {
                if let (key, value) = GameDefaults.assignment(line), key == "WINEDEBUG" { found = value }
            }
        }
        return found
    }

    // Every reading in a stretch of the log, oldest first.
    static func readings(in text: String) -> [Double] {
        text.split(separator: "\n").compactMap { line in
            guard line.contains(":trace:fps:"),
                  let match = line.firstMatch(of: /@ approx ([0-9]+(?:\.[0-9]+)?)fps/)
            else { return nil }
            return Double(match.1)
        }
    }

    // Follows a Wine log as it grows. The run script starts each launch's log afresh, so a
    // file shorter than what was read is read again from its start.
    struct Reader: Sendable {
        let url: URL
        private(set) var offset: UInt64
        private var partial = ""

        // Starts at the end of what the file holds now, so an earlier launch's readings are skipped.
        init(url: URL) {
            self.url = url
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size])
                as? UInt64
            offset = size ?? 0
        }

        mutating func read() -> [Double] {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { return [] }
            if size < offset {
                offset = 0
                partial = ""
            }
            guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: Int(min(size - offset, 1 << 20)))
            else { return [] }
            offset += UInt64(data.count)
            var text = partial + String(decoding: data, as: UTF8.self)
            // Keep a line the writer has not finished for the next read.
            if let last = text.lastIndex(of: "\n") {
                partial = String(text[text.index(after: last)...])
                text = String(text[...last])
            } else {
                partial = text
                return []
            }
            return WineFPS.readings(in: text)
        }
    }
}
