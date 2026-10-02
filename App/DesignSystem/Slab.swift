import OverstayCore
import SwiftUI

/// One raised slab per group: lit top edge (the door light catches it), hairline, a long soft amber-tinted shadow.
/// Selected slabs sit 2pt higher with an amber rim; `settled` is the collapse end state (docs/MOTION.md §3.2): sunk 6pt,
/// scaled to .96 from its bottom edge, faded out. Pure fills and shadows, no material, so ImageRenderer can draw it.
/// Not a button by itself: `WeightBar` wraps it in one.
struct Slab: View {
    let group: LeftoverGroup
    var selected: Bool
    var settled = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        let dark = scheme == .dark
        let face = dark ? [Color(red: 0.180, green: 0.157, blue: 0.129), Color(red: 0.133, green: 0.114, blue: 0.090)]   // #2E2821 → #221D17
                        : [Color(red: 1, green: 0.992, blue: 0.976), Color(red: 0.953, green: 0.925, blue: 0.882)]        // #FFFDF9 → #F3ECE1
        VStack(alignment: .leading, spacing: 4) {
            Text(Grouping.title(group)).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY smallCaps with SF
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(Format.bytes(group.ghostBytes)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(Format.count(group.ghostCount, "process")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background {
            if contrast == .increased {
                shape.fill(.quaternary).overlay(shape.strokeBorder(Color.primary, lineWidth: selected ? 2 : 1))
            } else {
                shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {                                                       // the lit edge: amber when selected
                        Capsule().fill(selected ? Brand.amber : Color.white.opacity(dark ? 0.12 : 0.9))
                            .frame(height: 2).padding(.horizontal, Radius.tile).padding(.top, 1)
                    }
                    .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.10 : 0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.06), radius: 1, y: 1)
                    .shadow(color: Brand.amber.opacity(selected ? (dark ? 0.35 : 0.3) : 0.1), radius: 14, y: 10)   // constant per state, never animated
            }
        }
        .opacity(settled ? 0 : selected ? 1 : 0.72)
        .scaleEffect(settled ? 0.96 : 1, anchor: .bottom)
        .offset(y: settled ? 6 : selected ? -2 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Grouping.title(group)), \(Format.bytes(group.ghostBytes)), \(Format.count(group.ghostCount, "process"))\(selected ? ", selected" : "")")
        .accessibilityHidden(settled)
    }
}
