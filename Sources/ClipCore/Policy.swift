import Foundation
import UniformTypeIdentifiers

/// Pasteboard type names clipultra cares about.
public enum ClipType {
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let jpeg = "public.jpeg"
    /// Written next to clipultra's own JPEG, so it never compresses its own output.
    public static let marker = "io.github.jkmungara.clipultra.optimized"

    /// Older names AppKit adds next to the modern ones. They carry the same image.
    static let legacyImageNames: Set<String> = [
        "Apple PNG pasteboard type",
        "NeXT TIFF v4.0 pasteboard type",
        "NSTIFFPboardType",
        "NSPNGPboardType",
    ]
}

/// Why clipultra leaves the clipboard alone.
public enum SkipReason: Equatable, Sendable, CustomStringConvertible {
    case empty
    case ownOutput
    case multipleItems(Int)
    case otherContent(String)
    case alreadyJPEG
    case noImage
    case tooSmall(Int)

    public var description: String {
        switch self {
        case .empty: return "clipboard is empty"
        case .ownOutput: return "clipultra's own output"
        case .multipleItems(let n): return "\(n) items on the clipboard (only a single image is compressed)"
        case .otherContent(let t): return "clipboard also holds \(t), so it is not a plain image"
        case .alreadyJPEG: return "already a JPEG"
        case .noImage: return "no PNG or TIFF image"
        case .tooSmall(let n): return "image is only \(n / 1024) KB"
        }
    }
}

public enum Decision: Equatable, Sendable {
    /// Compress the data of this pasteboard type.
    case compress(type: String)
    case skip(SkipReason)
}

/// Decides whether the clipboard holds nothing but one image, such as a screenshot.
///
/// The rule is an allow-list: every type on the clipboard must be an image type. Copying cells
/// in Excel or Numbers, a picture in a browser, or a file in Finder also puts an image on the
/// clipboard, next to text, HTML or a file URL. Replacing such a clipboard with a JPEG would
/// lose what the user copied, so any other type means "leave it alone".
public enum ClipboardPolicy {
    public static func decide(itemTypes: [[String]], minBytes: Int, size: (String) -> Int?) -> Decision {
        guard let types = itemTypes.first, !types.isEmpty else { return .skip(.empty) }
        if itemTypes.count > 1 { return .skip(.multipleItems(itemTypes.count)) }
        if types.contains(ClipType.marker) { return .skip(.ownOutput) }
        if let other = types.first(where: { !isImageType($0) }) { return .skip(.otherContent(other)) }
        if types.contains(ClipType.jpeg) { return .skip(.alreadyJPEG) }
        // PNG first: it is what screenshots put on the clipboard and the honest size to beat.
        guard let type = [ClipType.png, ClipType.tiff].first(where: types.contains) else { return .skip(.noImage) }
        let bytes = size(type) ?? 0
        if bytes < minBytes { return .skip(.tooSmall(bytes)) }
        return .compress(type: type)
    }

    static func isImageType(_ t: String) -> Bool {
        if ClipType.legacyImageNames.contains(t) { return true }
        guard let ut = UTType(t), !ut.isDynamic else { return false }
        return ut.conforms(to: .image)
    }
}
