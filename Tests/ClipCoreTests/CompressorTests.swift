import Foundation
import Testing
@testable import ClipCore

@Suite("Compression")
struct CompressorTests {
    @Test("Only the width is limited; the aspect ratio is kept")
    func targetSize() {
        #expect(Compressor.targetSize(width: 3456, height: 2234, maxWidth: 2560) == (2560, 1655))
        // A tall full-page capture keeps readable text: 2560 wide, not squeezed to its longest side.
        #expect(Compressor.targetSize(width: 3456, height: 27260, maxWidth: 2560) == (2560, 20193))
        #expect(Compressor.targetSize(width: 1385, height: 631, maxWidth: 2560) == (1385, 631))
        #expect(Compressor.targetSize(width: 5000, height: 100, maxWidth: nil) == (5000, 100))
        #expect(Compressor.targetSize(width: 5000, height: 1, maxWidth: 2560) == (2560, 1))
    }

    @Test("Quality is lowered for large images, never raised")
    func qualityTiers() {
        #expect(Compressor.quality(forBytes: 1_000_000, base: 0.85) == 0.85)
        #expect(Compressor.quality(forBytes: 4_000_000, base: 0.95) == 0.85)
        #expect(Compressor.quality(forBytes: 9_000_000, base: 0.85) == 0.78)
        #expect(Compressor.quality(forBytes: 9_000_000, base: 0.6) == 0.6)
    }

    @Test("A small image keeps its size and becomes a smaller JPEG")
    func keepsSize() throws {
        let png = makePNG(width: 800, height: 500)
        let out = try #require(Compressor.compress(png, options: CompressOptions()))
        let info = try #require(imageInfo(out.jpeg))
        #expect(info.type == "public.jpeg")
        #expect((info.width, info.height) == (800, 500))
        #expect((out.width, out.height) == (800, 500))
        #expect(out.jpeg.count < png.count)
    }

    @Test("A wide image is scaled to the maximum width")
    func scalesWidth() throws {
        let png = makePNG(width: 3000, height: 1000)
        let out = try #require(Compressor.compress(png, options: CompressOptions(maxWidth: 1500)))
        let info = try #require(imageInfo(out.jpeg))
        #expect(info.width == 1500)
        #expect(abs(info.height - 500) <= 1)
    }

    @Test("A tall image is limited by its width, not its height")
    func tallImage() throws {
        let png = makePNG(width: 600, height: 4000)
        let out = try #require(Compressor.compress(png, options: CompressOptions(maxWidth: 300)))
        let info = try #require(imageInfo(out.jpeg))
        #expect(info.width == 300)
        #expect(abs(info.height - 2000) <= 1)
    }

    @Test("maxWidth nil keeps the full size")
    func noLimit() throws {
        let png = makePNG(width: 3000, height: 200)
        let out = try #require(Compressor.compress(png, options: CompressOptions(maxWidth: nil)))
        #expect(imageInfo(out.jpeg)?.width == 3000)
    }

    @Test("Transparent areas become white, with and without scaling", arguments: [nil, 400] as [Int?])
    func transparencyOnWhite(maxWidth: Int?) throws {
        let png = makePNG(width: 600, height: 400, transparentBorder: 60)
        let out = try #require(Compressor.compress(png, options: CompressOptions(maxWidth: maxWidth)))
        let corner = pixel(out.jpeg, x: 2, y: 2)
        #expect(corner.r > 245 && corner.g > 245 && corner.b > 245, "corner is \(corner), not white")
        let middle = pixel(out.jpeg, x: out.width / 2, y: out.height / 2)
        #expect(middle.b > 100 && middle.b < 160, "the image itself is kept, middle is \(middle)")
    }

    @Test("Data that is not an image gives nil")
    func notAnImage() {
        #expect(Compressor.compress(Data("hello".utf8), options: CompressOptions()) == nil)
        #expect(Compressor.compress(Data(), options: CompressOptions()) == nil)
    }

    @Test("An image too tall for JPEG gives nil instead of a broken file")
    func tooTallForJPEG() {
        let png = makePNG(width: 2, height: 66_000)
        #expect(Compressor.compress(png, options: CompressOptions(maxWidth: nil)) == nil)
    }
}
