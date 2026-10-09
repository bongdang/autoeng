import AppKit

@MainActor
enum StatusIcon {
    static func make(size: NSSize = NSSize(width: 30, height: 22)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            let scale = bounds.height / 22
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9 * scale, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            ("Auto" as NSString).draw(in: NSRect(x: 0, y: 11 * scale,
                                               width: bounds.width, height: 11 * scale), withAttributes: attributes)
            ("Eng" as NSString).draw(in: NSRect(x: 0, y: 0,
                                              width: bounds.width, height: 11 * scale), withAttributes: attributes)
            return true
        }
        // macOS tints template images for light/dark menu bars and selection.
        image.isTemplate = true
        return image
    }

    static func exportPreview(to url: URL) throws {
        let size = NSSize(width: 300, height: 220)
        let icon = make(size: size)
        icon.isTemplate = false
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            icon.draw(in: bounds)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
