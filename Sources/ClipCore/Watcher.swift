import AppKit
import Foundation

/// The clipboard, as the watcher sees it. `SystemClipboard` wraps an `NSPasteboard`; tests use
/// a private named pasteboard or a fake.
@MainActor
public protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    /// The types of each item on the clipboard.
    func itemTypes() -> [[String]]
    /// Data of the first item for a type.
    func data(forType type: String) -> Data?
    /// Replaces the clipboard with the JPEG and the marker. Returns the new change count.
    func writeJPEG(_ jpeg: Data) -> Int
}

@MainActor
public final class SystemClipboard: Clipboard {
    public let pasteboard: NSPasteboard

    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public var changeCount: Int { pasteboard.changeCount }

    public func itemTypes() -> [[String]] {
        (pasteboard.pasteboardItems ?? []).map { $0.types.map(\.rawValue) }
    }

    public func data(forType type: String) -> Data? {
        pasteboard.pasteboardItems?.first?.data(forType: NSPasteboard.PasteboardType(type))
    }

    public func writeJPEG(_ jpeg: Data) -> Int {
        let jpegType = NSPasteboard.PasteboardType(ClipType.jpeg)
        let markerType = NSPasteboard.PasteboardType(ClipType.marker)
        pasteboard.declareTypes([jpegType, markerType], owner: nil)
        pasteboard.setData(jpeg, forType: jpegType)
        pasteboard.setString("1", forType: markerType)
        return pasteboard.changeCount
    }
}

public struct WatcherConfig: Sendable {
    public var options: CompressOptions
    /// Images smaller than this are left alone.
    public var minBytes: Int
    /// Folder for a copy of each JPEG; nil saves nothing.
    public var saveDirectory: URL?

    public init(options: CompressOptions = CompressOptions(), minBytes: Int = 300 * 1024, saveDirectory: URL? = nil) {
        self.options = options
        self.minBytes = minBytes
        self.saveDirectory = saveDirectory
    }
}

/// What one look at the clipboard did.
public enum Outcome: Equatable, Sendable {
    /// Nothing new since the last look, or still busy with the previous image.
    case unchanged
    case skipped(SkipReason)
    /// The image could not be read, or would be too tall for JPEG.
    case failed
    /// The JPEG was not smaller than the original, so the clipboard was kept.
    case notSmaller(originalBytes: Int, jpegBytes: Int)
    /// The clipboard changed while compressing, so the result was dropped.
    case clipboardChanged
    case compressed(originalBytes: Int, jpegBytes: Int, width: Int, height: Int, savedTo: URL?)
}

@MainActor
public final class Watcher {
    public typealias CompressFunction = @Sendable (Data, CompressOptions) -> CompressedImage?

    private let clipboard: Clipboard
    private let config: WatcherConfig
    private let compress: CompressFunction
    private var lastChangeCount: Int
    private var busy = false

    /// Starts from the clipboard as it is now: what is already there is not touched.
    public init(clipboard: Clipboard, config: WatcherConfig = WatcherConfig(),
                compress: @escaping CompressFunction = Compressor.compress) {
        self.clipboard = clipboard
        self.config = config
        self.compress = compress
        self.lastChangeCount = clipboard.changeCount
    }

    /// Looks at the clipboard once. Compression runs off the main thread; the clipboard is read
    /// and written on the main thread only.
    public func tick() async -> Outcome {
        let start = clipboard.changeCount
        guard start != lastChangeCount, !busy else { return .unchanged }
        lastChangeCount = start
        busy = true
        defer { busy = false }

        let decision = ClipboardPolicy.decide(itemTypes: clipboard.itemTypes(), minBytes: config.minBytes) {
            self.clipboard.data(forType: $0)?.count
        }
        guard case .compress(let type) = decision else {
            if case .skip(let reason) = decision { return .skipped(reason) }
            return .unchanged
        }
        guard let data = clipboard.data(forType: type) else { return .skipped(.noImage) }

        let options = config.options
        let compress = self.compress
        let result = await Task.detached(priority: .userInitiated) {
            autoreleasepool { compress(data, options) }
        }.value

        guard let result else { return .failed }
        guard result.jpeg.count < data.count else {
            return .notSmaller(originalBytes: data.count, jpegBytes: result.jpeg.count)
        }
        // The user copied something else meanwhile: never overwrite it with the older image.
        // lastChangeCount stays at `start`, so the next look handles the new contents (which may be
        // another screenshot).
        guard clipboard.changeCount == start else { return .clipboardChanged }
        lastChangeCount = clipboard.writeJPEG(result.jpeg)

        var savedTo: URL? = nil
        if let dir = config.saveDirectory {
            savedTo = Self.save(result.jpeg, in: dir)
        }
        return .compressed(originalBytes: data.count, jpegBytes: result.jpeg.count,
                           width: result.width, height: result.height, savedTo: savedTo)
    }

    /// Writes `clipultra_<milliseconds>.jpg`, adding `-2`, `-3`... rather than overwriting a file.
    static func save(_ jpeg: Data, in dir: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        for n in 1...100 {
            let name = n == 1 ? "clipultra_\(stamp).jpg" : "clipultra_\(stamp)-\(n).jpg"
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { continue }
            do {
                try jpeg.write(to: url, options: .withoutOverwriting)
                return url
            } catch {
                continue
            }
        }
        return nil
    }
}
