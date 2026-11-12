import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ClipCore

/// A PNG of the given size: a colour gradient with noise, which a PNG stores poorly and a JPEG
/// well, like a photo or a busy screenshot. `transparentBorder` leaves that many pixels on each
/// side fully transparent, like the shadow area of a window capture.
func makePNG(width: Int, height: Int, transparentBorder: Int = 0, seed: UInt64 = 1) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var rng = seed
    for y in 0..<height {
        for x in 0..<width {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let noise = Int((rng >> 59) & 15)
            let i = (y * width + x) * 4
            let inside = x >= transparentBorder && x < width - transparentBorder
                && y >= transparentBorder && y < height - transparentBorder
            if inside {
                px[i] = UInt8(clamping: x * 255 / max(1, width) + noise)
                px[i + 1] = UInt8(clamping: y * 255 / max(1, height) + noise)
                px[i + 2] = UInt8(clamping: 128 + noise)
                px[i + 3] = 255
            } else {
                px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
            }
        }
    }
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
    return out as Data
}

/// Pixel size and type of encoded image data.
func imageInfo(_ data: Data) -> (width: Int, height: Int, type: String)? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
          let type = CGImageSourceGetType(src) as String?
    else { return nil }
    return (w, h, type)
}

/// RGB of the pixel at (x, y), counted from the top left.
func pixel(_ data: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let src = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (Int(p[0]), Int(p[1]), Int(p[2]))
}

/// An in-memory clipboard for the watcher tests.
@MainActor
final class FakeClipboard: Clipboard {
    private(set) var changeCount = 0
    private(set) var items: [[String: Data]] = []
    private(set) var writes = 0

    /// Replaces the contents, as a copy in another app does.
    func copy(_ items: [[String: Data]]) {
        self.items = items
        changeCount += 1
    }

    func itemTypes() -> [[String]] { items.map { Array($0.keys).sorted() } }

    func data(forType type: String) -> Data? { items.first?[type] }

    func writeJPEG(_ jpeg: Data) -> Int {
        writes += 1
        copy([[ClipType.jpeg: jpeg, ClipType.marker: Data("1".utf8)]])
        return changeCount
    }
}
