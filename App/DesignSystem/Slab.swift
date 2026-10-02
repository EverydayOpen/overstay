import OverstayCore
import SwiftUI

/// One raised slab per group: lit top edge (the door light catches it), hairline, a long soft amber-tinted shadow.
/// Selected slabs sit 2pt higher with an amber rim; `settled` is the collapse end state (docs/MOTION.md §3.2): sunk 6pt,
/// scaled to .96 from its bottom edge, faded out. Pure fills and shadows, no material, so ImageRenderer can draw it.
/// What it prints depends on the width `WeightBar` gives it (`Tier`): the project folder (or the agent when there is none),
/// the size and the count; narrower, less; the narrowest, the size alone, named in the bar's legend.
/// Not a button by itself: `WeightBar` wraps it in one.
struct Slab: View {
    enum Tier { case full, compact, tiny }

    let group: LeftoverGroup
    var selected: Bool
    var settled = false
    var tier = Tier.full
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    static func tier(forWidth width: CGFloat) -> Tier { width >= 104 ? .full : width >= 64 ? .compact : .tiny }

    /// "foo", the project folder; "Browsers" for a group with no folder. Short on purpose: two groups can share an agent.
    static func label(_ g: LeftoverGroup) -> String {
        if let name = g.project?.name, !name.isEmpty { return name }
        switch g.agent {
        case .automationBrowser: return "Browsers"
        case .unattributed: return "Servers"
        case .vscode: return "VS Code"
        case .gemini: return "Gemini"
        default: return g.agent.displayName
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        let dark = scheme == .dark
        let face = dark ? [Color(red: 0.180, green: 0.157, blue: 0.129), Color(red: 0.133, green: 0.114, blue: 0.090)]   // #2E2821 → #221D17
                        : [Color(red: 1, green: 0.992, blue: 0.976), Color(red: 0.953, green: 0.925, blue: 0.882)]        // #FFFDF9 → #F3ECE1
        VStack(alignment: tier == .tiny ? .center : .leading, spacing: 4) {
            if tier != .tiny {
                HStack(spacing: 4) {
                    Text(Self.label(group)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    if tier == .full {
                        Spacer(minLength: 0)
                        Image(systemName: group.agent.symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    }
                }
            }
            Text(Format.bytes(group.ghostBytes))
                .font(.system(size: tier == .full ? 17 : tier == .compact ? 14 : 13, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            if tier != .tiny {
                ViewThatFits(in: .horizontal) {
                    Text(Format.count(group.ghostCount, "process"))
                    Text("\(group.ghostCount)")
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(tier == .full ? Space.s : tier == .compact ? 8 : 6)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: tier == .tiny ? .center : .leading)
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
