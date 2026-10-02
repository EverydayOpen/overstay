import AppKit
import OverstayCore
import SwiftUI

/// "Copy my number": the 1200x630 card as a 600x315pt view. The on-screen preview and the exported PNG are this same
/// view (`Export` renders it at 2x). An object, not a screen: the night room in every scheme, front-facing and flat, pure
/// fills only (no material, blur, shadow or AppKit control), so every shared PNG looks the same (docs/DESIGN.md §6.6).
/// Content comes only from `ShareCard`, which holds no paths and no project names unless the user opted in.
struct ShareCardView: View {
    static let size = CGSize(width: 600, height: 315)
    /// The site address without the scheme, e.g. "everydayopen.github.io/overstay" (Core has no URL).
    static let address = Links.website.absoluteString.replacingOccurrences(of: "https://", with: "")

    let card: ShareCard
    /// On-screen width. The art is always drawn at 600pt and scaled, so the PNG never depends on this.
    var width = ShareCardView.size.width

    private static let night = [Color(red: 0.059, green: 0.051, blue: 0.043), Color(red: 0.086, green: 0.075, blue: 0.059)]   // #0F0D0B, #16130F
    private static let cream = Color(red: 0.965, green: 0.941, blue: 0.902)                                                  // #F6F0E6
    private static let sand = Color(red: 0.655, green: 0.608, blue: 0.541)                                                  // #A79B8A, 6.8:1 on the night

    var body: some View {
        let scale = width / Self.size.width
        art
            .frame(width: Self.size.width, height: Self.size.height)
            .clipped()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: Self.size.height * scale, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Share card. \(ShareCardText.headline(card)) \(ShareCardText.subline(card))" + (card.isSample ? " \(ShareCardText.sampleWatermark)." : ""))
    }

    private var art: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: Self.night, startPoint: .top, endPoint: .bottom)
            // The door light: one tall warm pool at the leading edge, a plain fill.
            EllipticalGradient(colors: [Brand.amber.opacity(0.22), .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: 360, height: 420)
                .offset(x: -180, y: -52)
            VStack(alignment: .leading, spacing: 10) {
                headline
                Text(ShareCardText.subline(card))
                    .font(.system(size: 18))
                    .foregroundStyle(Self.sand)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    slabs
                    Spacer(minLength: 16)
                    signature
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 52)
            .padding(.bottom, 32)
            if card.isSample {
                Text(ShareCardText.sampleWatermark)
                    .font(.system(size: 14, weight: .semibold).smallCaps())   // VERIFY: Font.smallCaps() with the system font
                    .tracking(0.6)
                    .foregroundStyle(Brand.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Brand.amber.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Brand.amber.opacity(0.5), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(20)
            }
        }
    }

    /// Core's words, with the number (the size in GB) in amber.
    private var headline: some View {
        let line = ShareCardText.headline(card)
        let number = Format.bytes(card.bytes)
        var out = AttributedString()
        func add(_ s: String, _ color: Color) {
            var part = AttributedString(s)
            part.foregroundColor = color
            out += part
        }
        if card.processCount > 0, let r = line.range(of: number) {
            add(String(line[..<r.lowerBound]), Self.cream)
            add(number, Brand.amber)
            add(String(line[r.upperBound...]), Self.cream)
        } else {
            add(line, Self.cream)
        }
        return Text(out)
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .tracking(-0.8)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static let slabWidths: [CGFloat] = [150, 90, 52]

    /// One slab per top agent, largest first. ShareCard carries ranks, not per-agent bytes, so the widths are a fixed
    /// 1 : 0.6 : 0.35 by rank (ponytail: add per-agent bytes to ShareCard if true proportions are wanted). After a stop
    /// the slabs lie settled and dim, echoing the collapse.
    private var slabs: some View {
        let settled = card.kind == .stopped
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<min(3, card.topAgents.count), id: \.self) { i in
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape.fill(Brand.amber.opacity(settled ? 0.35 : 1 - 0.18 * Double(i)))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                    .frame(width: Self.slabWidths[i], height: settled ? 8 : 26)
            }
        }
        .accessibilityHidden(true)
    }

    private var signature: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
                Text("Overstay").font(.system(size: 16, weight: .semibold)).foregroundStyle(Self.cream)
            }
            Text(Self.address).font(.system(size: 12)).foregroundStyle(Self.sand)
        }
    }
}
