import AppKit
import OverstayCore
import SwiftUI

// docs/DESIGN.md §6.1 and docs/MOTION.md §3.1. Space, Radius, Motion, surface, OnFloor, Horizon, Metric, Tag, KeyCapStyle,
// HoverTilt, flip and FlipFaces are the family's shared mechanics (Tirekick's, unchanged); Brand, Room, AmberButtonStyle and
// the model extensions are Overstay's. Every API here is macOS 13; anything newer lives in Compat.swift.

/// Spacing in points. `xxl` is the screen padding, `l` the bottom bar's.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum Radius {
    static let card: CGFloat = 12
    /// A plate (the weight bar's surface), a slab or tile, a list row, a chip. Outer = inner + padding (rule 7).
    static let plate: CGFloat = 18
    static let tile: CGFloat = 14
    static let row: CGFloat = 12
    static let chip: CGFloat = 8
}

/// docs/MOTION.md §1.2, spelled for macOS 13: the duration-and-bounce springs are macOS 14, these are the same curves.
enum Motion {
    /// `.smooth` is macOS 14. Under Reduce Motion callers also drop movement and keep only the fade.
    static func standard(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.28)
    }
    /// Surfaces: flips, deal-ins, a tilt settling back, a slab settling.
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.78)
    }
    static let hero = Animation.spring(response: 0.9, dampingFraction: 0.8)
    static func pop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.62)
    }
    static let follow = Animation.interactiveSpring(response: 0.25, dampingFraction: 0.86)
    /// Seconds between slabs in the collapse and between rows flipping in. Callers cap the index at 8 so a long list never trickles.
    static let stagger = 0.045
}

// MARK: - Brand

/// docs/DESIGN.md §1, §6. Amber is the one accent ("leftover"); green only for All quiet; red only on a refused row's symbol.
enum Brand {
    /// Warm brown-black: the soft shadow under porcelain surfaces is tinted with it, never neutral grey (rule 3).
    static let ink = Color(red: 0.16, green: 0.09, blue: 0.03)                                          // #281808
    /// The door light and every amber fill. Near-black text on it (9.5:1).
    static let amber = Color(red: 0.949, green: 0.663, blue: 0.231)                                      // #F2A93B
    static let onAmber = Color(red: 0.078, green: 0.059, blue: 0.031)                                    // #140F08
    /// Amber as text or a symbol: readable on paper and on the night room (4.6:1 / 9.6:1).
    static let amberInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.961, green: 0.710, blue: 0.290, alpha: 1)                              // #F5B54A
            : NSColor(srgbRed: 0.604, green: 0.357, blue: 0.000, alpha: 1)                              // #9A5B00
    })
}

extension AgentKind {
    /// Neutral SF Symbols, never vendor logos (BUILD_PLAN §1). VERIFY each in the SF Symbols app: availability macOS 13 or earlier.
    var symbol: String {
        switch self {
        case .claudeCode: "terminal"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow"
        case .zed: "bolt"
        case .windsurf: "wind"
        case .vscode: "curlybraces"
        case .gemini: "sparkles"
        case .automationBrowser: "globe"
        case .unattributed: "server.rack"
        }
    }
}

extension Classification {
    /// The chip word. Tier is carried by the word, never by colour alone (§1.1 rule 4). The UI never says "Ghost".
    var word: String {
        switch self {
        case .ghost: "Leftover"
        case .maybe: "Maybe"
        case .ignored: "Ignored"
        case .protected: "Protected"
        }
    }
    var tint: Color { self == .ghost ? Brand.amber : .secondary }
}

extension TargetStatus {
    /// Result rows: a symbol in a status colour, the word beside it. Red only here, only on refused/failed.
    var symbol: String {
        switch self {
        case .stopped, .forceStopped: "checkmark.circle.fill"
        case .survived: "clock.badge.exclamationmark"
        case .alreadyGone: "minus.circle"
        case .changedSinceScan, .blocked: "hand.raised"
        case .refused, .failed: "xmark.circle.fill"
        case .signalled: "paperplane"
        }
    }
    var tint: Color {
        switch self {
        case .stopped, .forceStopped: .green
        case .refused, .failed: .red
        default: .secondary
        }
    }
}

// MARK: - Surfaces (docs/DESIGN.md §6)

/// The room behind stage screens (first run, the main window's overview, the result sheet): the plain window plus the
/// door light at the leading edge, as a static wash. Increase Contrast gets the plain window. Drawn once per size.
struct Room: View {
    var strength = 1.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if contrast != .increased {
                if dark {
                    LinearGradient(colors: [Color(red: 0.078, green: 0.067, blue: 0.051), Color(red: 0.043, green: 0.035, blue: 0.031)],
                                   startPoint: .top, endPoint: .bottom)                                  // #14110D → #0B0908
                }
                // The door light: one tall warm pool whose centre is the leading edge (rule 2). An overlay, so the 720pt
                // frame never sizes the room; the clip below trims the half that falls outside the window.
                Color.clear.overlay(alignment: .leading) {
                    EllipticalGradient(colors: [Brand.amber.opacity((dark ? 0.22 : 0.16) * strength), .clear],
                                       center: UnitPoint(x: 0, y: 0.55), startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: 720, height: 720)
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A symbol in a recessed, tinted squircle: the site's icon well. Pure fills, so ImageRenderer-safe.
    func well(_ tint: Color, size: CGFloat = 44) -> some View {
        modifier(Well(tint: tint, size: size))
    }

    /// A raised object (never a row): a tight contact shadow plus a wide soft one.
    /// compositingGroup so glyphs don't cast their own shadows (MOTION.md §1.4).
    func lifted() -> some View {
        compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.20), radius: 24, y: 14)
    }

    /// Commands and their output: a recessed well. The text stays primary and selectable.
    func terminal() -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return background(Color.primary.opacity(0.04), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// Porcelain surface: white (a 5.5% white lift in dark), a hairline rim, a tight contact shadow plus a wide soft
    /// one tinted with the brand's ink. Concentric: pass the outer radius; content inside pads by radius - inner.
    /// Replaces grey grouped Form cells and `.quaternary` slabs. Never glass, never on a single row.
    func surface(_ radius: CGFloat = 16) -> some View { modifier(Surface(radius: radius)) }
}

private struct Surface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark, strong = contrast == .increased
        // The shadows hang off the fill, not the content: glyphs never cast their own (MOTION §1.4), and AppKit-backed
        // controls inside need no compositing group. White, not `.background`, which is the window's grey on macOS.
        // Dark's 5.5% fill casts almost nothing, so there the rim draws the edge (DESIGN.md §1.1 rule 3).
        return content
            .background {
                shape.fill(dark ? Color.white.opacity(0.055) : Color.white)
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.05), radius: 1, y: 1)
                    .shadow(color: Brand.ink.opacity(dark ? 0.5 : 0.10), radius: 16, y: 8)
            }
            .overlay {
                shape.strokeBorder(strong ? Color.primary.opacity(0.5) : Color.primary.opacity(dark ? 0.10 : 0.07), lineWidth: strong ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// An object standing on a glossy floor: the view, its mirror fading out over 45% of its height, and a still
/// contact shadow at its base. Drawn once. Pass a stateless view: it is drawn twice. No mirror under Reduce
/// Transparency.
struct OnFloor<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let mirror = reduceTransparency ? 0 : height * 0.45
        VStack(spacing: 2) {
            content
                .background(alignment: .bottom) {
                    Ellipse().fill(.black.opacity(0.16)).frame(width: height * 0.7, height: height * 0.08).blur(radius: 6)
                        .offset(y: height * 0.04)   // centred on the base line. VERIFY by eye under an app icon
                        .accessibilityHidden(true)
                }
            if !reduceTransparency {
                content
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: mirror, alignment: .top).clipped()
                    .mask { LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // Pinned: on CI the mirror collapsed to 0pt and the old negative padding pulled the next view over the object's base.
        .frame(height: height + 2 + mirror, alignment: .top)
    }
}

/// The key light under a lifted object: a pool of light and a thin bright line. Static; drawn once per size.
/// `soft`: Whydunit's dawn bloom. Overstay passes false: a hard line with a tight spill. Decorative, hidden from
/// VoiceOver. The line runs through the middle of the view's height.
struct Horizon: View {
    var tint: Color
    var width: CGFloat = 420
    var soft = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if contrast != .increased {
                // Elliptical, so the pool fades out inside its wide, short frame instead of being cut at the edges.
                EllipticalGradient(colors: [tint.opacity(soft ? 0.42 : 0.22), tint.opacity(soft ? 0.10 : 0), .clear],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            }
            LinearGradient(colors: [.clear, tint, .white.opacity(0.9), tint, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.86, height: 1)
        }
        .frame(width: width, height: width * (soft ? 0.32 : 0.14))   // the same with or without the pool
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small-caps label over a big number. One VoiceOver element. Overstay's numerals are rounded; mono is for pids,
/// paths and argv only.
struct Metric: View {
    let label: String
    let value: String
    var unit: String? = nil
    var dot: Color? = nil
    var design: Font.Design = .rounded

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(value).font(.system(size: 26, weight: .semibold, design: design)).monospacedDigit()
                if let unit { Text(unit).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Increase Contrast draws a 1pt primary edge (DESIGN.md §1.1).
private struct Well: ViewModifier {
    let tint: Color
    let size: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let increased = contrast == .increased
        return content
            .frame(width: size, height: size)
            // The inner shadow is what makes it read as recessed (ShapeStyle.shadow is macOS 13).
            .background(shape.fill(tint.opacity(0.16).gradient.shadow(.inner(color: .black.opacity(0.22), radius: 1.5, y: 1))))
            .overlay(shape.strokeBorder(increased ? Color.primary : tint.opacity(0.24), lineWidth: increased ? 1 : 0.5))
    }
}

/// A count or a word in a tinted capsule. Colour sits in the dot and the fill; the text stays primary, so it always
/// has full contrast ("only symbols carry colour"). Increase Contrast adds a stroke. `Tag(text: c.tier.word, tint: c.tier.tint)`.
struct Tag: View {
    let text: String
    var tint: Color = .secondary
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(contrast == .increased ? Color.primary.opacity(0.4) : tint.opacity(0.3), lineWidth: contrast == .increased ? 1 : 0.5))
    }
}

// MARK: - Buttons

/// The one prominent button per screen (Stop 183, Continue, Copy my number): an amber key-cap with near-black text, a
/// lit top edge and a brown lip; a press sinks 1pt. No glow: the light comes from the door, not the button.
/// `.keyboardShortcut(.defaultAction)` still works. Replaces .borderedProminent there.
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    // Not `Body`: that's ButtonStyle's associated type.
    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            let down = configuration.isPressed && !reduceMotion
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.onAmber)
                .padding(.horizontal, 18)
                .frame(minHeight: 30)
                .background(shape.fill(Brand.amber).overlay(shape.fill(LinearGradient(colors: [.clear, Color.black.opacity(0.12)], startPoint: .top, endPoint: .bottom))))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .background(shape.fill(Color(red: 0.55, green: 0.33, blue: 0.05)).offset(y: down ? 0.5 : 1.5))   // the lip; its bottom stays put
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.4)
                .offset(y: down ? 1 : 0)
                .animation(Motion.pop(reduceMotion), value: configuration.isPressed)
        }
    }
}

/// A real key-cap (choices, tiles): a face lighter at the top with a lit rim, on a side wall that shrinks from 3pt to
/// 1pt as the face sinks 2pt. The rim turns amber under the pointer. No tilt: HoverTilt is on exactly two views in the app
/// (docs/MOTION.md §3.5). The label is padded by `Space.m` here.
struct KeyCapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Cap(configuration: configuration) }

    private struct Cap: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @State private var hovers = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            let dark = scheme == .dark, down = configuration.isPressed && !reduceMotion
            let face = dark ? [Color(red: 0.180, green: 0.157, blue: 0.129), Color(red: 0.133, green: 0.114, blue: 0.090)]   // #2E2821 → #221D17
                            : [Color.white, Color(red: 0.957, green: 0.937, blue: 0.902)]                                        // #FFFFFF → #F4EFE6
            let wall = dark ? Color(red: 0.039, green: 0.031, blue: 0.024) : Color(red: 0.851, green: 0.816, blue: 0.761)        // #0A0806 / #D9D0C2
            configuration.label
                .frame(maxWidth: .infinity)
                .padding(Space.m)
                .background {
                    if contrast == .increased {
                        shape.fill(.quaternary).overlay(shape.strokeBorder(Color.primary, lineWidth: 1))
                    } else {
                        ZStack {
                            // The side wall. In dark its rim keeps it apart from the near-black room.
                            shape.fill(wall).overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.10 : 0), lineWidth: 1)).offset(y: down ? 1 : 3)
                            shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.14 : 0.9), lineWidth: 1)
                                    .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center) })   // the lit top rim
                                .overlay(shape.strokeBorder(hovering ? Brand.amber.opacity(0.6) : Color.primary.opacity(dark ? 0.08 : 0.12), lineWidth: hovering ? 1 : 0.5))
                                .shadow(color: Brand.ink.opacity(dark ? 0.5 : 0.12), radius: 8, y: 4)   // constant: never animated
                        }
                    }
                }
                .contentShape(shape)
                .offset(y: down ? 2 : 0)
                .animation(Motion.pop(reduceMotion), value: configuration.isPressed)
                .bounce(on: hovers)                                   // Compat: symbol bounce on macOS 14+
                .onHover {
                    hovering = $0                                     // a colour, not motion: shown under Reduce Motion too
                    if $0 && !reduceMotion { hovers += 1 }
                }
        }
    }
}

/// Copying has no visible effect, so the title reads "Copied" for a moment.
struct CopyButton: View {
    var title = "Copy"
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : title) {
            action()
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copied = false
            }
        }
    }
}

// MARK: - Motion (docs/MOTION.md §1.8, §3)

/// Turns a surface to face the pointer (the edge under it recedes), at most `max` degrees, with an optional glare
/// masked to the content's own shape. Flat under Reduce Motion or with `max: 0`. The pointer is read in the layout
/// frame, so the tilt never moves hit areas. Used on exactly two views in the app: the first-run icon and the result's share card.
struct HoverTilt: ViewModifier {
    var max = 7.0
    var glare = false
    @State private var size = CGSize.zero
    @State private var p = CGPoint.zero          // -1...1 from the center
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if glare && hovering {
                    RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .center,
                                   startRadius: 0, endRadius: size.width * 0.6)
                        .offset(x: p.x * size.width / 2, y: p.y * size.height / 2)
                        .mask { content }            // VERIFY: content drawn twice; fine for an icon and one card
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // VERIFY on a Mac: the edge under the pointer should recede; negate both angles if it rises instead.
            .rotation3DEffect(.degrees(-p.y * max), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(p.x * max), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .background {
                GeometryReader { g in
                    Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 }
                }
            }
            .onContinuousHover { phase in
                guard !reduceMotion, max > 0, size.width > 0, size.height > 0 else { return }
                switch phase {
                case .active(let at):
                    withAnimation(Motion.follow) {
                        hovering = true
                        p = CGPoint(x: at.x / size.width * 2 - 1, y: at.y / size.height * 2 - 1)
                    }
                case .ended:
                    withAnimation(Motion.spring(false)) {
                        hovering = false
                        p = .zero
                    }
                }
            }
    }
}

extension AnyTransition {
    /// A card turning down into place from its top edge like a split-flap, and leaving by fading, so old and new never
    /// overlap mid-turn. Opacity only under Reduce Motion.
    static func flip(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .modifier(active: FlipDown(angle: 70, opacity: 0), identity: FlipDown(angle: 0, opacity: 1)),
            removal: .opacity)
    }
}

private struct FlipDown: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content   // VERIFY sign on a Mac: the bottom edge should start toward the viewer
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .opacity(opacity)
    }
}

/// Shows the content until the turn passes 90°, then `back`: a card turning over. `angle` animates.
struct FlipFaces<Back: View>: ViewModifier, Animatable {
    var angle: Double
    let back: Back
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(angle < 90 ? 1 : 0)
            .overlay {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(angle < 90 ? 0 : 1)
                    .accessibilityHidden(true)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}
