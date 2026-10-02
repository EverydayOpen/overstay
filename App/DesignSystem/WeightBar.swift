import OverstayCore
import SwiftUI

/// The weight bar: slabs side by side, width proportional to Ghost footprint with a floor so small groups stay legible.
/// Click (or Space on a focused slab) toggles selection; `settled` holds the ids whose stop has finished (the collapse,
/// docs/MOTION.md §3.2; `AppModel.settledGroupIDs`). Groups with no Ghost are not drawn (they are in no bulk action).
/// Only as many slabs as fit are drawn, largest first; the rest fold into a "+N more" stub (they are still ticked and
/// unticked from the sidebar). A dashed stub at the end says how many Maybes there are.
struct WeightBar: View {
    let groups: [LeftoverGroup]
    @Binding var selected: Set<String>
    var settled: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let all = groups.filter { $0.ghostCount > 0 }
        let maybes = groups.reduce(0) { $0 + $1.maybeCount }
        GeometryReader { g in
            let gap = Space.xs, minW: CGFloat = 92, stubW: CGFloat = 64
            // Slabs that fit beside `stubs` stubs: n * minW + stubs * stubW + (n + stubs - 1) * gap <= width. At least one.
            let fit = { (stubs: Int) -> Int in
                max(1, Int((g.size.width + gap - CGFloat(stubs) * (stubW + gap)) / (minW + gap)))
            }
            let base = maybes > 0 ? 1 : 0
            let n = all.count <= fit(base) ? all.count : fit(base + 1)
            let shown = Array(all.prefix(n))
            let hidden = all.dropFirst(n)
            let stubs = base + (hidden.isEmpty ? 0 : 1)
            let total = max(1, shown.reduce(UInt64(0)) { $0 + $1.ghostBytes })
            let used = gap * CGFloat(max(0, shown.count + stubs - 1)) + minW * CGFloat(shown.count) + stubW * CGFloat(stubs)
            let free = max(0, g.size.width - used)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, group in
                    let on = selected.contains(group.id)
                    Button {
                        if selected.remove(group.id) == nil { selected.insert(group.id) }
                    } label: {
                        Slab(group: group, selected: on, settled: settled.contains(group.id))
                    }
                    .buttonStyle(.plain)
                    .disabled(settled.contains(group.id))
                    .frame(width: minW + free * CGFloat(group.ghostBytes) / CGFloat(total))
                    .accessibilityLabel("\(Grouping.title(group)), \(Format.bytes(group.ghostBytes)), \(Format.count(group.ghostCount, "process"))")
                    .accessibilityValue(on ? "selected" : "not selected")
                    .animation(Motion.spring(reduceMotion).delay(reduceMotion ? 0 : Double(min(i, 8)) * Motion.stagger), value: settled)
                    .animation(Motion.pop(reduceMotion), value: selected)
                }
                if !hidden.isEmpty {
                    let stub = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    let bytes = Format.bytes(hidden.reduce(UInt64(0)) { $0 + $1.ghostBytes })
                    VStack(spacing: 2) {
                        Text("+\(hidden.count) more").font(.caption2.weight(.semibold))
                        Text(bytes).font(.caption2).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: stubW, height: 72)
                    .background(stub.fill(Color.primary.opacity(0.05)))
                    .overlay(stub.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Format.count(hidden.count, "more group")), \(bytes). Choose them in the sidebar.")
                }
                if maybes > 0 {
                    let stub = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    Text("+\(maybes) Maybe").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: stubW, height: 72)
                        .overlay(stub.strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .accessibilityLabel("\(maybes) Maybe, not part of any bulk stop")
                }
            }
        }
        .frame(height: 76)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight bar: memory held per group")
    }
}

/// The popover's reading of the same groups: arcs of one ring, each group's share of the Ghost footprint, amber at falling
/// opacity by rank. `progress` 1 → 0 shrinks every arc toward the top (the collapse). Animatable, so a
/// `.animation(_:value:)` on the stop's progress interpolates it; `Canvas` redraws per frame for that 0.28 s and never loops.
/// VERIFY: that `Path.addArc(clockwise: false)` runs clockwise on screen (SwiftUI's y axis is flipped).
struct OrbitRing: View, Animatable {
    let groups: [LeftoverGroup]
    var progress = 1.0
    var size: CGFloat = 56

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let shown = groups.filter { $0.ghostCount > 0 }
        let total = Double(max(1, shown.reduce(UInt64(0)) { $0 + $1.ghostBytes }))
        let p = min(max(progress, 0), 1)
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2 - 3
            let gap = shown.count > 1 ? 6.0 : 0.0
            var start = -90.0
            for (i, g) in shown.enumerated() {
                let sweep = 360 * Double(g.ghostBytes) / total * p - gap
                if sweep > 0 {
                    var path = Path()
                    path.addArc(center: c, radius: r, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
                    ctx.stroke(path, with: .color(Brand.amber.opacity(max(0.22, 1 - Double(i) * 0.25))),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                start += sweep + gap
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // the number beside it carries the value
    }
}
