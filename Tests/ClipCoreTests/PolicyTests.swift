import Testing
@testable import ClipCore

@Suite("Which clipboards are compressed")
struct PolicyTests {
    let big = 500 * 1024
    let min = 300 * 1024

    func decide(_ items: [[String]], size: Int? = nil) -> Decision {
        ClipboardPolicy.decide(itemTypes: items, minBytes: min) { _ in size ?? big }
    }

    @Test("A screenshot (PNG and TIFF, with AppKit's older names) is compressed from its PNG")
    func screenshot() {
        let types = ["public.png", "Apple PNG pasteboard type", "public.tiff", "NeXT TIFF v4.0 pasteboard type"]
        #expect(decide([types]) == .compress(type: "public.png"))
    }

    @Test("A TIFF-only image is compressed from its TIFF")
    func tiffOnly() {
        #expect(decide([["public.tiff"]]) == .compress(type: "public.tiff"))
    }

    @Test("Spreadsheet cells (text and an image of them) are left alone")
    func spreadsheetCells() {
        let types = ["public.utf8-plain-text", "public.html", "public.tiff", "com.adobe.pdf"]
        guard case .skip(.otherContent) = decide([types]) else { Issue.record("cells were not left alone"); return }
    }

    @Test("A picture copied from a web page (with HTML and URL) is left alone")
    func browserImage() {
        guard case .skip(.otherContent) = decide([["public.png", "public.html", "public.url"]]) else {
            Issue.record("browser image was not left alone"); return
        }
    }

    @Test("A file copied in Finder (file URL and icon) is left alone")
    func finderFile() {
        guard case .skip(.otherContent) = decide([["public.file-url", "com.apple.icns", "public.tiff"]]) else {
            Issue.record("Finder file was not left alone"); return
        }
    }

    @Test("A type unknown to the system (dynamic UTI) means the clipboard is left alone")
    func unknownType() {
        guard case .skip(.otherContent("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu")) =
            decide([["public.png", "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu"]]) else {
            Issue.record("unknown type was not left alone"); return
        }
    }

    @Test("Several items (several images or files) are left alone")
    func multipleItems() {
        #expect(decide([["public.png"], ["public.png"]]) == .skip(.multipleItems(2)))
    }

    @Test("clipultra's own output is never compressed again")
    func ownOutput() {
        #expect(decide([["public.jpeg", ClipType.marker]]) == .skip(.ownOutput))
    }

    @Test("A JPEG is left alone")
    func alreadyJPEG() {
        #expect(decide([["public.jpeg"]]) == .skip(.alreadyJPEG))
        #expect(decide([["public.png", "public.jpeg"]]) == .skip(.alreadyJPEG))
    }

    @Test("Images below the minimum size are left alone")
    func tooSmall() {
        #expect(decide([["public.png"]], size: 1000) == .skip(.tooSmall(1000)))
        #expect(decide([["public.png"]], size: min) == .compress(type: "public.png"))
    }

    @Test("An empty clipboard is left alone")
    func empty() {
        #expect(decide([]) == .skip(.empty))
        #expect(decide([[]]) == .skip(.empty))
    }

    @Test("Image types other than PNG and TIFF alone are not compressed")
    func otherImageOnly() {
        #expect(decide([["com.compuserve.gif"]]) == .skip(.noImage))
    }
}
