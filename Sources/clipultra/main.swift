import AppKit
import ClipCore
import Foundation

let version = "1.0.1"

let usage = """
clipultra \(version): compresses screenshots on the macOS clipboard to JPEG.

Copy a screenshot (Cmd-Ctrl-Shift-4) and clipultra replaces the PNG with a much smaller JPEG.
It acts only when the clipboard holds nothing but one image: cells copied from a spreadsheet,
a picture copied from a web page or a file copied in Finder are left alone.

USAGE: clipultra [options]

OPTIONS:
  --quality <0.1-1.0>   JPEG quality (default 0.85; large images use at most 0.85 or 0.78)
  --max-width <pixels>  Scale wider images down to this width; 0 keeps full size (default 2560)
  --min-kb <KB>         Leave images smaller than this alone (default 300)
  --save-dir <folder>   Also save each JPEG in this folder (default: save nothing)
  --interval <seconds>  How often to look at the clipboard (default \(WatcherConfig.defaultInterval))
  --verbose             Also log clipboard changes that were left alone, and why
  --version             Print the version
  --help                Print this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("clipultra: \(message)\nRun clipultra --help for usage.\n".utf8))
    exit(2)
}

var config = WatcherConfig()
var interval = WatcherConfig.defaultInterval
var verbose = false

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func value(_ flag: String) -> String {
    guard !args.isEmpty else { fail("\(flag) needs a value") }
    return args.removeFirst()
}
while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--quality":
        guard let q = Double(value(flag)), q >= 0.1, q <= 1 else { fail("--quality must be between 0.1 and 1.0") }
        config.options.quality = q
    case "--max-width":
        guard let w = Int(value(flag)), w >= 0 else { fail("--max-width must be a whole number of pixels") }
        config.options.maxWidth = w == 0 ? nil : w
    case "--min-kb":
        guard let kb = Int(value(flag)), kb >= 0 else { fail("--min-kb must be a whole number") }
        config.minBytes = kb * 1024
    case "--save-dir":
        config.saveDirectory = URL(fileURLWithPath: (value(flag) as NSString).expandingTildeInPath, isDirectory: true)
    case "--interval":
        guard let s = Double(value(flag)), s >= 0.01, s <= 10 else { fail("--interval must be between 0.01 and 10 seconds") }
        interval = s
    case "--verbose": verbose = true
    case "--version": print("clipultra \(version)"); exit(0)
    case "--help", "-h": print(usage); exit(0)
    default: fail("unknown option \(flag)")
    }
}

// Line-buffered output, so a log file shows every line at once (launchd redirects stdout).
setlinebuf(stdout)

let dateFormatter = ISO8601DateFormatter()
let bytes: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .binary; return f }()
@MainActor func log(_ s: String) { print("[\(dateFormatter.string(from: Date()))] \(s)") }

@MainActor func report(_ outcome: Outcome) {
    switch outcome {
    case .unchanged: break
    case .compressed(let before, let after, let w, let h, let saved):
        let pct = (1 - Double(after) / Double(before)) * 100
        log("Compressed \(w)x\(h): \(bytes.string(fromByteCount: Int64(before))) -> "
            + "\(bytes.string(fromByteCount: Int64(after))) (saved \(String(format: "%.1f", pct))%)"
            + (saved.map { ", saved as \($0.path)" } ?? ""))
    case .clipboardChanged: log("Clipboard changed while compressing: kept the new contents")
    case .failed: log("Could not compress the image: kept the original")
    case .notSmaller(let before, let after):
        if verbose { log("JPEG (\(after) bytes) not smaller than the original (\(before) bytes): kept the original") }
    case .skipped(let reason):
        if verbose { log("Left alone: \(reason)") }
    }
}

let watcher = Watcher(clipboard: SystemClipboard(), config: config)
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: interval)
timer.setEventHandler {
    Task { @MainActor in report(await watcher.tick()) }
}
timer.resume()
let width = config.options.maxWidth.map { "\($0) px" } ?? "full size"
log("clipultra \(version) watching the clipboard every \(interval) s (quality \(config.options.quality), max width \(width), "
    + "min \(config.minBytes / 1024) KB, save \(config.saveDirectory?.path ?? "off"))")

dispatchMain()
