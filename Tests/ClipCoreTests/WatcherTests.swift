import AppKit
import Foundation
import Testing
@testable import ClipCore

@Suite("Watcher", .serialized)
@MainActor
struct WatcherTests {
    let config = WatcherConfig(options: CompressOptions(maxWidth: 1000), minBytes: 10 * 1024)

    func screenshot(_ png: Data) -> [[String: Data]] {
        [["public.png": png, "Apple PNG pasteboard type": png]]
    }

    @Test("What is on the clipboard at start is not touched")
    func startsFromCurrentContents() async {
        let clip = FakeClipboard()
        clip.copy(screenshot(makePNG(width: 800, height: 600)))
        let w = Watcher(clipboard: clip, config: config)
        #expect(await w.tick() == .unchanged)
        #expect(clip.writes == 0)
    }

    @Test("A new screenshot is replaced by a smaller JPEG with the marker")
    func compressesScreenshot() async throws {
        let clip = FakeClipboard()
        let w = Watcher(clipboard: clip, config: config)
        let png = makePNG(width: 1600, height: 900)
        clip.copy(screenshot(png))
        guard case .compressed(let before, let after, let width, _, let saved) = await w.tick() else {
            Issue.record("not compressed"); return
        }
        #expect(before == png.count && after < before && width == 1000 && saved == nil)
        #expect(clip.itemTypes() == [[ClipType.marker, "public.jpeg"]])
        let jpeg = try #require(clip.data(forType: "public.jpeg"))
        #expect(imageInfo(jpeg)?.type == "public.jpeg")
        // Its own output is not looked at again.
        #expect(await w.tick() == .unchanged)
        #expect(clip.writes == 1)
    }

    @Test("Text copied with an image (spreadsheet cells) stays on the clipboard")
    func keepsMixedContent() async {
        let clip = FakeClipboard()
        let w = Watcher(clipboard: clip, config: config)
        let cells: [[String: Data]] = [["public.utf8-plain-text": Data("a\tb".utf8),
                                         "public.tiff": makePNG(width: 800, height: 600)]]
        clip.copy(cells)
        #expect(await w.tick() == .skipped(.otherContent("public.utf8-plain-text")))
        #expect(clip.writes == 0)
        #expect(clip.data(forType: "public.utf8-plain-text") == Data("a\tb".utf8))
    }

    @Test("A copy made while compressing wins: the older image is not written back")
    func clipboardChangedDuringCompression() async {
        let clip = FakeClipboard()
        let slow: Watcher.CompressFunction = { data, options in
            Thread.sleep(forTimeInterval: 0.3)
            return Compressor.compress(data, options: options)
        }
        let w = Watcher(clipboard: clip, config: config, compress: slow)
        clip.copy(screenshot(makePNG(width: 800, height: 600)))
        let running = Task { await w.tick() }
        try? await Task.sleep(for: .milliseconds(100))
        clip.copy([["public.utf8-plain-text": Data("copied later".utf8)]])
        #expect(await running.value == .clipboardChanged)
        #expect(clip.writes == 0)
        #expect(clip.data(forType: "public.utf8-plain-text") == Data("copied later".utf8))
        // The next look handles the text copied later: it is not an image, so it is left alone.
        #expect(await w.tick() == .skipped(.otherContent("public.utf8-plain-text")))
        #expect(await w.tick() == .unchanged)
    }

    @Test("While one image is compressing, further looks do nothing")
    func busy() async {
        let clip = FakeClipboard()
        let slow: Watcher.CompressFunction = { data, options in
            Thread.sleep(forTimeInterval: 0.3)
            return Compressor.compress(data, options: options)
        }
        let w = Watcher(clipboard: clip, config: config, compress: slow)
        clip.copy(screenshot(makePNG(width: 800, height: 600)))
        let running = Task { await w.tick() }
        try? await Task.sleep(for: .milliseconds(100))
        clip.copy(screenshot(makePNG(width: 700, height: 500, seed: 2)))
        #expect(await w.tick() == .unchanged)
        #expect(await running.value == .clipboardChanged)
        // The second screenshot is picked up at the next look.
        guard case .compressed = await w.tick() else { Issue.record("second screenshot not compressed"); return }
    }

    @Test("A JPEG that is not smaller leaves the clipboard as it is")
    func notSmaller() async {
        let clip = FakeClipboard()
        let bloated: Watcher.CompressFunction = { data, _ in
            CompressedImage(jpeg: data + Data(count: 10), width: 1, height: 1)
        }
        let w = Watcher(clipboard: clip, config: config, compress: bloated)
        let png = makePNG(width: 800, height: 600)
        clip.copy(screenshot(png))
        #expect(await w.tick() == .notSmaller(originalBytes: png.count, jpegBytes: png.count + 10))
        #expect(clip.writes == 0)
    }

    @Test("An image that cannot be read leaves the clipboard as it is")
    func unreadable() async {
        let clip = FakeClipboard()
        let w = Watcher(clipboard: clip, config: config)
        clip.copy([["public.png": Data(repeating: 7, count: 20 * 1024)]])
        #expect(await w.tick() == .failed)
        #expect(clip.writes == 0)
    }

    @Test("With a save folder, each JPEG is saved under its own name")
    func savesCopies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipultra-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var cfg = config
        cfg.saveDirectory = dir
        let clip = FakeClipboard()
        let w = Watcher(clipboard: clip, config: cfg)
        var saved: [URL] = []
        for seed in 1...3 {
            clip.copy(screenshot(makePNG(width: 600, height: 400, seed: UInt64(seed))))
            guard case .compressed(_, _, _, _, let url?) = await w.tick() else { Issue.record("not saved"); return }
            saved.append(url)
        }
        #expect(Set(saved).count == 3)
        for url in saved {
            #expect(imageInfo(try Data(contentsOf: url))?.type == "public.jpeg")
        }
    }

    @Test("Saving never overwrites an existing file")
    func saveDoesNotOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipultra-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try #require(Watcher.save(Data("a".utf8), in: dir))
        let b = try #require(Watcher.save(Data("b".utf8), in: dir))
        #expect(a != b)
        #expect(try Data(contentsOf: a) == Data("a".utf8))
    }
}

/// The real NSPasteboard code, on a private pasteboard: the user's clipboard is never used.
@Suite("System clipboard", .serialized)
@MainActor
struct SystemClipboardTests {
    func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("clipultra-test-\(UUID().uuidString)"))
    }

    @Test("A screenshot on a real pasteboard becomes a JPEG with the marker")
    func compressesOnRealPasteboard() async throws {
        let pb = privatePasteboard()
        defer { pb.releaseGlobally() }
        let w = Watcher(clipboard: SystemClipboard(pb),
                        config: WatcherConfig(options: CompressOptions(maxWidth: 1000), minBytes: 10 * 1024))
        pb.clearContents()
        pb.setData(makePNG(width: 1400, height: 900), forType: .png)
        guard case .compressed = await w.tick() else { Issue.record("not compressed"); return }
        let types = Set(pb.types?.map(\.rawValue) ?? [])
        #expect(types.contains("public.jpeg") && types.contains(ClipType.marker))
        #expect(!types.contains("public.png"))
        let jpeg = try #require(pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")))
        #expect(imageInfo(jpeg)?.width == 1000)
        #expect(await w.tick() == .unchanged)
    }

    @Test("Text and an image on a real pasteboard are left as they are")
    func leavesMixedContent() async {
        let pb = privatePasteboard()
        defer { pb.releaseGlobally() }
        let w = Watcher(clipboard: SystemClipboard(pb),
                        config: WatcherConfig(minBytes: 10 * 1024))
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("Q3 total\t42", forType: .string)
        item.setData(makePNG(width: 800, height: 600), forType: .tiff)
        pb.writeObjects([item])
        guard case .skipped(.otherContent) = await w.tick() else { Issue.record("mixed content was touched"); return }
        #expect(pb.string(forType: .string) == "Q3 total\t42")
    }
}
