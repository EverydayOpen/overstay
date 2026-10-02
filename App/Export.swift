import AppKit
import OverstayCore
import SwiftUI
import UniformTypeIdentifiers

/// The only code in App/ that writes a file, and only where the user picks in the save panel (BUILD_PLAN §3.1 check 4).
/// The DEBUG demo's `--demo-share-out` also goes through `writePNG`.
@MainActor enum Export {
    /// The share card at 2x: 1200x630 px, drawn by the same view as the on-screen preview. VERIFY the size on macOS 13.
    /// `weights` is `AppModel.shareWeights(card)`: with it the bar's slabs are true proportions, without it they go by rank.
    private static func render(_ card: ShareCard, _ weights: [UInt64]?) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: ShareCardView(card: card, weights: weights))
        renderer.scale = 2
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    static func pngData(_ card: ShareCard, weights: [UInt64]? = nil) -> Data? {
        render(card, weights)?.representation(using: .png, properties: [:])
    }

    /// Puts the card on the pasteboard as an image (PNG and TIFF, so every paste target finds one). If rendering fails
    /// the text version is copied instead and this returns false.
    @discardableResult static func copyImage(_ card: ShareCard, weights: [UInt64]? = nil) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard let rep = render(card, weights), let png = rep.representation(using: .png, properties: [:]) else {
            copyToPasteboard(ShareCardText.plainText(card, footer: ShareCardView.address))
            NSSound.beep()
            return false
        }
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(rep.tiffRepresentation, forType: .tiff)
        return true
    }

    /// Asks where to save (a standalone panel, so it also works from the menu bar popover) and writes the PNG there.
    static func savePNG(_ card: ShareCard, weights: [UInt64]? = nil) {
        guard let data = pngData(card, weights: weights) else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Overstay.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// For the DEBUG demo (`--demo-share-out <png path>`): no panel; false if it could not render or write.
    static func writePNG(_ card: ShareCard, to url: URL, weights: [UInt64]? = nil) -> Bool {
        guard let data = pngData(card, weights: weights) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// Plain text to the pasteboard (Copy Diagnostics, the share card's text fallback). Here rather than in the design system
/// because the pasteboard is allowed only in AppModel.swift and Export.swift (safety_greps.sh check 8b).
@MainActor func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
