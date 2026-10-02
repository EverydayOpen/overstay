import AppKit
import SwiftUI

/// The menu bar item's images (docs/DESIGN.md §6.4), drawn once by `ImageRenderer` and cached. Plain shapes, not Canvas,
/// so the renderer cannot get it wrong. Nothing here animates (docs/MOTION.md §3.6).
@MainActor enum MenuBarIcon {
    /// VERIFY on macOS 13, 15 and 26 (BUILD_PLAN §12): does `MenuBarExtra` keep a non-template image's colour? If it
    /// flattens the badge to one tint, set this to false and `MenuBarLabel` draws the template glyph with the count as text.
    static let colorBadge = true

    /// The weight bar in miniature: three stacked rounded bars, left-aligned. Template, so the menu bar tints it.
    static let glyph: NSImage = render(count: nil)

    /// The same mark inside an amber pill with the count (near-black on amber, readable on a light or a dark menu bar).
    /// Not a template. Cached per count; the count is capped at 999 ("999+").
    static func badge(count: Int) -> NSImage {
        let key = min(max(count, 0), 1000)
        if let cached = cache[key] { return cached }
        let image = render(count: key)
        cache[key] = image
        return image
    }

    private static var cache: [Int: NSImage] = [:]

    private static func render(count: Int?) -> NSImage {
        let renderer = ImageRenderer(content: Mark(count: count))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = count == nil
        return image
    }

    private struct Mark: View {
        let count: Int?

        var body: some View {
            if let count {
                HStack(spacing: 4) {
                    bars(widths: [10, 7, 4.5], height: 2, gap: 1.5, color: Brand.onAmber)
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Brand.onAmber)
                }
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Capsule().fill(Brand.amber))
                .padding(1)
            } else {
                bars(widths: [14, 10, 6.5], height: 3, gap: 1.5, color: .black)
                    .frame(width: 16, height: 16)
            }
        }

        private func bars(widths: [CGFloat], height: CGFloat, gap: CGFloat, color: Color) -> some View {
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<widths.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(color).frame(width: widths[i], height: height)
                }
            }
        }
    }
}
