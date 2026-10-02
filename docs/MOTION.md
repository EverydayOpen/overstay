# Motion spec: Overstay (website and app)

**Why:** the family requirement (2026-09-28): a modern UI with 3D motion that stays lightweight, on the website and
in the app. Overstay's version of it is "Last Call" (`docs/DESIGN.md` §1): one scene, one sweep, then stillness.
**Authority:** this file is authoritative for motion. `docs/DESIGN.md` is authoritative for tokens, surfaces and
compositions and wins where the two conflict. BUILD_PLAN §8 already fixes the rules this file obeys: one signature
animation (the collapse, at most 1 s for the whole bar), everything else a plain fade, all of it off under Reduce
Motion, nothing moving at idle.
**Shared system:** §1 is the EverydayOpen motion language, copied verbatim from the Tirekick repo's `docs/MOTION.md`
(identical there and in Whydunit's); change all three together. Where §1 says "Tirekick (macOS 13)", read Overstay:
the deployment target is the same. Two Overstay-specific differences to §1.7: there is no webfont, and
`site/static/motion.js` is the shared file **plus one appended job** (the sweep, §2.4), so it is not byte-identical
to the siblings' and its cap is 6 KB, not 5.
**Status:** nothing in this file has been built or run. The CSS and JS in §2 follow the same mechanics as the
siblings' prototype-tested code but have not themselves been opened in a browser. The Swift in §3 is written, not
compiled; anything unconfirmed is marked VERIFY.

## 1. The EverydayOpen motion language (shared, identical in both repos)

### 1.0 What makes 3D feel premium and still light (research, 2026-09-28)

- **Only the object moves.** Apple's product pages keep headlines, prices and buttons still. The product and the
  depth around it do the moving, and the hero plays once and then stops.
- **One camera, a few planes.** Linear and Raycast get depth from 2 to 4 flat layers at different Z, turned a few
  degrees in one perspective. They never build a full 3D model. Flat layers are cheap and keep text sharp.
- **Physical, damped, quick.** Things and Arc use short springs with a little overshoot for small objects and none
  for big surfaces. Nothing floats for more than about a second.
- **Light follows the pointer.** macOS Tahoe's Liquid Glass puts specular highlights where you move, and Reduce Motion
  turns that parallax off. Here that becomes glare under the pointer plus shadows that don't move.
- **The platform does the heavy lifting.** CSS 3D transforms and scroll-driven animations run on the compositor.
  Safari 26 shipped scroll-driven animations, and Safari 26.4 moved them to the compositor thread. Firefox stable
  still hides them behind a flag (mid-2026), so it gets a small IntersectionObserver fallback. In SwiftUI,
  `rotation3DEffect`, springs and transitions cover everything here without SceneKit or Metal.
- **Trust tools animate facts calmly.** Motion never makes a verdict look scarier or more cheerful than it is.

### 1.1 Principles (rules, not taste)

1. **Text never waits.** Hero headlines, taglines, verdicts, numbers and buttons render still, at once. Below the
   fold, a block can rise in as it enters the viewport, and it is done by the time 75% of it is visible.
2. **One hero moment per surface, then stillness.** Every sequence ends: at most 3.2 s on the web and 1 s in the
   apps. The only loops are a progress indicator that runs while real work runs (a scan, the checks).
3. **Motion never encodes severity.** A red "Walk away" arrives exactly like a green "Clean". Nothing shakes, flashes
   or pulses to alarm.
4. **Depth follows light.** A surface turns to face the pointer: the edge under the pointer recedes. The glare sits
   under the pointer. Shadows are fixed per layer and move only with their surface.
5. **Physical and quick.** Surfaces use springs with bounce ≤ 0.25. Small glyphs use ≤ 0.4. Nothing lasts longer
   than 1.1 s except the one-time hero sequence.
6. **Reduce Motion means no movement.** The end state is the same, reached by at most a 150–200 ms fade. No tilt, no
   parallax, no flip: a flip becomes a crossfade or an instant swap.
7. **Compositor only.** The web animates `transform`, `translate`, `rotate`, `scale` and `opacity`. The apps animate
   geometry effects and opacity, never frames or padding, during 3D motion.

### 1.2 Tokens

**Depth.** The web shares one real perspective per scene. SwiftUI has no shared 3D space, so each view gets its own
`perspective:` (1 is the default; lower is flatter). The table's mapping is approximate: VERIFY on a Mac and tune by
eye.

| Token | CSS | SwiftUI `perspective:` | Use |
|---|---|---|---|
| scene | `--persp-scene: 1600px` | 0.4–0.5 | hero scenes, grids, the report card, the laptop |
| card | `--persp-card: 900px` | 0.6 | cards, tiles, rows, FAQ answers |
| glyph | `perspective(400px)` inline | 1.0 (default) | icons, step numbers, keys |

| Z layer | CSS `translateZ` | SwiftUI stand-in | Shadow |
|---|---|---|---|
| back | −140 to −160px | smaller, behind in a ZStack | none |
| surface | 0 | the view itself | `--shadow` (z3) if it floats, none on a band |
| hug | +40 to +60px | offset ×1 of the tilt | `--z1`/`--z2` |
| float | +90px (max +140) | offset ×2 of the tilt | `--shadow` |

Use at most 4 layers in one scene.

**Easing and springs.**

| Token | CSS | SwiftUI (Whydunit, macOS 15) | SwiftUI (Tirekick, macOS 13) | Use |
|---|---|---|---|---|
| out | `--ease-out: cubic-bezier(.16, 1, .3, 1)` | `Motion.spring(_:)` = `.spring(duration: 0.45, bounce: 0.22)` | `.spring(response: 0.45, dampingFraction: 0.78)` | entrances, settling, tilt return, flips |
| hero | `--ease-out` over `--t-hero` | `Motion.hero` = `.spring(duration: 0.9, bounce: 0.2)` | `.spring(response: 0.9, dampingFraction: 0.8)` | one-time entrances (icon, lid) |
| spring | `--ease-spring: cubic-bezier(.34, 1.56, .64, 1)` | `Motion.pop` = `.spring(duration: 0.32, bounce: 0.38)` | `.spring(response: 0.32, dampingFraction: 0.62)` | chips, symbols, keys |
| follow | `var(--t-fast)` with `--ease-out` | `Motion.follow` = `.interactiveSpring(response: 0.25, dampingFraction: 0.86)` | same (macOS 10.15 API) | following the pointer |
| in-out | `--ease-in-out: cubic-bezier(.65, 0, .35, 1)` | `.easeInOut(duration:)` | same | beams, rising files |
| standard | none | `Motion.standard(_:)` (existing) | `Motion.standard(_:)` (existing) | plain state changes |

`.spring(duration:bounce:)` is macOS 14. With bounce ≥ 0 its damping fraction is 1 − bounce, so the Tirekick column
is the same curve.

**Durations.** `--t-fast .16s` (hover, press), `--t-base .32s` (state change, FAQ), `--t-slow .7s` (reveal, tilt
settle), `--t-hero 1.1s` (hero plane). **Stagger:** 90 ms between cards and 80 ms between report rows on the web.
In the apps, Whydunit rows use `Motion.stagger = 0.045` and Tirekick check rows keep their existing 70 ms. The
stagger index is capped (6 on the web, 8 in the apps), so a long list never trickles.

### 1.3 Hover tilt, glare and sheen

| Surface | Max tilt | Lift | Glare |
|---|---|---|---|
| Hero scene (window, laptop and card together) | 5° | none (it already floats) | only the report card |
| Cards and tiles | 7° | `scale 1.02` (web), press `0.97` | web yes, app no |
| App icon (Whydunit Welcome) | 12° | none | yes, masked to the icon |
| Laptop drawing (Tirekick Welcome) | 8° | none | no |
| Reading surface with long text (report card in the app) | 4° | none | yes |
| Tables, forms, lists, sidebars, buttons, navigation, keys | 0° | press depth only | no |

- **Direction.** `px` and `py` run from −1 to 1, measured from the center. CSS uses
  `rotateX(py × −max) rotateY(px × max)`, which was checked in Chromium: the edge under the pointer recedes. SwiftUI
  starts from the same formula; VERIFY the signs on a Mac.
- **Follow fast, settle slow.** Follow the pointer over 160 ms. Return over 700 ms (web) or with `Motion.spring`
  (app).
- **Fine pointers only.** Tilt needs `(hover: hover) and (pointer: fine)`; a Mac always qualifies. Phones get
  scroll-driven depth instead (§1.7).
- **Hit areas never move.** The web reads the pointer on the element and caches the box when the pointer enters. The
  app gets `onContinuousHover` coordinates in the untransformed layout frame.
- **Glare** is a soft radial spot under the pointer, about 60% of the surface wide, fading in over 160 ms. White
  can't shine on white, so light mode uses a faint accent spotlight (`rgb(0 102 204 / .07)`). Dark mode uses white
  at .10, and the app uses white at .28. On the web it is a 200% layer moved with `transform` and clipped by the
  card, drawn between the card's fill and its text, so it never repaints and never lowers text contrast.
- **Sheen** is a single linear highlight sweep. It is used only for the Tirekick scan beam, once.

### 1.4 Shadows that sell depth

- `--z1: 0 1px 2px rgb(0 0 0 / .06), 0 4px 12px rgb(0 0 0 / .05)`: hug layers and guide boxes.
- `--z2: 0 2px 6px rgb(0 0 0 / .06), 0 12px 32px rgb(0 0 0 / .1)`: small floating badges.
- `--shadow` (existing, z3): floating surfaces and chips.
- **Dark mode:** black backgrounds swallow shadows, so each shadow is darker and carries a 1px light rim
  (`0 0 0 1px rgb(255 255 255 / .06–.12)`) that draws the edge.
- **Never animate `box-shadow` or `filter`.** A shadow belongs to its layer. Depth changes come from moving the
  surface, and the shadow moves with it.
- **App:** use `.compositingGroup().shadow(...)` on anything that contains text, so glyphs don't get shadows of
  their own.

### 1.5 Reduce Motion

| Effect | With Reduce Motion |
|---|---|
| Hero sequence (web) | Nothing plays. The page shows the final state: lid open, files uploaded, rows filled, chips gone. |
| Pointer tilt, glare, parallax | Off (flat). |
| Scroll reveal, steps coin, phone scroll lean | Off: content is simply there. |
| FAQ unfold, button press scale | Off. `<details>` opens instantly. |
| Report card flip (web) | Instant swap by `visibility`. The button still works. |
| App entrances (icon, lid, card deal-in) | Shown at rest immediately, or a `Motion.standard(true)` fade. |
| Row flip-ins, split-flap verdict, sheet card swaps | `.opacity` transitions. |
| Scan loops (cloud glyph, laptop beam) | Not drawn. The system `ProgressView` stays. |
| Symbol effects | Removed (`.symbolEffectsRemoved(reduceMotion)` in Whydunit; Tirekick never triggers them). |

The web puts every movement inside `@media (prefers-reduced-motion: no-preference)`, so Reduce Motion needs no
override rules except the flip. The apps read `@Environment(\.accessibilityReduceMotion)` in every view that moves,
or go through `Motion.*(reduceMotion)`. VoiceOver labels, traits and element grouping never change.

### 1.6 Performance rules

**Web**

- Animate `transform`, `translate`, `rotate`, `scale` and `opacity`, plus the custom properties `--px` and `--py`
  that feed them. Never animate `box-shadow`, `filter`, `background-position`, size or position.
- **Grouping properties flatten 3D.** Never put `opacity < 1`, a non-visible `overflow`, `filter`, `clip-path`,
  `mask`, `mix-blend-mode`, `isolation` or `contain: paint` on an element that has
  `transform-style: preserve-3d`. Fade its children or its parent instead. The prototype follows this.
- No `backdrop-filter` inside a 3D scene (Safari draws it flat), and no permanent `will-change`: it wastes GPU memory
  and blurs text in Safari.
- Use `translate`/`rotate`/`scale` (the individual properties) for reveals and `transform` for tilt, so both can
  run on one card without fighting.
- At most one `requestAnimationFrame` per frame. `pointermove` listeners are passive. The box is read once per
  element entered.
- No infinite animations on the web.
- **CSS stays in `styles.css`.** `motion.js` is byte-identical in both repos (2.7 KB; hard cap 5 KB) and loads with
  `defer` from `layout.html`.
- **Two `:root` blocks only.** `tools/build_site.py` `contrast()` unpacks exactly two `:root { }` blocks, light then
  dark; a third one crashes `--check`. New tokens go into the existing two blocks. Any other override uses `html`
  or a class.
- `data-theme` and `localStorage` fail `--check`. Dark and light come from `prefers-color-scheme` only.

**Apps**

- **Zero CPU when idle.** Springs settle and stop. `repeatForever`, a `phaseAnimator` without a trigger, and
  `TimelineView` appear only inside views that exist only while work runs: Whydunit's first-scan view and Tirekick's
  "Checking this Mac…" view.
- Use only `.animation(_:value:)`, never unscoped `.animation`. Call `withAnimation` only in event handlers and
  `onAppear`.
- **3D on content only.** Never add 3D to a `Table` or `List` row container: AppKit owns the cell, its clipping and
  its selection.
- `ImageRenderer` paths get no effects inside the rendered view. Tirekick's `ReportCardView` is the PNG.
- No `drawingGroup()` over text: it rasterizes, and the text blurs at 3D angles.
- Hover state lives in the modifier (`@State`), never in `AppStore` or `AppModel`. Keep at most 8 `HoverTilt`
  views on screen at once; plain `onHover` rows are cheap and don't count.
- Written, not compiled: none of the Swift in this file has been built. Mark every API you can't confirm with
  `VERIFY`.

### 1.7 Shared web code (prototype-tested in Chromium on Windows, 2026-09-28)

**Tokens.** Append these to the **existing** light `:root` block:

```css
  /* Motion and depth (docs/MOTION.md §1). Only these two :root blocks: build_site.py contrast() reads exactly two. */
  --ease-out: cubic-bezier(.16, 1, .3, 1);
  --ease-spring: cubic-bezier(.34, 1.56, .64, 1);
  --ease-in-out: cubic-bezier(.65, 0, .35, 1);
  --t-fast: .16s;
  --t-base: .32s;
  --t-slow: .7s;
  --t-hero: 1.1s;
  --persp-scene: 1600px;
  --persp-card: 900px;
  --z1: 0 1px 2px rgb(0 0 0 / .06), 0 4px 12px rgb(0 0 0 / .05);
  --z2: 0 2px 6px rgb(0 0 0 / .06), 0 12px 32px rgb(0 0 0 / .1);
  --glare: rgb(0 102 204 / .07);   /* white can't shine on white: a faint accent spotlight instead */
```

Then append these to the existing dark `:root` block:

```css
    --z1: 0 0 0 1px rgb(255 255 255 / .06), 0 4px 12px rgb(0 0 0 / .5);
    --z2: 0 0 0 1px rgb(255 255 255 / .08), 0 12px 32px rgb(0 0 0 / .6);
    --glare: rgb(255 255 255 / .1);
```

**Shared rules.** Append these to `styles.css`, and delete the old
`@media (prefers-reduced-motion: no-preference) { .button { transition: background-color .2s; } }` line, which the
button rule below replaces. The block adds about 3 KB.

```css
/* Motion (docs/MOTION.md). Everything above is the finished, still page; movement only under no-preference.
   Animate transform, translate, rotate, scale and opacity only. Never opacity, overflow, filter or clip-path on a
   transform-style: preserve-3d element: they flatten its 3D. */
[data-tilt] { --px: 0; --py: 0; }
.stage { --tilt: 5deg; perspective: var(--persp-scene); }
.scene { position: relative; transform-style: preserve-3d; }
.grid { perspective: var(--persp-scene); }
.card[data-tilt] { --tilt: 7deg; position: relative; isolation: isolate; overflow: hidden; }
/* Glare: a 200% spotlight moved by transform (no repaint), between the card's fill and its text. */
.card[data-tilt]::after {
  content: ""; position: absolute; z-index: -1; inset: -50%; pointer-events: none; opacity: 0;
  background: radial-gradient(circle, var(--glare), transparent 30%);
  transform: translate(calc(var(--px) * 25%), calc(var(--py) * 25%));
}
@media (prefers-reduced-motion: no-preference) and (hover: hover) and (pointer: fine) {
  .scene, .card[data-tilt] {
    transform: rotateX(calc(var(--py) * var(--tilt) * -1)) rotateY(calc(var(--px) * var(--tilt)));
    transition: transform var(--t-slow) var(--ease-out), scale var(--t-base) var(--ease-out);
  }
  .tilting .scene, .card.tilting { transition-duration: var(--t-fast), var(--t-base); }   /* follow fast, settle slow */
  .card.tilting { scale: 1.02; }
  .card[data-tilt]::after { transition: opacity var(--t-base), transform var(--t-fast) linear; }
  .card.tilting::after { opacity: 1; }
}
/* Phones: no pointer, so the hero leans back and straightens as it scrolls into place. */
@media (prefers-reduced-motion: no-preference) and (hover: none) {
  @supports (animation-timeline: view()) {
    .scene { animation: settle linear both; animation-timeline: view(); animation-range: cover 0% cover 45%; }
  }
}
/* Reveal: scroll-driven where supported; motion.js adds .reveal-io and .in elsewhere. */
@media (prefers-reduced-motion: no-preference) {
  @supports (animation-timeline: view()) {
    .reveal { animation: rise linear both; animation-timeline: view(); animation-range: entry 0% entry 75%; }
  }
  .reveal-io .reveal:not(.in) { opacity: 0; }
  .reveal-io .reveal.in { animation: rise var(--t-slow) var(--ease-out) calc(var(--i, 0) * 90ms) backwards; }
  details[open] > p { animation: unfold var(--t-base) var(--ease-out); }
  summary::after { transition: rotate var(--t-base) var(--ease-out); }
  details[open] summary::after { rotate: 180deg; }
  .button { transition: background-color .2s, scale var(--t-fast) var(--ease-out); }
  .button:active { scale: .97; }
}
details { perspective: var(--persp-card); }
@keyframes settle { from { transform: rotateX(12deg) scale(.96); } }
@keyframes rise { from { opacity: 0; translate: 0 32px; rotate: x 10deg; } }
@keyframes unfold { from { opacity: 0; translate: 0 -6px; rotate: x -12deg; } }
@keyframes fade { from { opacity: 0; } }
@keyframes pop { from { opacity: 0; transform: translateZ(0) scale(.8); } }
```

**`site/static/motion.js`** is byte-identical in both repos and loads from `layout.html` right after the stylesheet
link: `<script src="/motion.js" defer></script>`. The build prefixes `src="/`, and `--check` confirms the file
exists. It has three jobs:

1. **Tilt.** Write `--px`/`--py` on the hovered `[data-tilt]` element and toggle `.tilting`. This happens only for
   a mouse, without Reduce Motion, throttled to one rAF per frame. It resets on scroll and when the pointer leaves
   the window.
2. **Reveal fallback.** Where `animation-timeline: view()` is unsupported (Firefox stable), add `.reveal-io` to
   `<html>` and give `.in` to each `.reveal` as it enters, staggered within each batch. Anything already on screen at
   load gets `.in` before the class goes on, so it never flashes.
3. **Flip.** Unhide each `[data-flip]` button and make it toggle `.flipped` on its `aria-controls` target, keeping
   `aria-pressed` in sync.

With no JS, the pages are complete and still. Hero sequences are pure CSS and need no JS.

```js
// Motion for the EverydayOpen sites (docs/MOTION.md). Every page is complete and static without it.
(() => {
  const root = document.documentElement;
  const calm = matchMedia('(prefers-reduced-motion: reduce)');
  const fine = matchMedia('(hover: hover) and (pointer: fine)');

  // Tilt: --px/--py (-1..1 from the center) on the hovered [data-tilt]; CSS turns them into rotation and glare.
  // The box is read once per element entered, so the tilt never feeds back into it.
  let el = null, box, x = 0, y = 0, frame = 0;
  const enter = (t) => {
    if (el) {
      el.classList.remove('tilting');
      el.style.removeProperty('--px');
      el.style.removeProperty('--py');
    }
    el = t;
    if (el) {
      el.classList.add('tilting');
      box = el.getBoundingClientRect();
    }
  };
  const unit = (v, start, size) => Math.max(-1, Math.min(1, (v - start) / size * 2 - 1)).toFixed(3);
  const draw = () => {
    frame = 0;
    if (!el) return;
    el.style.setProperty('--px', unit(x, box.left, box.width));
    el.style.setProperty('--py', unit(y, box.top, box.height));
  };
  addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse' || calm.matches || !fine.matches) return;
    const t = e.target.closest ? e.target.closest('[data-tilt]') : null;
    if (t !== el) enter(t);
    x = e.clientX;
    y = e.clientY;
    if (el && !frame) frame = requestAnimationFrame(draw);
  }, { passive: true });
  addEventListener('scroll', () => el && enter(null), { passive: true });
  root.addEventListener('pointerleave', () => enter(null));

  // Reveal, where CSS scroll-driven animations don't exist yet (Firefox): .in when it enters, staggered per batch.
  const items = document.querySelectorAll('.reveal');
  if (items.length && !calm.matches && !CSS.supports('animation-timeline: view()') && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.filter((e) => e.isIntersecting).forEach((e, n) => {
        e.target.style.setProperty('--i', Math.min(n, 6));
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    items.forEach((e) => (e.getBoundingClientRect().top < innerHeight ? e.classList.add('in') : io.observe(e)));
    root.classList.add('reveal-io');
  }

  // Flip: a [data-flip] button turns the card named by aria-controls over and back.
  document.querySelectorAll('[data-flip]').forEach((b) => {
    const card = document.getElementById(b.getAttribute('aria-controls'));
    if (!card) return;
    b.hidden = false;
    b.addEventListener('click', () => b.setAttribute('aria-pressed', card.classList.toggle('flipped')));
  });
})();
```

### 1.8 Shared SwiftUI code (PROPOSAL, written, not compiled)

Both apps get the same pointer tilt, in `App/DesignSystem/Tokens.swift`. It uses only macOS 13 APIs:
`onContinuousHover` is macOS 13, and `rotation3DEffect`, `RadialGradient` and `mask` are older. **Whydunit** (macOS
15) replaces the `.background(GeometryReader …)` line with
`.onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }`, which avoids the one-argument `onChange`
that is deprecated from macOS 14.

```swift
/// Turns a surface to face the pointer (the edge under it recedes), at most `max` degrees, with an optional glare
/// masked to the content's own shape. Flat under Reduce Motion. The pointer is read in the layout frame, so the
/// tilt never moves hit areas.
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
                    RadialGradient(colors: [.white.opacity(0.28), .clear], center: .center,
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
            .background(GeometryReader { g in
                Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 }
            })
            .onContinuousHover { phase in
                guard !reduceMotion, size.width > 0, size.height > 0 else { return }
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
```

The `Motion` additions (`spring`, `hero`, `pop`, `follow`) are in each app's section, spelled for its deployment
target.

**Sources:** WebKit, "WebKit Features in Safari 26.0" (webkit.org/blog/17333) and "WebKit Features for Safari
26.4" (webkit.org/blog/17862); Firefox's `layout.css.scroll-driven-animations.enabled` flag status (mid-2026
developer guides); Apple docs for `onContinuousHover(coordinateSpace:perform:)` (macOS 13) and
`rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`; SF Symbols 6 effects `wiggle`, `breathe` and `rotate`
(macOS 15; WWDC24 "What's new in SwiftUI"). `keyframeAnimator` is deliberately unused. Nobody has checked whether a
one-shot run rests on the last keyframe or on `initialValue`, and plain `@State` plus a spring does the same job on
every macOS version without that question.

## 2. Overstay website

### 2.1 The story in 2.4 seconds, and the sweep

The room is dark. A door at the left edge opens onto a lit hallway: the light snaps on and pools across the floor.
The laptop on the desk goes dim; its cursor is still there, but nobody is typing. One by one, eight process chips
rise out of the screen and settle on a ring around the laptop, loitering. The menu bar badge turns amber: "183 ·
9.4 GB". The popover deals down from the badge and its Stop button lands. Then the page is still: the pointer tilts
the scene up to 5°, which parallaxes the ring against the laptop and the popover against the bar.

Press **Stop 183**. The chips leave through the door, one after another, and fade in the light. The ring in the
popover shrinks to nothing and a green check takes its place; the header now reads "Stopped 183. 9.4 GB was held.";
the rows dim with their readouts struck through; the badge goes quiet. The button reads **Reset demo** and puts
everything back. The headline, lede and both page buttons never move.

| t (s) | What happens | Element | Easing |
|---|---|---|---|
| 0.00–0.40 | The door light snaps on (`scaleY 0 → 1` from its middle) | `.door` | `--ease-out` |
| 0.10–0.80 | The floor and its pool fade in (opacity on a flat plane) | `.floor` | `--ease-out` |
| 0.15–1.10 | The screen dims: the session's last glow fades from full to the rest state | `.screen::after` | `--ease-in-out` |
| 0.40–1.60 | The chips rise from the laptop's base (radius 0, scale .6, below the ring) to their places on the ring, 90 ms apart | `.tokens li` | `--ease-out` |
| 1.30–1.60 | The badge pops in | `.bar .badge` | `--ease-spring` |
| 1.50–2.20 | The popover deals down from the badge (`translate3d(0, -14px, 60px) scale(.98)`), its front face fades in | `.pop-wrap`, `.pop` | `--ease-out` |
| 2.15–2.40 | The drawn Stop key-cap settles (`scale .96 → 1`) | `.pop-cta` | `--ease-spring` |

**The sweep** (0.9 s, on the button; reversible):

| t (s) | What happens | Element | Easing |
|---|---|---|---|
| 0.00–0.75 | Each chip slides toward the door and shrinks, 60 ms apart (8 chips, so the last leaves at 0.42 s and is gone by 0.9 s); its opacity fades over the last 0.4 s | `.swept .tokens li` | `--ease-in-out` |
| 0.10–0.50 | The ring shrinks to nothing; the green check scales in | `.swept .ring`, `.swept .held svg` | `--ease-out`, `--ease-spring` |
| 0.20–0.60 | "183 leftover · 9.4 GB" fades out as "Stopped 183. 9.4 GB was held." fades in (both in the DOM; `visibility` swaps with the fade) | `.found`, `.held` | `--ease-out` |
| 0.30–0.60 | The rows dim to .45 and their readouts strike through | `.swept .pop-rows li` | `--ease-out` |
| 0.40–0.80 | The badge loses its amber (a `background-color` transition, allowed: not a shadow or filter) | `.swept .bar .badge` | `--ease-out` |

Reset reverses every transition over the same durations: the chips come back in from the door. The label says
"Reset demo", not "Rescan", because a rescan never brings a stopped process back and the page must not suggest it.

### 2.2 DOM

The hero DOM is in DESIGN §4.2. The only motion-related additions: `id="hero-scene"` on `.scene` (the button's
`aria-controls`), `data-sweep="Reset demo"` on the button (the label it toggles to), and the `.held` headline
carrying the check glyph:

```html
<span class="held"><svg aria-hidden="true"><use href="#i-ok"/></svg>Stopped <b>183</b>. <b>9.4</b> GB was held.</span>
```

Every `.card` in the pairing, stop and FAQ sections and the download page's steps: `class="card reveal" data-tilt`.
The slab row in "Stop, politely": `class="slabs reveal" data-tilt`. The ledgers, the proof strip, the FAQ panel and
the filmstrip: `reveal` only, no tilt. `layout.html`: `<script src="/motion.js" defer></script>` after the
stylesheet link.

### 2.3 CSS (append after the shared block in §1.7; about 3.6 KB)

The rest state is written first (DESIGN §4.2); everything below is movement under `no-preference`, plus the sweep's
transitions, which run under Reduce Motion with `transition: none` so the states still swap.

```css
/* Hero (MOTION.md §2): the door light snaps on, the screen dims, the chips rise onto the ring, the badge pops, the
   popover deals down. Opacity sits on flat elements only: .floor, .screen::after, .tokens li, .badge, .pop (never on
   .scene, .mac, .tokens or .pop-wrap, which are preserve-3d or hold a 3D child). */
.tokens li { transform: rotateZ(var(--a)) translateX(var(--r)) rotateZ(calc(var(--a) * -1)) rotateX(-72deg) translate(-50%, -50%) scale(1); }   /* the rest transform, with scale(1) so the rise and the sweep interpolate per function */
@media (prefers-reduced-motion: no-preference) {
  .door { animation: door .4s var(--ease-out) backwards; transform-origin: 50% 50%; }
  .floor { animation: fade .7s var(--ease-out) .1s backwards; }
  .screen::after { animation: dim .95s var(--ease-in-out) .15s backwards; }
  .tokens li { animation: rise .9s var(--ease-out) backwards; }
  .tokens li:nth-child(1) { animation-delay: .40s; } .tokens li:nth-child(2) { animation-delay: .49s; } .tokens li:nth-child(3) { animation-delay: .58s; } .tokens li:nth-child(4) { animation-delay: .67s; }
  .tokens li:nth-child(5) { animation-delay: .76s; } .tokens li:nth-child(6) { animation-delay: .85s; } .tokens li:nth-child(7) { animation-delay: .94s; } .tokens li:nth-child(8) { animation-delay: 1.03s; }
  .bar .badge { animation: pop .3s var(--ease-spring) 1.3s backwards; }
  .pop-wrap { animation: deal .7s var(--ease-out) 1.5s backwards; }
  .pop { animation: fade .5s var(--ease-out) 1.5s backwards; }
  .pop-cta { animation: settle-cap .25s var(--ease-spring) 2.15s backwards; }
  /* The sweep's transitions. */
  .tokens li { transition: transform .75s var(--ease-in-out), opacity .4s var(--ease-out) .35s; }
  .swept .tokens li:nth-child(2) { transition-delay: .06s, .41s; } .swept .tokens li:nth-child(3) { transition-delay: .12s, .47s; } .swept .tokens li:nth-child(4) { transition-delay: .18s, .53s; }
  .swept .tokens li:nth-child(5) { transition-delay: .24s, .59s; } .swept .tokens li:nth-child(6) { transition-delay: .30s, .65s; } .swept .tokens li:nth-child(7) { transition-delay: .36s, .71s; } .swept .tokens li:nth-child(8) { transition-delay: .42s, .77s; }
  .ring { transition: transform .4s var(--ease-out) .1s; }
  .held svg { transition: transform .4s var(--ease-spring) .2s; }
  .found, .held { transition: opacity .4s var(--ease-out) .2s, visibility 0s .2s; }
  .pop-rows li { transition: opacity .3s var(--ease-out) .3s; }
  .bar .badge { transition: background-color .4s var(--ease-out) .4s, color .4s var(--ease-out) .4s; }
}
/* The swept state (rest state of the sweep; applies with or without motion). */
.swept .tokens li { transform: rotateZ(var(--a)) translateX(var(--r)) rotateZ(calc(var(--a) * -1)) rotateX(-72deg) translate(-50%, -50%) scale(.7) translate3d(-520px, 0, 0); opacity: 0; }
.swept .ring { transform: scale(0); }
.held svg { width: 28px; height: 28px; color: var(--ok); transform: scale(0); }
.swept .held svg { transform: scale(1); }
.swept .found { opacity: 0; visibility: hidden; }
.swept .held { opacity: 1; visibility: visible; }
.found, .held { opacity: 1; }
.held { opacity: 0; }
.swept .pop-rows li { opacity: .45; }
.swept .pop-rows code { text-decoration: line-through; }
.swept .bar .badge { background: var(--pop-row); color: var(--bar-text); }
.swept .pop-cta { visibility: hidden; }   /* the real button sits over it; its label now says Reset demo */
@keyframes door { from { transform: translateZ(-220px) scaleY(0); } }
@keyframes dim { from { opacity: 1; } }
@keyframes rise { from { opacity: 0; transform: rotateZ(var(--a)) translateX(0) rotateZ(calc(var(--a) * -1)) rotateX(-72deg) translate(-50%, 40%) scale(.6); } }
@keyframes deal { from { transform: translate3d(0, -14px, 60px) scale(.98); } }
@keyframes settle-cap { from { transform: scale(.96); } }
```

Notes:

- **Custom properties inside keyframes.** `rise` reads each chip's `--a`, so one keyframe rule serves eight chips.
  Chromium and Safari resolve `var()` in keyframes per element; VERIFY in Firefox (expected fine since Firefox 57).
- **Per-function interpolation.** The rest transform and the sweep transform share the same function list in the
  same order, so the browser interpolates each function rather than falling back to a matrix decomposition (which
  would spin the chip). Never reorder them.
- **`.found`/`.held` share one grid cell** (`.held` is absolutely positioned over `.found`, DESIGN §4.2), so the
  swap moves nothing; CLS stays 0.
- **Reduce Motion:** every animation is inside `no-preference`; the `.swept` rules are outside it, so the button
  still swaps states, instantly.
- **The badge's `background-color` transition** is the one colour transition on the page. It is not a shadow or
  filter (§1.6), and it is a state swap, not an idle effect.
- **At 360px** the laptop and the ring are hidden (DESIGN §4.2), so the sweep is the popover's header, rows and
  badge only. There is no horizontal scroll.

### 2.4 `motion.js`: the shared file plus the sweep

`site/static/motion.js` is the shared §1.7 script with this fourth job appended before the closing `})();`
(about 540 bytes; the file stays under 6 KB). With no JS the hero is complete and still in the found state and the
button stays hidden.

```js
  // Sweep (Overstay only): the hero's Stop button sends the chips out through the door; the same button resets it.
  document.querySelectorAll('[data-sweep]').forEach((b) => {
    const scene = document.getElementById(b.getAttribute('aria-controls'));
    if (!scene) return;
    const stop = b.textContent, reset = b.getAttribute('data-sweep');
    b.hidden = false;
    b.addEventListener('click', () => {
      const on = scene.classList.toggle('swept');
      b.setAttribute('aria-pressed', on);
      b.textContent = on ? reset : stop;
    });
  });
```

The button is a real `<button>` with `aria-pressed`, hidden until JS runs, absolutely positioned over the drawn
key-cap so showing it moves nothing. Hover never sweeps (people move the mouse over the popover to read it; the
Tirekick §4.4 argument applies unchanged).

### 2.5 Sections and sub-pages

| Section | Motion |
|---|---|
| Hero text, lede, both buttons, trust line | none (LCP: the h1) |
| Hero scene | §2.1 once, then tilt 5° (fine pointers) or scroll lean (phones); the sweep on the button |
| Pairing (Activity Monitor vs Overstay), FAQ, download steps | reveal plus 7° tilt, glare and scale 1.02 on the `.card`s |
| Stop, politely (the slab row) | reveal; 5° tilt on the whole row; slabs never move individually (the collapse belongs to the app) |
| Proof strip, ledgers, receipts, filmstrip | reveal only (text and data stay still) |
| FAQ | answer unfolds; "+" turns into "×" |
| Buttons | press sinks 1px, shadow swapped |
| Finale | the icon on the floor with its reflection; `data-tilt` 8° on the icon only |
| Safety, how-it-decides, changelog, 404, llms.txt | no motion beyond reveal and the `--z1` shadow on `pre` and `.summary`; they print |

## 3. Overstay app (macOS 13 deployment, SwiftUI; written, not compiled)

BUILD_PLAN §8: one signature animation (the collapse), everything else a plain fade, all off under Reduce Motion,
nothing moving at idle. This section says exactly where each of those lives. Every API is macOS 13 unless it sits in
`App/DesignSystem/Compat.swift` behind `if #available`.

### 3.1 Tokens (`App/DesignSystem/Tokens.swift`)

Tirekick's `Motion` (`standard`, `spring`, `hero`, `pop`, `follow`), `HoverTilt`, `AnyTransition.flip` and
`FlipFaces` verbatim (§1.8, Tirekick MOTION §5.1), plus one constant:

```swift
extension Motion {
    /// Stagger between slabs in the collapse and between rows flipping in. Capped at index 8, so a long list never trickles.
    static let stagger = 0.045
}
```

### 3.2 The collapse: the one signature animation

`AppModel.phase == .running(plan, finished:)` drives it. `finished` is the number of `TargetOutcome`s reported so
far; the plan's targets are in signalling order (leaf-first). The groups view derives which slabs have settled:

```swift
/// A group's slab settles when every one of its targets has reported (stopped, survived, skipped or refused: the
/// slab shows that Overstay is done with it, not that memory is free). Honest timing: slabs settle as outcomes
/// arrive, never on a fake schedule.
func settledGroups(_ plan: StopPlan, finished: Int, groups: [LeftoverGroup]) -> Set<String> {
    let done = plan.targets.prefix(finished)
    return Set(groups.filter { g in
        let mine = plan.targets.filter { $0.agent == g.agent && $0.projectName == g.project?.name }
        return !mine.isEmpty && mine.allSatisfy { t in done.contains { $0.id == t.id } }
    }.map(\.id))
}
```

`WeightBar(groups:selected:settled:)` (DESIGN §6.3) animates each slab's `settled` with `Motion.spring` delayed by
`min(index, 8) × Motion.stagger`: the slab sinks 6pt, scales to .96 from its bottom edge and fades. Five slabs
settle inside 0.9 s of the last outcome. Under Reduce Motion: `Motion.spring(true)` is a 150 ms linear fade and the
delay is 0, so the slabs simply fade. After `.result`, the rescan replaces the bar's data; slabs that are gone are
gone, and the remaining ones re-lay out with `Motion.spring` (a `.animation(_:value:)` on `groups.map(\.id)`).

The `Metric("Leftover", "183")` above the bar counts down with `.contentTransition(.numericText())` (macOS 13) under
`.animation(Motion.standard(reduceMotion), value: finished)`: it shows `plan.targets.count - finished`, which is
what remains to be reported, not a promise of what stopped. The result sheet shows the real outcome.

### 3.3 The popover: the ring shrinks

`OrbitRing(groups:progress:)` (DESIGN §6.3) takes `progress = 1 - Double(finished) / Double(max(1, plan.targets.count))`
with `.animation(Motion.standard(reduceMotion), value: finished)`. `Canvas` redraws per value; nothing loops. When
`.result` arrives the ring is replaced by the green `checkmark.circle.fill` with `.transition(.opacity)` and, on
macOS 14+, one `.bounce(on:)`. The number beside it uses the same `numericText` countdown as §3.2. VERIFY that
`Canvas` inside a `MenuBarExtra` window redraws smoothly on macOS 13 under rapid `finished` changes; if it stutters,
drop the countdown and swap the ring for the check at the end.

### 3.4 Entrances (one per screen, then stillness)

| Screen | Entrance | Length |
|---|---|---|
| First run | the icon rises 24pt and fades in on `OnFloor`, `Motion.hero` after 0.1 s; then `HoverTilt(max: 8, glare: true)` | ≤ 1 s |
| Popover | none: it must be instant; the ring is simply drawn | 0 |
| Main window, groups | the weight bar's `.surface` appears with `.transition(.flip(reduceMotion))` once per scan result (`.id(scan.scannedAt)`); the sidebar rows are a system `List` and get no transition | ≤ 0.5 s |
| Group detail | process rows flip in (`.flip`) on the 45 ms stagger, cap 8, once per load | ≤ 0.8 s |
| Confirm sheet | the system sheet animation only | system |
| Result sheet | the share-card preview is dealt with `FlipFaces(angle: dealt ? 0 : 180, back: CardBack())` under `Motion.spring`, once per sheet; then `HoverTilt(max: 4, glare: true)` | ≤ 0.5 s |
| Activity, Preferences, edge states | none | 0 |

`CardBack` is the night room with the mark, no text (nothing to read or miss while it turns). Under Reduce Motion
every entrance is `Motion.standard(true)`: a 150 ms fade, no movement, no tilt, no flip.

### 3.5 Hover, press and selection

- `AmberButtonStyle` and `KeyCapStyle` sink 1–2pt on press with `Motion.pop`; shadows are constant per state and
  never animated (§1.4).
- A slab toggles selection with `Motion.pop`: it lifts 2pt and its rim turns amber. The amber shadow is a constant
  per state (selected or not) and swaps without a transition.
- `HoverTilt` is used on exactly three views in the whole app (first-run icon, result share card, and the detail's
  `terminal()` argv well gets none): never on list rows, the weight bar, the popover or sheets.
- Hover state lives in the modifier's `@State`, never in `AppModel`.

### 3.6 What doesn't move, and why

- The menu bar icon and badge never animate: the badge appears and disappears with the scan result, as system
  status items do. A pulsing menu bar item would be the "alarm" §1.1 rule 3 forbids.
- The quiet state is still: a green check and a sentence. Calm is the resolution, not a celebration.
- The confirm sheet is still. People read it before stopping processes they can't bring back.
- The process tree, the activity table and the preferences form are system parts; AppKit owns their cells.
- Nothing in the share card view moves (`ImageRenderer` draws it); decoration sits outside it on the result sheet.
- No loop anywhere except the system `ProgressView` while a scan or a stop runs.
- **Not doing:** an orbit that rotates; a `matchedGeometryEffect` from the popover rows to the main window (two
  windows, two scenes: simpler apart); keyframe or phase animators; glass on content; symbol effects beyond the one
  bounce on macOS 14+.

## 4. Budgets, acceptance and how to verify without a Mac

### 4.1 Budgets

| Website item | Hard cap | Measure |
|---|---|---|
| `site/static/styles.css` | 40 KB | `wc -c`; `BUDGET` in `build_site.py` |
| `site/static/motion.js` | 6 KB (shared 2.7 KB + the sweep ≈ 0.55 KB) | `wc -c`; `diff` against Tirekick's shows only the appended job |
| Webfonts, CDNs, third-party requests, trackers | 0 | the Network panel on a cold load |
| Home HTML (built) | 36 KB | `wc -c site/_dist/index.html` |
| Home first load, uncompressed (HTML + CSS + JS + icon + favicon) | 110 KB | sum of the above |
| Hero sequence | ≤ 2.4 s, once; ≤ 4 planes | §2.1 table |
| The sweep | ≤ 0.9 s per press; reversible | §2.1 table |
| CLS / LCP | 0 / the h1 | the siblings' §6.3 snippets |

| App item | Budget |
|---|---|
| CPU after any entrance settles (first run, popover, groups, detail, result) | 0% in Activity Monitor within 2 s |
| Loops | only the system `ProgressView` while a scan or a stop runs |
| The collapse | ≤ 1 s for the whole bar after the last outcome; per-slab spring 0.45 s on a 45 ms stagger |
| Entrance lengths | first-run icon ≤ 1 s; detail row flips ≤ 0.8 s; share card deal ≤ 0.5 s |
| `HoverTilt` views on screen | ≤ 2 (first run: 1; result: 1) |
| macOS 13 | every API outside `Compat.swift` is macOS 13 |
| New files | `App/DesignSystem/{Tokens,Compat,Slab,WeightBar,MenuBarIcon}.swift`; no assets beyond the icon set, no dependencies |

### 4.2 Acceptance checklist

**Website, all pages**

- [ ] `python tools/build_site.py --check` passes: links (including `/motion.js`), one `<h1>`, alt text, contrast with
      exactly two `:root` blocks, no `data-theme`/`localStorage`, no inline style or script, the exact CSP, budgets.
- [ ] With Reduce Motion: the found state is simply there (door lit, chips on the ring, popover open); nothing rises,
      deals or tilts; pressing Stop 183 swaps to the swept state instantly and Reset demo swaps back.
- [ ] With JavaScript off: the page is complete and still in the found state, the real button stays hidden and the
      drawn key-cap is visible.
- [ ] Light and dark are right: a warm paper room by day, a warm near-black room at night; the door light is amber in
      both; the laptop keeps its fixed colours; the popover follows the scheme.
- [ ] At 360×740: no horizontal scroll; the laptop and ring are hidden; the bar and popover stack; the sweep still
      changes the header, rows and badge.
- [ ] Firefox shows the reveal fallback and the chips' `rise` keyframe with per-element `--a`. Print of the safety
      page shows dark text on white, no shadows, no motion artifacts.
- [ ] Performance: no long task from `motion.js`, no layout or paint while tilting or sweeping (only compositor
      properties plus the one `background-color` transition on the badge).

**Website, hero**

- [ ] The door light snaps on, the floor pools, the screen dims, eight chips rise onto the ring one by one, the badge
      pops, the popover deals down and its Stop key-cap settles. The page is still after about 2.4 s.
- [ ] Stop 183 sends the chips out through the door, left to right in order, the ring shrinks to a green check, the
      header reads "Stopped 183. 9.4 GB was held.", the rows dim with struck readouts, the badge goes quiet, and the
      button reads "Reset demo" with `aria-pressed="true"`. Keyboard (Tab, Space, Enter) and tap both work; hover
      never sweeps.
- [ ] The headline, lede, both page buttons and the trust line never move.

**App** (on a Mac, or in CI once it compiles)

- [ ] First run: the icon rises once and tilts up to 8° with glare; Continue sinks on press.
- [ ] Popover: opens instantly with the ring drawn; during a stop the ring shrinks and the number counts down; at the
      end the green check replaces the ring (one bounce on macOS 14+). Quiet state: no amber, nothing moves.
- [ ] Groups: the weight bar flips in once per scan; slabs lift on selection; during a stop each slab settles as its
      targets report, the last within 1 s; after the rescan the survivors re-lay out with a spring.
- [ ] Detail: rows flip in once; Details discloses without motion beyond the system's.
- [ ] Result: the share card is dealt once, then tilts up to 4° with glare; Save as PNG is byte-for-byte unaffected
      by the decoration (compare a PNG saved before and after any change outside `ShareCardView`).
- [ ] macOS 13: everything works without the Compat touches. Reduce Motion: fades only; no tilt, no flip, no sink,
      no stagger. VoiceOver: the weight bar reads each slab's title, size, count and selection; the countdown is not
      announced on every change (`.accessibilityValue` updates only at the end).

### 4.3 How to verify without a Mac

```sh
python tools/build_site.py --check
wc -c site/static/styles.css site/static/motion.js
diff <(head -c 2700 site/static/motion.js) ../tirekick/site/static/motion.js   # only the appended job may differ
python tools/build_site.py && python -m http.server 8767 --directory site/_dist   # open http://localhost:8767/overstay/ after copying under that prefix
```

- **Chromium:** DevTools Rendering › emulate `prefers-reduced-motion` and `prefers-color-scheme`; the 360px device
  toolbar; `document.getAnimations()` to step the hero; a `PerformanceObserver` for `layout-shift` and
  `largest-contentful-paint`; the Performance panel while pressing Stop 183 (no Layout or Paint entries beyond the
  badge's colour).
- **Firefox on Windows** covers the reveal fallback and `var()` in keyframes. **Safari** needs the owner's Mac.
- **App, by review until CI compiles it:**

```sh
grep -rn "#available" App/ | grep -v DesignSystem/Compat.swift                                                     # nothing
grep -rn "symbolEffect\|phaseAnimator\|keyframeAnimator\|visualEffect\|\.smooth(\|spring(duration" App/ | grep -v Compat.swift   # nothing
grep -rn "repeatForever\|TimelineView" App/                                                                       # nothing (the only loop is the system ProgressView)
grep -n "rotation3DEffect\|HoverTilt\|FlipFaces\|shadow\|material" App/Share/ShareCardView.swift                  # nothing: the PNG stays clean
grep -rn "\.animation(" App/ | grep -v "value:"                                                                   # nothing
grep -rn "HoverTilt(" App/ | wc -l                                                                                # 2
```

- Then the macOS CI build is the first compile. Until it is green, call the app code "written, not compiled".

### 4.4 Proposals for other owners (not made here)

- **site (`site/**`):** §2.2–§2.5; `motion.js` = the shared file plus §2.4's job; the `#i-ok` and `#i-mark` sprite
  symbols.
- **infra (`tools/build_site.py`):** `BUDGET["motion.js"] = 6_000`; in CI run the §4.3 app greps as failures.
- **app-shell (`PopoverView`, `FirstRunView`, `MainView`):** §3.3's ring countdown and check swap; §3.4's first-run
  entrance and the weight bar's flip-in.
- **app-content (`GroupsView`, `GroupDetailView`, `ResultSheet`):** §3.2's `settledGroups` and the `WeightBar`
  binding; §3.4's row flips and the share card deal.
- **architect (BUILD_PLAN §7, frozen):** add "Motion: docs/MOTION.md; design: docs/DESIGN.md" to §7, and note that
  `.running(plan, finished:)` is enough for the collapse (no per-target outcome list is needed in `AppModel`).

**VERIFY (on a Mac or in Safari):** the ring's chips in Safari (counter-rotation inside a rotated plane); `var()` in
`@keyframes` in Firefox; the per-function transform interpolation on the sweep in all three engines; `Canvas` in a
`MenuBarExtra` window under rapid redraws on macOS 13; `.contentTransition(.numericText())` with fast changes;
`FlipFaces` and `HoverTilt` signs; `Motion.spring` delays on `.animation(_:value:)` with per-slab offsets.
