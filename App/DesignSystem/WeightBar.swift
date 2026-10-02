import OverstayCore
import SwiftUI

/// The weight bar: slabs side by side, each as wide as its share of the Ghost footprint (docs/MOTION.md §3.2 for the
/// collapse). A slab never gets narrower than `floorW`; groups whose share is below that are pinned at the floor and the
/// rest are shrunk to make room, so the bar is proportional everywhere the floor does not apply. A slab too narrow to
/// carry its name shows the size only and is spelled out in a legend line under the bar.
/// Click (or Space on a focused slab) toggles selection; `settled` holds the ids whose stop has finished (the collapse,
/// `AppModel.settledGroupIDs`). Groups with no Ghost are not drawn (they are in no bulk action). Only as many slabs as fit
/// are drawn, largest first; the rest fold into a "+N more" stub (they are still ticked and unticked from the sidebar). A
/// dashed stub at the end says how many Maybes there are.
struct WeightBar: View {
    let groups: [LeftoverGroup]
    @Binding var selected: Set<String>
    var settled: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Replaced by the first measurement (one layout pass, before the first frame is shown).
    @State private var width: CGFloat = 560

    private static let gap: CGFloat = 6, floorW: CGFloat = 60, stubW: CGFloat = 64

    private struct Cell: Identifiable {
        let group: LeftoverGroup
        let width: CGFloat
        var id: String { group.id }
    }

    /// Widths for `width` points: slabs that fit beside the stubs (at least one), then proportional shares with the floor.
    private static func plan(_ all: [LeftoverGroup], maybes: Int, width: CGFloat) -> (cells: [Cell], hidden: [LeftoverGroup]) {
        let base = maybes > 0 ? 1 : 0
        func fit(_ stubs: Int) -> Int { max(1, Int((width + gap - CGFloat(stubs) * (stubW + gap)) / (floorW + gap))) }
        let n = all.count <= fit(base) ? all.count : fit(base + 1)
        let shown = Array(all.prefix(n)), hidden = Array(all.dropFirst(n))
        let stubs = base + (hidden.isEmpty ? 0 : 1)
        var room = max(0, width - gap * CGFloat(max(0, shown.count + stubs - 1)) - stubW * CGFloat(stubs))
        var w = [CGFloat](repeating: floorW, count: shown.count)
        var free = Array(shown.indices)   // not pinned to the floor yet
        while !free.isEmpty {
            let total = CGFloat(max(1, free.reduce(UInt64(0)) { $0 + shown[$1].ghostBytes }))
            let shares = free.map { (i: $0, w: room * CGFloat(shown[$0].ghostBytes) / total) }
            let small = shares.filter { $0.w < floorW }
            if small.isEmpty {
                for s in shares { w[s.i] = s.w }
                break
            }
            for s in small { w[s.i] = floorW }
            room -= floorW * CGFloat(small.count)
            free.removeAll { i in small.contains { $0.i == i } }
        }
        return (shown.indices.map { Cell(group: shown[$0], width: w[$0]) }, hidden)
    }

    var body: some View {
        let all = groups.filter { $0.ghostCount > 0 }
        let maybes = groups.reduce(0) { $0 + $1.maybeCount }
        let plan = Self.plan(all, maybes: maybes, width: width)
        let tiny = plan.cells.filter { Slab.tier(forWidth: $0.width) == .tiny }.map(\.group)
        let legend = tiny.map { "\(Slab.label($0)) · \(Grouping.title($0)) · \(Format.bytes($0.ghostBytes))" }.joined(separator: "     ")
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .bottom, spacing: Self.gap) {
                ForEach(Array(plan.cells.enumerated()), id: \.element.id) { i, cell in
                    let group = cell.group
                    let on = selected.contains(group.id)
                    let tip = [Grouping.title(group), group.project?.name].compactMap { $0 }.joined(separator: " · ")
                    Button {
                        if selected.remove(group.id) == nil { selected.insert(group.id) }
                    } label: {
                        Slab(group: group, selected: on, settled: settled.contains(group.id), tier: Slab.tier(forWidth: cell.width))
                    }
                    .buttonStyle(.plain)
                    .disabled(settled.contains(group.id))
                    .frame(width: cell.width)
                    .help(tip)
                    .accessibilityLabel("\(Grouping.title(group)), \(Format.bytes(group.ghostBytes)), \(Format.count(group.ghostCount, "process"))")
                    .accessibilityValue(on ? "selected" : "not selected")
                    .animation(Motion.spring(reduceMotion).delay(reduceMotion ? 0 : Double(min(i, 8)) * Motion.stagger), value: settled)
                    .animation(Motion.pop(reduceMotion), value: selected)
                }
                if !plan.hidden.isEmpty {
                    let stub = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    let bytes = Format.bytes(plan.hidden.reduce(UInt64(0)) { $0 + $1.ghostBytes })
                    VStack(spacing: 2) {
                        Text("+\(plan.hidden.count) more").font(.caption2.weight(.semibold))
                        Text(bytes).font(.caption2).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.stubW, height: 72)
                    .background(stub.fill(Color.primary.opacity(0.05)))
                    .overlay(stub.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Format.count(plan.hidden.count, "more group")), \(bytes). Choose them in the sidebar.")
                }
                if maybes > 0 {
                    let stub = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    Text("+\(maybes) Maybe").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: Self.stubW, height: 72)
                        .overlay(stub.strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .accessibilityLabel("\(maybes) Maybe, not part of any bulk stop")
                }
            }
            .frame(height: 76)
            if !tiny.isEmpty {
                // Names for the slabs that are too narrow to carry one.
                Text(legend)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityHidden(true)   // each slab already speaks its full name
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { width = $0 }
            }
        }
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
