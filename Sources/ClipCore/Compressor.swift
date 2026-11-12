import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CompressOptions: Sendable, Equatable {
    /// JPEG quality for images up to 3 MB. Larger images use `min(quality, 0.85)` and, above
    /// 8 MB, `min(quality, 0.78)`.
    public var quality: Double
    /// Images wider than this are scaled down to this width; nil keeps the full size. Only the
    /// width is limited, so a tall full-page capture keeps readable text.
    public var maxWidth: Int?

    public init(quality: Double = 0.85, maxWidth: Int? = 2560) {
        self.quality = quality
        self.maxWidth = maxWidth
    }
}

public struct CompressedImage: Sendable, Equatable {
    public let jpeg: Data
    public let width: Int
    public let height: Int
}

public enum Compressor {
    /// JPEG cannot store more than 65,535 pixels on a side.
    public static let maxJPEGSide = 65_500

    public static func quality(forBytes bytes: Int, base: Double) -> Double {
        if bytes > 8_000_000 { return min(base, 0.78) }
        if bytes > 3_000_000 { return min(base, 0.85) }
        return base
    }

    /// Output size: the width capped at `maxWidth`, the aspect ratio kept.
    public static func targetSize(width: Int, height: Int, maxWidth: Int?) -> (width: Int, height: Int) {
        guard let maxWidth, maxWidth > 0, width > maxWidth else { return (width, height) }
        let scale = Double(maxWidth) / Double(width)
        return (maxWidth, max(1, Int((Double(height) * scale).rounded())))
    }

    /// The image as a JPEG, transparent areas on white. Nil when the data is not an image, or
    /// the result would be too tall for JPEG.
    public static func compress(_ data: Data, options: CompressOptions) -> CompressedImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0
        else { return nil }

        let target = targetSize(width: w, height: h, maxWidth: options.maxWidth)
        guard target.width <= maxJPEGSide, target.height <= maxJPEGSide else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality(forBytes: data.count, base: options.quality),
            kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]

        var final = (width: w, height: h)
        if target.width < w {
            // ImageIO's thumbnail limits the longest side: give it the longest side of the target.
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else { return nil }
            CGImageDestinationAddImage(dest, thumb, destOptions as CFDictionary)
            final = (thumb.width, thumb.height)
        } else {
            CGImageDestinationAddImageFromSource(dest, src, 0, destOptions as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return CompressedImage(jpeg: out as Data, width: final.width, height: final.height)
    }
}
