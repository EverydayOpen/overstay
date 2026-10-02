import AppKit
import OverstayCore
import SwiftUI

/// "Copy my number": the 1200x630 card as a 600x315pt view. The on-screen preview and the exported PNG are this same
/// view (`Export` renders it at 2x). An object, not a screen: the night room in every scheme, front-facing and flat, pure
/// fills only (no material, blur, shadow or AppKit control), so every shared PNG looks the same (docs/DESIGN.md §6.6).
/// Content comes only from `ShareCard`, which holds no paths and no project names unless the user opted in.
///
/// Layout is plain arithmetic on a 600x315 canvas (36pt side inset, 28pt top and bottom): the wordmark row, the number,
/// then the weight bar and its legend on the bottom edge. The light is a background, so nothing is sized by a gradient
/// or an offset and nothing can push the content off the canvas (the first version's bug).
struct ShareCardView: View {
    static let size = CGSize(width: 600, height: 315)
    /// The site address without the scheme, e.g. "everydayopen.github.io/overstay" (Core has no URL).
    static let address = Links.website.absoluteString.replacingOccurrences(of: "https://", with: "")

    let card: ShareCard
    /// Bytes behind each entry of `card.topAgents`, same order (`AppModel.shareWeights`). The slabs are then true
    /// proportions, with an "Other" slab for the rest. nil: drawn by rank only (1 : 0.6 : 0.35), no sizes in the legend.
    var weights: [UInt64]? = nil
    /// On-screen width. The art is always drawn at 600pt and scaled, so the PNG never depends on this.
    var width = ShareCardView.size.width

    private static let night = [Color(red: 0.059, green: 0.051, blue: 0.043), Color(red: 0.086, green: 0.075, blue: 0.059)]   // #0F0D0B, #16130F
    private static let cream = Color(red: 0.965, green: 0.941, blue: 0.902)                                                  // #F6F0E6
    private static let sand = Color(red: 0.655, green: 0.608, blue: 0.541)                                                  // #A79B8A, 6.8:1 on the night
    private static let inset: CGFloat = 36
    private static let gap: CGFloat = 4
    private static let barWidth: CGFloat = 600 - 2 * 36

    var body: some View {
        let scale = width / Self.size.width
        art
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background { backdrop }
            .clipped()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: Self.size.height * scale, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Share card. \(ShareCardText.headline(card)) \(ShareCardText.subline(card))" + (card.isSample ? " \(ShareCardText.sampleWatermark)." : ""))
    }

    /// The night, and the door light: one tall warm pool centred on the leading edge (half of it falls outside and is
    /// clipped). An overlay on a clear fill, so its size never takes part in the layout.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: Self.night, startPoint: .top, endPoint: .bottom)
            Color.clear.overlay(alignment: .leading) {
                EllipticalGradient(colors: [Brand.amber.opacity(0.24), .clear], center: UnitPoint(x: 0, y: 0.5),
                                   startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: 400, height: 560)
            }
        }
    }

    private var art: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 8)
            hero
            Spacer(minLength: 8)
            if !parts.isEmpty { barBlock }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 28)
    }

    // MARK: - Top row

    /// The wordmark and address on the left, the "Sample data" watermark on the right.
    private var topRow: some View {
        HStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 24, height: 24)
            Text("Overstay").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Self.cream)
                .padding(.leading, 7)
            Text(Self.address).font(.system(size: 12)).foregroundStyle(Self.sand)
                .padding(.leading, 12)
            Spacer(minLength: 12)
            if card.isSample {
                HStack(spacing: 6) {
                    Circle().fill(Brand.amber).frame(width: 7, height: 7)
                    Text(ShareCardText.sampleWatermark).font(.system(size: 13, weight: .semibold)).tracking(0.3).foregroundStyle(Brand.amber)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Brand.amber.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Brand.amber.opacity(0.55), lineWidth: 1))
            }
        }
        .lineLimit(1)
        .frame(height: 24)
    }

    // MARK: - The number

    /// Core's headline split around the number: "Your AI agents left" / 9.4 GB / "running." or "Stopped 183 leftovers." /
    /// 9.4 GB / "was held.". With no number (all quiet, nothing stopped) the whole line, large.
    private var hero: some View {
        let line = ShareCardText.headline(card)
        let number = Format.bytes(card.bytes)
        let pieces = number.split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: 2) {
            if card.processCount > 0, let r = line.range(of: number) {
                Text(line[..<r.lowerBound].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.cream.opacity(0.92))
                    .lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(pieces.first ?? number)
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .tracking(-2)
                        .foregroundStyle(Brand.amber)
                    Text(pieces.count > 1 ? pieces[1] : "")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.amber)
                    Text(line[r.upperBound...].trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Self.cream)
                        .padding(.leading, 6)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            } else {
                Text(line)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(Self.cream)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = subline {
                Text(note).font(.system(size: 15)).foregroundStyle(Self.sand).lineLimit(1)
            }
        }
    }

    /// Found: "183 leftover processes" (the headline has the GB, not the count). Stopped: the count is in the headline, so
    /// only the project names, when the user opted in.
    private var subline: String? {
        var out: [String] = []
        if card.kind == .found, card.processCount > 0 { out.append(Format.count(card.processCount, "leftover process")) }
        if !card.projectNames.isEmpty { out.append(card.projectNames.joined(separator: ", ")) }
        return out.isEmpty ? nil : out.joined(separator: " · ")
    }

    // MARK: - Weight bar

    private struct Part {
        let name: String
        let bytes: UInt64?
        let weight: Double
        let color: Color
    }

    /// The slabs, largest first. With `weights`: the top agents by their bytes plus "Other" for the rest (when it is over
    /// 2% of the total). Without: by rank, 1 : 0.6 : 0.35 (ponytail: ShareCard has no per-agent bytes; add them there and
    /// drop `weights` if the callers should not have to pass them).
    private var parts: [Part] {
        let tints = [1.0, 0.74, 0.52].map { Brand.amber.opacity($0) }
        let names = Array(card.topAgents.prefix(3))
        var out: [Part] = []
        guard let w = weights, w.count == names.count else {
            let rank = [1.0, 0.6, 0.35]
            for (i, name) in names.enumerated() { out.append(Part(name: name, bytes: nil, weight: rank[i], color: tints[i])) }
            return out
        }
        for (i, name) in names.enumerated() where w[i] > 0 {
            out.append(Part(name: name, bytes: w[i], weight: Double(w[i]), color: tints[i]))
        }
        let known = w.reduce(UInt64(0), +)
        if card.bytes > known, Double(card.bytes - known) > 0.02 * Double(card.bytes) {
            out.append(Part(name: "Other", bytes: card.bytes - known, weight: Double(card.bytes - known), color: Self.sand.opacity(0.4)))
        }
        return out
    }

    /// Slab widths: proportional to weight, none under `minimum` (a small agent stays visible), summing to the bar width.
    private static func widths(_ weights: [Double], minimum: CGFloat) -> [CGFloat] {
        let room = barWidth - gap * CGFloat(max(0, weights.count - 1))
        var pinned = Set<Int>()
        var out = [CGFloat](repeating: minimum, count: weights.count)
        var again = true
        while again {
            again = false
            let free = room - minimum * CGFloat(pinned.count)
            let sum = weights.indices.filter { !pinned.contains($0) }.reduce(0.0) { $0 + weights[$1] }
            guard sum > 0 else { break }
            for i in weights.indices where !pinned.contains(i) {
                out[i] = free * CGFloat(weights[i] / sum)
                if out[i] < minimum {
                    pinned.insert(i)
                    out[i] = minimum
                    again = true
                }
            }
        }
        return out
    }

    /// After a stop the bar sits lower and dimmer, echoing the collapse; before, it is full height.
    private var barBlock: some View {
        let settled = card.kind == .stopped
        let parts = self.parts
        let sizes = Self.widths(parts.map(\.weight), minimum: 30)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Self.gap) {
                ForEach(parts.indices, id: \.self) { i in
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    shape.fill(parts[i].color.opacity(settled ? 0.6 : 1))
                        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                        .frame(width: sizes[i], height: settled ? 22 : 34)
                }
            }
            .frame(width: Self.barWidth, alignment: .leading)
            HStack(spacing: 14) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        Circle().fill(parts[i].color).frame(width: 7, height: 7)
                        Text(parts[i].name).foregroundStyle(Self.sand).lineLimit(1).minimumScaleFactor(0.8)
                        if let bytes = parts[i].bytes { Text(Format.bytes(bytes)).fontWeight(.semibold).foregroundStyle(Self.cream) }
                    }
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .frame(width: Self.barWidth, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

extension AppModel {
    /// The bytes behind `card.topAgents`, in that order, summed the way `ShareCardText` ranks them (a stopped card by what
    /// exited, a found card by Ghost footprint). Pass it to `ShareCardView` and the `Export` calls.
    func shareWeights(_ card: ShareCard) -> [UInt64] {
        var bytes: [String: UInt64] = [:]
        if card.kind == .stopped, let lastOutcome {
            for r in lastOutcome.results where r.status.wasStopped { bytes[r.target.agent.displayName, default: 0] += r.target.footprintBytes }
        } else if let scan {
            for g in scan.groups where g.ghostCount > 0 { bytes[g.agent.displayName, default: 0] += g.ghostBytes }
        }
        return card.topAgents.map { bytes[$0] ?? 0 }
    }
}
