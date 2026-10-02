# Design spec: Overstay (website and app)

**Why:** Overstay is EverydayOpen's third app and must read as a sibling of Whydunit ("Daylight", light, a desktop
diorama) and Tirekick ("Night Bay", dark, an inspection bay) while having its own world. The bar is the family's
reference set (Maccy, Rectangle, VoiceInk, Recordly, Mole, MaCursor): a real product object inside a small world with
one light source, on a page that is otherwise quiet.
**Authority:** this file is authoritative for visual design (tokens, surfaces, compositions, type, icon).
`docs/MOTION.md` is authoritative for motion and is referenced by section. BUILD_PLAN (§8 UI rules, §7 screens, §9
demo) is the contract; where this file wants a BUILD_PLAN or copy change it is listed in §9, not made.
**Shared system:** §1.1 (the eight rules), §2.3–§2.7 (web foundation) and §6.1 (`surface`, `OnFloor`, `Horizon`,
`Metric`, `Tag`, `KeyCapStyle`, `HoverTilt`) are the same mechanics as the Whydunit and Tirekick `docs/DESIGN.md`
§1–§3; copy fixes to all three. Everything else here is Overstay's.
**Status:** nothing in this file has been built. Every contrast figure was computed with `tools/build_site.py`'s
own `contrast()` formula (`<scratchpad>/overstay_contrast.py`, 2026-10-02). The Swift is written, not compiled, and
no Mac has run it; anything unconfirmed is marked VERIFY.

## 1. The verdict: "Last Call"

The theme is guests who overstayed. The world is **a room after the party**: late, dark, warm. The laptop on the
desk has gone dim, but the processes the session left behind are still there, loitering in a loose orbit around it.
A door at the edge of the room stands ajar with the hallway light on, and that light is the only light source in the
scene. Overstay sends the stragglers out through that door; when the room is empty it is calm and the light stays.
That one picture gives every surface its colour (amber = the hallway light = "leftover"), its motion (the sweep to
the door) and its resolution (the quiet state is dim, still, green-checked, not celebratory).

| | Whydunit | Tirekick | **Overstay** |
|---|---|---|---|
| Direction | Daylight (light-first) | Night Bay (dark on every page) | **Last Call** (dark-first, follows the system; a true light mode, "the morning after") |
| World | a macOS desktop diorama | an inspection bay with a floor grid | **a desk at night**: a dimmed laptop, a ring of loitering process tokens, a drawn menu bar with the amber badge, the popover hanging from it, and a door ajar at the edge |
| Key light | the dawn glow on the horizon | one lime laser | **the door light**: a warm vertical slab at the edge of the scene with a soft spill across the floor |
| Accent | sky blue | hi-vis lime | **amber** `#F2A93B` with near-black text; green only for "All quiet"; red only on a refused row's symbol |
| Type voice | Inter Display, centered, rounded numerals | Inter Display, left, mono readouts | **system display face, no webfont** (§2.2); left-aligned hero; **rounded numerals** for totals and counts, mono only for pids, paths and argv |
| Signature object | the window on the wallpaper | the paper report card | **the weight bar of slabs** (main window) and **the orbit ring** (popover and site): the same groups, two readings |
| Signature motion | the notification lands | the beam sweeps the card | **the sweep**: tokens leave through the door, slabs settle and fade, the counter runs to 0 |
| Radii | 8/12/18/28, pills | 6/10/14/20, 12px buttons | **7/11/16/24**, 11px buttons: softer than Tirekick's machined corners, firmer than Whydunit's pills |

**Decided, in this brand:**

1. **No webfont.** The owner's brief for Overstay caps the site at "CSS ≤ 40 KB, JS ≤ 6 KB, no webfont". The
   headline uses the system display face at weight 600 with tight tracking (§2.2). On Windows this renders in
   Segoe UI Variable Display (Win 11) or Segoe UI Semibold (Win 10), which is the trade-off the brief accepts; §9
   lists it as a lead decision because it reverses the siblings' decision 1.
2. **The site follows the system scheme** (like Whydunit, unlike Tirekick) because the app has a true light mode
   and BUILD_PLAN §8 asks for one. The dark palette is the one designed first and the one on every screenshot and
   the OG image.
3. **The tokens are the app's own objects, not orbs.** Rule 5 (§1.1) bans "cartoon clouds, orbs or glossy coins".
   The brief asks for "tokens/orbs" in orbit; the tokens are therefore **process chips** drawn exactly like a row of
   the app's group detail (a mono executable name, a rounded size), standing on an elliptical ring in 3D. They are
   faithful Mac objects, and the ring reads as an orbit without a sphere in sight.
4. **The orbit never rotates at idle.** "Orbit" is an arrangement, not an animation (MOTION §1.1 rule 2, §1.6). It
   moves once on arrival, once on the sweep, and with the pointer tilt.
5. **The sweep is a real button on the page.** The hero's replica "Stop 183" is a `<button>` that plays the sweep
   and turns into "Rescan" (MOTION §2.4), the same mechanic as Tirekick's flip button: keyboard, tap and click,
   `aria-pressed` in sync, hidden without JS, instant under Reduce Motion. It is the one piece of Overstay-specific
   JS and the reason the JS cap is 6 KB, not 5.
6. **Glass only on the controls layer** (`barSurface()`, §6.2): the popover's bottom bar and the main window's
   selection bar. Content sits on porcelain surfaces; the weight bar's slabs are opaque.
7. **Vendor logos never ship.** Agent groups get neutral SF Symbols (§6.4); the site draws the same glyphs inline.

**Not doing:** a CDN, a tracker, any font file, a live star count, autoplay video, mesh blobs, gradient text, emoji
icons, glass on content, a nav CTA that hides itself, `style=""` attributes, `data-theme`, a rotating orbit, a
"memory freed" number, a red anything that is not a refused row's symbol.

### 1.1 The eight rules (shared with the siblings)

1. **One world per product, and it appears only behind objects:** the hero scene, the "stop" section's media well,
   the finale and the download page's icon. Every other section is paper (light) or graphite (dark), paced by
   whitespace.
2. **One key light per scene.** Overstay's is the door light. Nothing else glows, and a glow is never severity- or
   tier-coloured (MOTION §1.1 rule 3): a Maybe is lit exactly like a Ghost.
3. **Light, not lines.** Every raised surface has a lit top edge (`inset 0 1px 0`), a 0.5px hairline (a 1px light
   rim in dark, because black swallows shadows) and a shadow tinted with the brand's ink (warm brown-black), never
   neutral grey, never animated (MOTION §1.4).
4. **One accent.** Amber means "leftover" and is the only accent. Green and red mean a status and appear only in 6px
   dots, symbols and tag fills behind primary text. A tier never gets a coloured panel: a Maybe row is set exactly
   like a Ghost row, and the word in the chip tells them apart.
5. **Objects, not illustrations.** Every product visual is a faithful Mac object: a menu bar, a popover, a window, a
   sheet, a process row, the laptop. No clouds, orbs or coins (see decision 3).
6. **Everything you can press is a key-cap:** a gradient lighter at the top, a lit rim, a hairline, a shallow side
   wall, and a press that sinks 1–2px with the shadow swapped instantly (never transitioned).
7. **Concentric radii:** outer radius = inner radius + padding. Overstay 7/11/16/24 and 11px buttons. Grain (≤ 6%,
   inline SVG) only on the room gradients, never under body text.
8. **The apps stay native.** `MenuBarExtra`, `NavigationSplitView`, `List`, sheets, the toolbar are system parts.
   Premium comes from the room wash, porcelain surfaces, one lifted object per screen, the amber, the tags, the
   key-caps and the precision of the type. Nothing moves at idle.

## 2. Web foundation

### 2.1 The contract with `tools/build_site.py`

- `contrast()` reads exactly two `:root { }` blocks and only 6-digit hex tokens: light first, then
  `@media (prefers-color-scheme: dark)`. It measures `--text`, `--text-2`, `--accent` on `--bg`, `--bg-alt`,
  `--card`, and `--on-button` on `--button` and `--button-hover`. Every other override sits on `html[lang]`
  (§2.7), never on a third `:root`.
- Hero copy sits on `--bg` (the room is behind objects only), so no new pairs are needed. The popover replica
  (`--pop-*`), the laptop and the tokens are `aria-hidden` or `role="img"` pictures, not measured.
- `data-theme` and `localStorage` must not appear anywhere, including comments. No `style=""` (stagger and ring
  angles use `:nth-child`).
- The CSP is Tirekick's exact string, unchanged, in `layout.html` and the `CSP` constant:
  `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; form-action 'none'`.
  `font-src 'self'` stays for parity across the three repos even though Overstay ships no font file.
- `BUDGET` in `build_site.py` (infra): `styles.css` 40 000, `motion.js` 6 000, `index.html` 36 000, `shots/*`
  110 000; no `fonts/*` entry (none ship; a font file appearing is itself a `--check` error: infra adds the glob).

### 2.2 Type: the system display face, no webfont

```css
--font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI Variable Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI Variable Display", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-num: ui-rounded, "SF Pro Rounded", var(--font);
--font-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, "Cascadia Mono", Consolas, monospace;
```

**Type ladder.** Put this comment at the top of `styles.css`; no size outside it.

```css
/* Type ladder (docs/DESIGN.md §2.2). Display = var(--font-display) 600; numerals = var(--font-num) 600 tabular;
   everything else = var(--font). No webfont: the ladder is tuned so SF Pro Display and Segoe UI Variable both hold it.
   h1       display  clamp(2.75rem, 1.5rem + 4.6vw, 5rem)     / 1.02, -.034em, text-wrap: balance
   h2       display  clamp(2rem, 1.35rem + 2.4vw, 3.125rem)   / 1.06, -.028em, balance
   feature  display  clamp(1.5rem, 1.2rem + 1vw, 2rem)        / 1.12, -.022em
   card h3  system   17px / 1.3, -.015em, 600
   lede     system   clamp(1.125rem, 1rem + .45vw, 1.3125rem) / 1.45, -.012em, --text-2
   body     17px / 1.55, -.011em        small 15px / 1.5        meta 13px / 1.4, 500
   numerals num, tabular-nums: 40px (proof strip), 56px (popover replica total), 64–88px (finale)
   readouts mono 12–13px 500: pids, paths, argv, "61 · 3.1 GB" in rows
   labels   13px 600 with font-variant-caps: all-small-caps and .04em tracking (styling, not ALL CAPS copy)
   eyebrow  12px 500 mono "01 · Leftovers", the index in --accent */
h1, h2, .display, .feature h3, .brand { font-family: var(--font-display); font-weight: 600; }
.num, .proof dd, .pop-head b { font-family: var(--font-num); font-weight: 600; font-variant-numeric: tabular-nums; }
```

Weight 600, never 700. The h1 keeps the family's `<mark>` highlighter on one phrase, in amber (§4.1).

### 2.3 Space, widths and radii

- Widths: `.wrap` 1080px (content), `.wide` 1240px (stages), `.read` 720px (prose, FAQ, the how-it-decides page).
  Gutter 20px, 16px under 480.
- `main > section { padding-block: clamp(72px, 10vw, 136px) }`. Gaps are 12, 16, 24, 32, 48 or 64px.
  `scroll-padding-top: 84px`.
- Radii: `--r-s: 7px; --r-m: 11px; --r-l: 16px; --r-xl: 24px; --r-btn: 11px`.

### 2.4 Light and depth

Every shadow and hairline is the brand's ink at an alpha. `--ink` is warm brown-black (`40 24 8`) in light; in dark
every shadow is black at .5–.8 and the hairline becomes a 1px light rim. Never animate `box-shadow` or `filter`.

| Token | Role | Light recipe |
|---|---|---|
| `--hi` | lit top edge on raised surfaces | `rgb(255 255 255 / .9)`; dark `/ .07` |
| `--z1` | hairline plus contact: rows, pills, the header | `0 0 0 .5px ink/.12, 0 1px 2px ink/.05` |
| `--z2` | porcelain card | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.12, 0 2px 4px ink/.04, 0 12px 28px -12px ink/.16` |
| `--shadow` | a floating object (the popover replica, the share card) | `0 0 0 .5px ink/.22, 0 2px 4px ink/.06, 0 24px 48px -16px ink/.30, 0 64px 128px -32px ink/.34` |
| `--cap` | key-caps (buttons, slabs on the site) | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.18, 0 1px 2px ink/.08, 0 2px 0 var(--cap-side), 0 6px 14px -6px ink/.14` |
| `--slab` | a weight-bar slab: lit top, amber-tinted long shadow | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.16, 0 14px 28px -12px rgb(var(--amber-ink) / .35)` |

### 2.5 Tokens (the two `:root` blocks, ready to paste)

```css
:root {
  color-scheme: light dark;
  /* contrast(), light, worst of bg / bg-alt / card: text 15.39:1, text-2 5.30:1, accent 4.62:1;
     on-button on button 9.54:1, on hover 8.13:1. (Checked with build_site.py's formula, 2026-10-02.) */
  --bg: #faf6ef; --bg-alt: #f2ece2; --card: #ffffff;                   /* warm paper: the morning after */
  --text: #1b1510; --text-2: #6a5f52; --accent: #9a5b00;               /* amber as text needs this depth on paper */
  --button: #f2a93b; --button-hover: #e49a2a; --on-button: #140f08;     /* the amber key-cap, near-black label */
  --line: #e4dccf; --header: rgb(255 252 247 / .74); --hi: rgb(255 255 255 / .9);
  --ink: 40 24 8;                                                       /* warm brown-black: every shadow and hairline */
  --ok: #1a7f37; --bad: #d93025;                                        /* dots and symbols only, never measured text */
  /* The world: a room after the party, in daylight. The door light is the key light; weaker by day. */
  --room-top: #f6efe4; --room-floor: #ebe1d2; --room-ink: 60 36 12;
  --door: #f2a93b; --door-core: #fff1d6; --spill: rgb(242 169 59 / .22); --pool: rgb(242 169 59 / .14);
  --amber: #f2a93b; --amber-ink: 154 91 0; --mark: rgb(242 169 59 / .42);
  --grain: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix values='.33 .33 .33 0 0 .33 .33 .33 0 0 .33 .33 .33 0 0 0 0 0 0 .04'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  /* Key-caps and slabs. */
  --cap-top: #ffffff; --cap-bot: #f4efe6; --cap-side: #d9d0c2;
  --cap: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .18), 0 1px 2px rgb(var(--ink) / .08), 0 2px 0 var(--cap-side), 0 6px 14px -6px rgb(var(--ink) / .14);
  --cap-down: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .18), 0 1px 0 var(--cap-side);
  --slab-top: #fffdf9; --slab-bot: #f3ece1;
  --slab: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .16), 0 14px 28px -12px rgb(var(--amber-ink) / .35);
  --z1: 0 0 0 .5px rgb(var(--ink) / .12), 0 1px 2px rgb(var(--ink) / .05);
  --z2: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .12), 0 2px 4px rgb(var(--ink) / .04), 0 12px 28px -12px rgb(var(--ink) / .16);
  --shadow: 0 0 0 .5px rgb(var(--ink) / .22), 0 2px 4px rgb(var(--ink) / .06), 0 24px 48px -16px rgb(var(--ink) / .30), 0 64px 128px -32px rgb(var(--ink) / .34);
  --glare: rgb(242 169 59 / .08);                                      /* white can't shine on white: an amber spot */
  /* The popover replica and the menu bar strip (role="img", not measured). macOS 13 light materials, opaque. */
  --pop-bg: #f6f3ee; --pop-row: #ffffff; --pop-line: rgb(0 0 0 / .08); --pop-text: #1b1510; --pop-2: #6a5f52;
  --bar-bg: rgb(255 255 255 / .55); --bar-text: #1b1510;
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI Variable Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI Variable Display", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-num: ui-rounded, "SF Pro Rounded", var(--font);
  --font-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, "Cascadia Mono", Consolas, monospace;
  --r-s: 7px; --r-m: 11px; --r-l: 16px; --r-xl: 24px; --r-btn: 11px;
  /* Motion and depth (docs/MOTION.md §1.2, §1.7). */
  --ease-out: cubic-bezier(.16, 1, .3, 1); --ease-spring: cubic-bezier(.34, 1.56, .64, 1); --ease-in-out: cubic-bezier(.65, 0, .35, 1);
  --t-fast: .16s; --t-base: .32s; --t-slow: .7s; --t-hero: 1.1s;
  --persp-scene: 1600px; --persp-card: 900px;
}
@media (prefers-color-scheme: dark) {
  :root {
    /* worst: text 15.26:1, text-2 6.34:1, accent 9.55:1; on-button on button 9.54:1, hover 8.13:1 */
    --bg: #0f0d0b; --bg-alt: #16130f; --card: #1e1a15;                 /* warm near-black, never #000: the room at night */
    --text: #f6f0e6; --text-2: #a79b8a; --accent: #f5b54a;
    --line: #2a2520; --header: rgb(20 17 14 / .76); --hi: rgb(255 255 255 / .07); --ink: 0 0 0;
    --ok: #34d26b; --bad: #ff5a4f;
    --room-top: #14110d; --room-floor: #0b0908; --room-ink: 0 0 0;
    --door: #f2a93b; --door-core: #fff3d8; --spill: rgb(242 169 59 / .26); --pool: rgb(242 169 59 / .12);
    --amber: #f2a93b; --amber-ink: 242 169 59; --mark: rgb(242 169 59 / .34);
    --grain: /* the same SVG with the last matrix value .06 */;
    --cap-top: #2a241d; --cap-bot: #1e1a15; --cap-side: #0a0806;
    --cap: inset 0 1px 0 rgb(255 255 255 / .12), 0 0 0 1px rgb(255 255 255 / .08), 0 2px 0 var(--cap-side), 0 10px 20px -10px rgb(0 0 0 / .8);
    --cap-down: inset 0 1px 0 rgb(255 255 255 / .12), 0 0 0 1px rgb(255 255 255 / .08), 0 1px 0 var(--cap-side);
    --slab-top: #2e2821; --slab-bot: #221d17;
    --slab: inset 0 1px 0 rgb(255 255 255 / .10), 0 0 0 1px rgb(255 255 255 / .08), 0 16px 32px -12px rgb(0 0 0 / .8), 0 10px 24px -14px rgb(var(--amber-ink) / .45);
    --z1: inset 0 1px 0 var(--hi), 0 0 0 1px rgb(255 255 255 / .07), 0 1px 2px rgb(0 0 0 / .6);
    --z2: inset 0 1px 0 var(--hi), 0 0 0 1px rgb(255 255 255 / .08), 0 14px 36px -12px rgb(0 0 0 / .8);
    --shadow: 0 0 0 1px rgb(255 255 255 / .1), 0 24px 48px -16px rgb(0 0 0 / .8), 0 64px 128px -32px rgb(0 0 0 / .9);
    --glare: rgb(255 255 255 / .09);
    --pop-bg: #221e19; --pop-row: #2a251f; --pop-line: rgb(255 255 255 / .08); --pop-text: #f6f0e6; --pop-2: #a79b8a;
    --bar-bg: rgb(0 0 0 / .32); --bar-text: #f6f0e6;
  }
}
```

`layout.html`: `<meta name="color-scheme" content="light dark">`, `theme-color` `#faf6ef` and `#0f0d0b`
(two metas with `media`), no font preload.

### 2.6 Shared components (the same CSS as the siblings; Overstay's tokens)

```css
/* Header pill: 48px, the only backdrop-filter on the page. */
.nav { height: 48px; max-width: 980px; padding: 0 6px 0 14px; border-radius: 999px; background: var(--header);
  -webkit-backdrop-filter: saturate(180%) blur(20px); backdrop-filter: saturate(180%) blur(20px);
  box-shadow: inset 0 1px 0 var(--hi), var(--z1); }
.brand { font-size: 17px; letter-spacing: -.02em; }

/* Section head: editorial, left-aligned; heading left, lede right on wide screens. */
.sec-head { display: grid; gap: 16px 64px; align-items: end; margin-bottom: clamp(40px, 5vw, 64px); }
@media (min-width: 900px) { .sec-head { grid-template-columns: 7fr 5fr; } }
.sec-head h2, .sec-head .lede { margin: 0; }

/* Primary button: an amber key-cap. The fill darkens downward only, so the label keeps its measured contrast. */
.button { border-radius: var(--r-btn); min-height: 48px; padding: 0 22px; font: 600 16px/1 var(--font); color: var(--on-button);
  background: linear-gradient(var(--button), color-mix(in srgb, var(--button) 88%, #000));
  box-shadow: inset 0 1px 0 rgb(255 255 255 / .35), inset 0 -1px 0 rgb(0 0 0 / .18), var(--cap); }
.button.secondary { color: var(--text); background: linear-gradient(var(--cap-top), var(--cap-bot)); box-shadow: var(--cap); }
.button:active { translate: 0 1px; box-shadow: inset 0 1px 0 rgb(255 255 255 / .3), var(--cap-down); }

/* Porcelain card. */
.card { border-radius: var(--r-l); background: var(--card); box-shadow: var(--z2); }

/* Proof strip: hairlines only, no box; rounded numerals. */
.proof { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0; border-block: 1px solid var(--line); }
.proof div { padding: 24px 28px 24px 0; } .proof div + div { border-left: 1px solid var(--line); padding-left: 28px; }
.proof dd { font: 600 clamp(28px, 3.2vw, 44px)/1 var(--font-num); letter-spacing: -.02em; font-variant-numeric: tabular-nums; }
@media (max-width: 720px) { .proof { grid-template-columns: 1fr 1fr; } .proof div:nth-child(odd) { border-left: 0; padding-left: 0; } }

/* Ledger: rules as a spec sheet, with a trailing mono chip. */
.rules { margin: 0; padding: 0; list-style: none; border-top: 1px solid var(--line); }
.rules li { display: grid; grid-template-columns: 1fr auto; gap: 4px 24px; padding: 20px 0; border-bottom: 1px solid var(--line); }
.rules h3 { margin: 0; font: 600 17px/1.3 var(--font); letter-spacing: -.015em; }
.rules p { margin: 0; color: var(--text-2); font-size: 15px; }
.rules code { grid-column: 2; grid-row: 1 / span 2; align-self: center; }

/* FAQ: one grouped panel with hairline rows. "+" turns into "×", no JS. */
.faq-list { border-radius: var(--r-l); background: var(--card); box-shadow: var(--z2); }
.faq-list details { padding-inline: 20px; } .faq-list details + details { border-top: 1px solid var(--line); }
.faq-list summary::after { content: "+"; transition: rotate var(--t-base) var(--ease-spring); }
.faq-list details[open] summary::after { rotate: 45deg; }

/* Real screens: a scroll-snap filmstrip (§2.8). */
.film { display: grid; grid-auto-flow: column; grid-auto-columns: min(560px, 84vw); gap: 24px; overflow-x: auto;
  scroll-snap-type: x mandatory; overscroll-behavior-x: contain; padding: 8px 20px 36px; scrollbar-width: thin; }
.film figure { margin: 0; scroll-snap-align: center; }
.film img { display: block; width: 100%; height: auto; border-radius: 10px; background: var(--pop-bg); box-shadow: var(--shadow); }
.film figcaption { margin-top: 12px; font-size: 13px; color: var(--text-2); }

/* Finale: the app icon standing on a glossy floor by the door. */
.finale .icon { width: 128px; height: 128px; -webkit-box-reflect: below 6px linear-gradient(transparent 62%, rgb(0 0 0 / .22)); }   /* VERIFY inside a 3D parent in Safari */

/* Small-caps labels; tier tags (the word carries the meaning, the dot carries the colour). */
.label { font: 600 13px/1.3 var(--font); font-variant-caps: all-small-caps; letter-spacing: .04em; color: var(--text-2); }
.tag { display: inline-flex; gap: 6px; align-items: center; padding: 2px 9px; border-radius: 999px; font: 600 12px/1.4 var(--font); color: var(--text);
  background: color-mix(in srgb, var(--tag, var(--text-2)) 14%, transparent); box-shadow: 0 0 0 .5px color-mix(in srgb, var(--tag, var(--text-2)) 35%, transparent); }
.tag::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--tag, var(--text-2)); }
.tag.amber { --tag: var(--amber); } .tag.ok { --tag: var(--ok); } .tag.bad { --tag: var(--bad); }
```

### 2.7 Accessibility media

```css
@media (prefers-contrast: more) { html[lang] { --grain: none; --glare: transparent; --spill: transparent; --pool: transparent; }
  .card, details, .nav, .button, .tag, .proof, .faq-list, .note, .pop, .slab { box-shadow: 0 0 0 2px var(--text); } .finale .icon { -webkit-box-reflect: unset; } }
@media (prefers-reduced-transparency: reduce) { .nav { -webkit-backdrop-filter: none; backdrop-filter: none; background: var(--card); } }
@media (forced-colors: active) { .button, .card, details, .tag, .proof div, .nav, .note, .pop, .slab, .tokens li { border: 1px solid CanvasText; } }
@media print { html[lang] { color-scheme: light; --bg: #fff; --bg-alt: #fff; --card: #fff; --text: #000; --text-2: #333; --grain: none; }
  .site-header, .site-footer, .skip, .stage, .finale, .film { display: none; } }
```

`html[lang]` (0,1,1) beats `:root` (0,1,0) and does not match the checker's `:root\s*\{` regex (the siblings' §2.7
bug, fixed from the start here). Also: visible 3px amber focus rings, 44px hit areas, content visible without JS,
every image with `width`/`height`, no `style=""`.

### 2.8 Imagery

- **Hero:** an HTML replica of the popover and a drawn menu bar strip (0 image bytes, sharp at any DPI, follows the
  scheme). Its copy is the `leftovers` demo scenario (BUILD_PLAN §9): "183 leftover · 9.4 GB", Claude Code `~/dev/foo`
  61 · 3.1 GB, Codex `~/dev/bar` 40 · 2.2 GB, Headless browsers 12 · 1.4 GB, "started 3 days ago". Caption:
  "Illustration with sample data." and, as on every page, the not-affiliated line.
- **Real screens** below the fold, at half their pixel width (the siblings' half-scale rule): the main window with
  the weight bar, a group detail, the result sheet; `<picture>` with a dark `<source>`, `loading="lazy"`,
  `decoding="async"`, real `alt`. Ship the section only once `screens.yml` captures are committed to
  `site/static/shots/`.
- The README hero GIF is composited by CI from the demo screens onto the same drawn menu bar strip (BUILD_PLAN §9),
  and the README says so.

## 3. Home page, section by section (11 blocks)

1. **Header pill** (§2.6): 22px icon and wordmark; "How it decides", "Safety", "Download" at 14px/500 `--text-2`;
   a secondary key-cap "Source" and a 36px amber "Download".
2. **Hero: the room** (§4). Left copy, right scene, full-bleed band, no box.
3. **Proof strip** in rounded numerals: "0 · permissions asked", "0 · network calls", "1 · signal, then a 5 s wait",
   "100 % · of stops in the log". The last gets a 6px `--ok` dot, the one LED. (Copy owner confirms wording against
   BUILD_PLAN §8.)
4. **"Activity Monitor shows `node`. Overstay shows who left it."** Two objects: left, a dimmed Activity Monitor-style
   list (five rows, `node`, `node`, `Google Chrome for Testing`, `python3`, `node`, with sizes, `opacity: .6`,
   `--text-2`); right, overlapping it by −30px, the Overstay group card (`.card`, `--shadow`, `data-tilt` 7°): the
   agent glyph, "Claude Code · ~/dev/foo", "61 processes · 3.1 GB · started 3 days ago", a "Leftover" `.tag.amber`,
   and the why line in 13px: "Parent is gone. Looks like an MCP server. No live session in foo." A 1px amber line
   joins the two.
5. **"How it decides."** `.sec-head`, then a 4-item `.rules` ledger with mono chips: "It matches a known agent tool"
   `signature`; "Its parent is gone" `ppid 1`; "No live session owns it" `no session`; "It has been there a while"
   `≥ 10 min`. Under it one line: "Anything that only half fits is a Maybe: shown, never pre-selected, never in a bulk
   stop." A link to the how-it-decides page.
6. **"Stop, politely."** The weight bar as a site object (§4.4 `.slab`): five slabs in a row whose widths are the
   demo footprints, each a key-cap-like raised tile with the group name, the GB and a tiny ring; below it the confirm
   copy as a mono receipt: "SIGTERM first · leaf first · wait up to 5 s · survivors reported · the stronger signal
   only when you ask". No motion here beyond reveal; the sweep lives in the hero.
7. **"What it reads. What it never does."** A two-column `.rules` ledger: left "Reads" (the process table, memory
   footprint, the arguments of matching processes, working folders), right "Never" (no permissions, no network, no
   files touched, no login item, no other users' processes, no undo claims). Honesty is part of the trust.
8. **Real screens.** The `.film` strip (§2.8). Caption: "Real screens, captured by CI from the app with sample data."
9. **FAQ.** Sticky head left (5), the grouped `.faq-list` right (7): "Will this break my build?", "Why not just
   `pkill node`?", "What is a Maybe?", "Is it really free?", "Why is the app unsigned?".
10. **Finale band:** the room again (door light at the left, floor pool), the icon at 176px standing in the pool with
    its reflection, "Send them home. It's free." in display, the amber key-cap, the trust line.
11. **Footer:** the `--bg-alt` slab, a 0.5px ink hairline on top, mono column titles, the version tag, the official
    sources line, and the fixed line "Overstay is not affiliated with or endorsed by any of the tools it detects."

## 4. Hero: the room (the 3D product scene)

### 4.1 Copy, left, 5 of 12 columns (nothing here moves)

Eyebrow `<b>01</b> · Leftover-process finder · macOS 13 or later` in 12px mono, the index in `--accent`; h1
`Your AI agents <mark>overstayed.</mark>`; the lede "Overstay finds the processes Claude Code, Codex and Cursor left
running with nothing attached to them, shows what they hold and which project started them, and sends them home."; the
amber key-cap "Download free" and the secondary "View source"; the mono trust line "Free · No permissions · No
network · Nothing leaves your Mac".

```css
.hero h1 mark { color: inherit; padding: 0 .06em; background: linear-gradient(transparent 56%, var(--mark) 56% 90%, transparent 90%);
  -webkit-box-decoration-break: clone; box-decoration-break: clone; }
```

### 4.2 The scene, right, 7 of 12 columns, no box

The `.hero` section itself is the band: full-bleed, no radius, no border. Back to front: the door (the key light) at
the far left, the floor, the dim laptop centre-left, the ring of tokens around it, the menu bar strip across the top,
the popover hanging from the amber badge at the right.

```html
<section class="hero room" aria-labelledby="hero-h">
  <div class="wide hero-grid">
    <div class="hero-copy">…§4.1…</div>
    <div class="stage" data-tilt>
      <div class="scene" id="hero-scene">
        <i class="door" aria-hidden="true"></i>                                  <!-- Z -220: the key light -->
        <i class="floor" aria-hidden="true"></i>                                 <!-- the plane everything stands on -->
        <div class="mac" aria-hidden="true">                                     <!-- Z -140, rotateY(12deg) -->
          <div class="lid"><div class="screen"><i class="prompt"></i></div></div><div class="deck"></div>
        </div>
        <ul class="tokens" aria-hidden="true">                                   <!-- the orbit ring, rotateX(72deg) -->
          <li><code>node</code><span>mcp-server-filesystem</span><b>412 MB</b></li>
          <li><code>node</code><span>@modelcontextprotocol/server-github</span><b>388 MB</b></li>
          <li><code>Chrome for Testing</code><span>--headless</span><b>1.1 GB</b></li>
          <li><code>node</code><span>playwright-mcp</span><b>296 MB</b></li>
          <li><code>python3</code><span>mcp-server-fetch</span><b>140 MB</b></li>
          <li><code>node</code><span>chrome-devtools-mcp</span><b>233 MB</b></li>
          <li><code>node</code><span>mcp-server-memory</span><b>97 MB</b></li>
          <li><code>uvx</code><span>mcp-server-git</span><b>121 MB</b></li>
        </ul>
        <p class="bar" aria-hidden="true"><b>Overstay</b><span class="badge"><svg aria-hidden="true"><use href="#i-mark"/></svg>183 · 9.4 GB</span><span class="clock">Tue 23:41</span></p>   <!-- Z 0 -->
        <div class="pop-wrap">                                                   <!-- Z +60 -->
          <figure class="pop" role="img" aria-label="Illustration with sample data: the Overstay menu bar panel. 183 leftover processes holding 9.4 GB in three groups: Claude Code in ~/dev/foo, 61 processes, 3.1 GB, started 3 days ago; Codex in ~/dev/bar, 40 processes, 2.2 GB; Headless browsers, 12 processes, 1.4 GB. A Stop 183 button.">
            <p class="pop-head"><i class="ring"></i><span class="found"><b>183</b> leftover · <b>9.4</b> GB</span><span class="held">Stopped <b>183</b>. <b>9.4</b> GB was held.</span></p>
            <ul class="pop-rows">
              <li><svg aria-hidden="true"><use href="#g-terminal"/></svg><span><b>Claude Code</b> ~/dev/foo</span><code>61 · 3.1 GB</code><small>started 3 days ago</small></li>
              <li><svg aria-hidden="true"><use href="#g-code"/></svg><span><b>Codex</b> ~/dev/bar</span><code>40 · 2.2 GB</code><small>started 2 days ago</small></li>
              <li><svg aria-hidden="true"><use href="#g-globe"/></svg><span><b>Headless browsers</b></span><code>12 · 1.4 GB</code><small>started 5 hours ago</small></li>
            </ul>
            <p class="pop-foot"><span class="pop-cta">Stop 183</span><span>Open Overstay</span><span>Quit</span></p>
          </figure>
          <button class="button pop-stop" type="button" data-sweep aria-controls="hero-scene" aria-pressed="false" hidden>Stop 183</button>
        </div>
      </div>
    </div>
  </div>
  <p class="caption">Illustration with sample data. Overstay is not affiliated with or endorsed by any of the tools it detects.</p>
</section>
```

The `.pop-cta` span is the drawn button inside the picture; the real `<button>` sits exactly over it (same box,
`position: absolute`) once `motion.js` unhides it, so the picture is complete without JS and the control is a true
control with JS. The `.held` headline is in the DOM from the start and `visibility: hidden` until the sweep, so the
figure's `aria-label` (which describes the found state) stays true for assistive tech, and the swept state is
announced through the button's `aria-pressed`.

```css
.room { background: var(--grain), radial-gradient(42% 60% at 6% 62%, var(--spill), transparent 70%), linear-gradient(var(--room-top), var(--room-floor)); }
.hero-grid { display: grid; gap: 40px; align-items: center; }
@media (min-width: 900px) { .hero-grid { grid-template-columns: 5fr 7fr; } }
.stage { position: relative; min-height: 560px; perspective: var(--persp-scene); perspective-origin: 50% 32%; }
.scene { position: absolute; inset: 0; transform-style: preserve-3d; }
/* The door: a tall warm slab at the far left, brightest at mid height, and the only light in the room. */
.door { position: absolute; left: 2%; top: 8%; width: 10px; height: 74%; border-radius: 3px; transform: translateZ(-220px);
  background: linear-gradient(var(--door), var(--door-core) 45% 55%, var(--door)); box-shadow: 0 0 14px var(--spill), 0 0 60px var(--spill); }
.door::before { content: ""; position: absolute; left: 100%; top: -10%; width: 520px; height: 120%; pointer-events: none;
  background: linear-gradient(90deg, var(--spill), transparent 80%); -webkit-mask-image: linear-gradient(transparent, #000 20% 80%, transparent); mask-image: linear-gradient(transparent, #000 20% 80%, transparent); }
/* The floor: a flat plane with the door's pool on it. The mask sits on this flat plane, never on the preserve-3d scene (MOTION §1.6). */
.floor { position: absolute; left: -30%; right: -30%; bottom: -6%; height: 64%; transform-origin: 50% 100%; transform: rotateX(78deg);
  background: radial-gradient(40% 50% at 8% 50%, var(--pool), transparent 70%), repeating-linear-gradient(90deg, rgb(var(--room-ink) / .06) 0 1px, transparent 1px 96px);
  -webkit-mask-image: radial-gradient(70% 90% at 50% 100%, #000 10%, transparent 72%); mask-image: radial-gradient(70% 90% at 50% 100%, #000 10%, transparent 72%); }
/* The laptop: Tirekick's .lid/.screen/.deck drawing, screen dim (the session is over). Fixed colours in both schemes: it's an object. */
.mac { position: absolute; left: 10%; top: 24%; width: 46%; transform: translateZ(-140px) rotateY(12deg); transform-style: preserve-3d; }
.lid { aspect-ratio: 16 / 10.5; padding: 3.5%; border-radius: 14px 14px 4px 4px; background: #1d1d1f; box-shadow: inset 0 0 0 1px rgb(255 255 255 / .1), 0 30px 60px -30px rgb(0 0 0 / .8); transform-origin: 50% 100%; }
.screen { position: relative; height: 100%; border-radius: 6px; background: #0b0b0d; overflow: hidden; }
.screen::after { content: ""; position: absolute; inset: 0; background: linear-gradient(160deg, rgb(242 169 59 / .10), transparent 50%); opacity: .35; }   /* the last glow of the session */
.prompt { position: absolute; left: 7%; top: 10%; width: 7px; height: 14px; background: #6b655c; }               /* a cursor nobody is typing at */
.deck { position: relative; height: 12px; margin-inline: -7%; border-radius: 0 0 16px 16px / 0 0 10px 10px; background: linear-gradient(#e3e4e6, #a9abb0); }
/* The ring: an ellipse in 3D around the laptop. Each token is placed on it and turned back upright to face the camera. */
.tokens { position: absolute; left: 33%; top: 58%; width: 0; height: 0; margin: 0; padding: 0; list-style: none; transform: rotateX(72deg); transform-style: preserve-3d; --r: 250px; }
.tokens li { position: absolute; left: 0; top: 0; display: flex; gap: 8px; align-items: baseline; white-space: nowrap; padding: 7px 11px; border-radius: var(--r-m);
  background: linear-gradient(var(--cap-top), var(--cap-bot)); color: var(--text); font: 500 12px/1.2 var(--font); box-shadow: var(--cap);
  transform: rotateZ(var(--a)) translateX(var(--r)) rotateZ(calc(var(--a) * -1)) rotateX(-72deg) translate(-50%, -50%); }
.tokens code { background: none; box-shadow: none; padding: 0; font-size: 12px; color: var(--text-2); }
.tokens b { font-family: var(--font-num); font-variant-numeric: tabular-nums; }
.tokens li:nth-child(1) { --a: 200deg; } .tokens li:nth-child(2) { --a: 245deg; } .tokens li:nth-child(3) { --a: 290deg; } .tokens li:nth-child(4) { --a: 335deg; }
.tokens li:nth-child(5) { --a: 20deg; }  .tokens li:nth-child(6) { --a: 65deg; }  .tokens li:nth-child(7) { --a: 110deg; } .tokens li:nth-child(8) { --a: 155deg; }
/* The menu bar strip: 28px, a drawn macOS bar with the amber badge. */
.bar { position: absolute; inset: 0 0 auto; height: 28px; margin: 0; padding: 0 14px; display: flex; gap: 16px; align-items: center;
  background: var(--bar-bg); color: var(--bar-text); font: 500 13px/1 var(--font); box-shadow: inset 0 -1px 0 rgb(var(--ink) / .12); }
.bar .badge { margin-left: auto; display: inline-flex; gap: 5px; align-items: center; padding: 3px 8px; border-radius: 999px; background: var(--amber); color: var(--on-button); font: 600 12px/1 var(--font-num); font-variant-numeric: tabular-nums; }
.bar .badge svg { width: 12px; height: 12px; }
.bar .clock { margin-left: 8px; }
/* The popover: hangs from the badge, the front-most object. Opaque, macOS 13 proportions, 360px wide. */
.pop-wrap { position: absolute; right: 3%; top: 34px; width: 360px; transform: translateZ(60px); }
.pop { position: relative; margin: 0; padding: 14px; border-radius: 14px; background: var(--pop-bg); color: var(--pop-text); font: 13px/1.35 var(--font);
  box-shadow: inset 0 1px 0 var(--hi), var(--shadow); }
.pop-head { position: relative; display: flex; gap: 12px; align-items: center; margin: 0 0 12px; padding: 4px 2px 12px; border-bottom: 1px solid var(--pop-line); font-size: 15px; }
.pop-head b { font-family: var(--font-num); font-size: 28px; line-height: 1; letter-spacing: -.02em; }
.pop-head .held { position: absolute; inset: 4px 2px auto; visibility: hidden; }
.ring { flex: none; width: 36px; height: 36px; border-radius: 50%;
  background: conic-gradient(var(--amber) 0 118deg, transparent 118deg 124deg, color-mix(in srgb, var(--amber) 75%, transparent) 124deg 208deg, transparent 208deg 214deg, color-mix(in srgb, var(--amber) 50%, transparent) 214deg 268deg, transparent 268deg 274deg, color-mix(in srgb, var(--amber) 30%, transparent) 274deg 331deg, transparent 331deg 337deg, color-mix(in srgb, var(--amber) 22%, transparent) 337deg 360deg);
  -webkit-mask: radial-gradient(circle, transparent 58%, #000 60%); mask: radial-gradient(circle, transparent 58%, #000 60%); }
.pop-rows { margin: 0; padding: 0; list-style: none; }
.pop-rows li { display: grid; grid-template-columns: 22px 1fr auto; gap: 2px 10px; align-items: center; padding: 8px 6px; border-radius: 8px; }
.pop-rows li:hover { background: var(--pop-row); }
.pop-rows svg { width: 16px; height: 16px; color: var(--pop-2); grid-row: 1 / span 2; }
.pop-rows code { background: none; box-shadow: none; padding: 0; font: 500 12px/1 var(--font-mono); color: var(--pop-2); }
.pop-rows small { grid-column: 2 / span 2; font-size: 11px; color: var(--pop-2); }
.pop-foot { display: flex; gap: 14px; align-items: center; margin: 12px 0 0; padding-top: 12px; border-top: 1px solid var(--pop-line); font-size: 12px; color: var(--pop-2); }
.pop-cta { padding: 8px 14px; border-radius: var(--r-btn); background: linear-gradient(var(--button), color-mix(in srgb, var(--button) 88%, #000)); color: var(--on-button); font: 600 13px/1 var(--font); box-shadow: inset 0 1px 0 rgb(255 255 255 / .35), var(--cap); }
.pop-stop { position: absolute; left: 14px; bottom: 14px; min-height: 0; padding: 8px 14px; font-size: 13px; transform: translateZ(2px); }
.pop-stop[hidden] { display: none; }
@media (max-width: 900px) { .mac, .tokens { display: none; } .pop-wrap { position: static; width: min(360px, 100%); margin: 36px auto 0; transform: none; } .bar { position: static; border-radius: 10px 10px 0 0; } .stage { min-height: 0; } }
```

**Planes** (4, within MOTION §1.2's cap): door −220, laptop −140 (the ring sits on the floor plane around it), the
bar at 0, the popover +60. The pointer tilts the whole scene up to 5°, which parallaxes the ring against the laptop
and the popover against the bar: the depth cue a flat frame can't give.

**Sequence** (2.4 s once, then still) and **the sweep** (0.9 s on the button) are specified in MOTION §2.
Reduce Motion, print and no-JS show the found state; the button swaps states instantly under Reduce Motion.

### 4.3 Inline glyphs (the page's sprite; neutral, no vendor marks)

`#i-mark` (the app mark: three stacked bars of decreasing width, §7), `#g-terminal` (Claude Code), `#g-code`
(Codex), `#g-globe` (Headless browsers), `#g-server` (Agent tool servers), each a 24-viewBox stroke icon drawn to
match the SF Symbols the app uses (§6.4), so the replica and the CI captures agree.

### 4.4 Section recipes

- **Slabs (`.slab`, the "Stop, politely" section):** the weight bar as a site object. A flex row, each slab's
  `flex-grow` its demo footprint, `min-width: 64px`, 16px radius, `linear-gradient(var(--slab-top), var(--slab-bot))`,
  `box-shadow: var(--slab)`, a 2px amber lit edge on top (`::before`, `inset: 0 0 auto`, `background: var(--amber)`,
  `opacity: .9`), inside: the small-caps agent name, the rounded GB, the mono count. `data-tilt` 5° on the row, not
  per slab. Under Reduce Motion, static.
- **Readout rows** (the Activity Monitor pair, the group card): a 3px amber tick on the leading edge of a Ghost row
  (`::before`, 10px inset), none on a Maybe; title 15px 600, detail `--text-2`, mono readout right-aligned, then
  `.tag`. Hairlines between rows, never cards.
- **Receipt** (the confirm copy): `--bg-alt`, 11px radius, 13px mono, `--text-2`, dots between clauses.
- **Finale:** `.finale .icon` from §2.6 standing in a `.floor` copy's pool with a `.door` copy at the band's left.

## 5. Sub-pages

- **Download:** a 240px room band with the icon standing in the door's pool, the h1, the amber key-cap, the
  requirements line, three key-cap steps (Open the zip · Drag to Applications · Right-click, Open the first time:
  the Gatekeeper step, with the SHA-256 line), and the official-sources line.
- **Safety ("What it reads"):** the reading layout; the §3-7 ledger in full, then the safety rules from BUILD_PLAN
  §3 as a numbered `.rules` list with mono chips (`kill(2)`, `SIGTERM`, `0600`, `stat`). Prints clean.
- **How it decides:** the reading layout; the four rules with a worked example per tier (Ghost, Maybe, Ignored,
  Protected), each example a readout row with its why line; the protected list as a mono block; a "Report a false
  positive" amber key-cap linking the issue template.
- **Changelog:** release `.card`s with a 2px amber rail on the left and the version in a mono tag.
- **404:** the room band with the door light and nothing in orbit: "Nothing here. Nothing left behind, either."
  (copy owner to confirm).
- **`llms.txt`:** plain text, the pitch, the trust box, the not-affiliated line.

## 6. The app (macOS 13; macOS 14+ and 26 only in `Compat.swift`). Written, not compiled.

**Material hierarchy, in order:** the system window (sidebar and toolbar stay system; on macOS 26 the SDK makes
them glass by itself) → `Room` (a static wash: the door light at the leading edge of stage screens) → porcelain
surfaces for content groups → controls (glass only on `barSurface()`). One accent; tier only as a tag word plus
dot; status only as symbol tint. One lifted object per screen. Nothing moves at idle.

### 6.1 `App/DesignSystem/Tokens.swift`

Copy Tirekick's `Space`, `Radius` (add `plate = 18, tile = 14, row = 12, chip = 8`), `Motion`, `surface`,
`OnFloor`, `Horizon`, `Metric`, `Tag`, `KeyCapStyle`, `HoverTilt`, `flip`, `FlipFaces`, `CopyButton`,
`copyToPasteboard` verbatim, then change only these:

```swift
/// docs/DESIGN.md §1, §6. Amber is the one accent ("leftover"); green only for All quiet; red only on a refused row's symbol.
enum Brand {
    /// Warm brown-black: the soft shadow under porcelain surfaces is tinted with it, never neutral grey (rule 3).
    static let ink = Color(red: 0.16, green: 0.09, blue: 0.03)                                        // #281808
    /// The door light and every amber fill. Near-black text on it (9.5:1).
    static let amber = Color(red: 0.949, green: 0.663, blue: 0.231)                                    // #F2A93B
    static let onAmber = Color(red: 0.078, green: 0.059, blue: 0.031)                                  // #140F08
    /// Amber as text or a symbol: readable on paper and on the night room (4.6:1 / 9.6:1).
    static let amberInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.961, green: 0.710, blue: 0.290, alpha: 1)                            // #F5B54A
            : NSColor(srgbRed: 0.604, green: 0.357, blue: 0.000, alpha: 1)                            // #9A5B00
    })
}

/// The room behind stage screens (first run, the main window's header, the result sheet): the plain window plus
/// the door light at the leading edge, as a static wash. Increase Contrast gets the plain window. Drawn once per size.
struct Room: View {
    var strength = 1.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .leading) {
            Color(nsColor: .windowBackgroundColor)
            if contrast != .increased {
                if dark {
                    LinearGradient(colors: [Color(red: 0.078, green: 0.067, blue: 0.051), Color(red: 0.043, green: 0.035, blue: 0.031)],
                                   startPoint: .top, endPoint: .bottom)                                    // #14110D → #0B0908
                }
                // The door light: a tall warm pool anchored to the leading edge. One key light per scene (rule 2).
                EllipticalGradient(colors: [Brand.amber.opacity((dark ? 0.22 : 0.16) * strength), .clear],
                                   center: UnitPoint(x: 0, y: 0.55), startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: 720, height: 720)
                    .offset(x: -360)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one prominent button per screen (Stop 183, Continue, Copy my number): an amber key-cap with near-black text, a
/// lit top edge and a brown lip; a press sinks 1pt. No glow: the light comes from the door, not the button.
/// `.keyboardShortcut(.defaultAction)` still works. Replaces .borderedProminent there.
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

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
                .animation(Motion.pop, value: configuration.isPressed)
        }
    }
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
    /// The chip word. Tier is carried by the word, never by colour alone (§1.1 rule 4).
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
```

`Tag(text, tint:)` is unchanged; `Tag(c.tier.word, tint: c.tier.tint)` is the tier chip. The `Metric` default
design is `.rounded` (Overstay's numerals are rounded; mono is for pids, paths and argv only).

**Type in the app:** SF only. The total `.system(size: 44, weight: .semibold, design: .rounded)` with
`.monospacedDigit()` and `.contentTransition(.numericText())` (macOS 13); stage headlines `.system(size: 28,
weight: .semibold)` `tracking(-0.5)`; plate titles 22pt semibold; rows 13pt with a 12pt secondary line; argv, cwd
and pids `.system(.caption, design: .monospaced)`; small-caps labels only on metric labels and section headers.
Radii 18 (plates), 14 (tiles, slabs), 12 (rows, inner groups), 8 (chips), 11 for the amber button.

### 6.2 `App/DesignSystem/Compat.swift` (the only file with `#available`)

Tirekick's `barSurface()`, `capsuleBorder()` and `bounce(on:)` verbatim, plus:

```swift
extension View {
    /// Opens the main window and brings the app forward. `NSApp.activate()` is macOS 14; 13 uses the older form.
    func activateApp() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}
```

The macOS 13 path is the full design. macOS 14 adds the symbol bounce on the All-quiet check and the capsule
border; macOS 26 adds glass on the two bars.

### 6.3 `Slab.swift`, `WeightBar.swift`: the signature object

```swift
/// One raised slab per group: lit top edge (the door light catches it), hairline, a long soft amber-tinted shadow.
/// Selected slabs sit 2pt higher with a brighter rim; `settled` is the collapse end state (MOTION §3.2).
/// Pure fills and shadows: no material, so ImageRenderer can draw it for the share card and the GIF.
struct Slab: View {
    let group: LeftoverGroup
    var selected: Bool
    var settled = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        let dark = scheme == .dark
        let face = dark ? [Color(red: 0.18, green: 0.157, blue: 0.129), Color(red: 0.133, green: 0.114, blue: 0.09)]   // #2E2821 → #221D17
                        : [Color(red: 1, green: 0.992, blue: 0.976), Color(red: 0.953, green: 0.925, blue: 0.882)]      // #FFFDF9 → #F3ECE1
        VStack(alignment: .leading, spacing: 4) {
            Text(Grouping.title(group)).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary).lineLimit(1)   // VERIFY smallCaps with SF
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
                        Capsule().fill(selected ? Brand.amber : Color.white.opacity(dark ? 0.12 : 0.9)).frame(height: 2).padding(.horizontal, Radius.tile).padding(.top, 1)
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
        .accessibilityAddTraits(.isButton)
    }
}

/// The weight bar: slabs side by side, width proportional to Ghost footprint with a floor so small groups stay
/// legible. Click toggles selection; `settled` holds the ids whose stop has finished (the collapse, MOTION §3.2).
/// Maybes are not in the bar (they are in no bulk action); a trailing dotted stub says how many there are.
struct WeightBar: View {
    let groups: [LeftoverGroup]
    @Binding var selected: Set<String>
    var settled: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = max(1, groups.reduce(0) { $0 + $1.ghostBytes })
        GeometryReader { g in
            let gap = Space.xs, minW: CGFloat = 92
            let free = max(0, g.size.width - gap * CGFloat(max(0, groups.count - 1)) - minW * CGFloat(groups.count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                    Slab(group: group, selected: selected.contains(group.id), settled: settled.contains(group.id))
                        .frame(width: minW + free * CGFloat(group.ghostBytes) / CGFloat(total))
                        .contentShape(Rectangle())
                        .onTapGesture { if selected.remove(group.id) == nil { selected.insert(group.id) } }
                        .animation(Motion.spring(reduceMotion).delay(reduceMotion ? 0 : Double(min(i, 8)) * Motion.stagger), value: settled)
                        .animation(Motion.pop, value: selected)
                }
            }
        }
        .frame(height: 76)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight bar: memory held per group")
    }
}

/// The popover's reading of the same groups: arcs of one ring, each group's share of the Ghost footprint, amber at
/// falling opacity by rank; the total sits inside. `progress` 1 → 0 shrinks every arc clockwise (the collapse).
/// Canvas is macOS 12; drawn once per value, no loop.
struct OrbitRing: View {
    let groups: [LeftoverGroup]
    var progress = 1.0
    var size: CGFloat = 56

    var body: some View {
        let total = max(1, groups.reduce(0) { $0 + $1.ghostBytes })
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2), r = min(sz.width, sz.height) / 2 - 3
            let gap = Angle.degrees(groups.count > 1 ? 6 : 0)
            var start = Angle.degrees(-90)
            for (i, g) in groups.enumerated() {
                let sweep = Angle.degrees(360 * Double(g.ghostBytes) / Double(total) * progress) - gap
                if sweep.degrees > 0 {
                    var p = Path()
                    p.addArc(center: c, radius: r, startAngle: start, endAngle: start + sweep, clockwise: false)
                    ctx.stroke(p, with: .color(Brand.amber.opacity(max(0.22, 1 - Double(i) * 0.25))), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                start += sweep + gap
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // the number beside it carries the value
    }
}
```

`Motion.stagger = 0.045` is added to `Motion` (Whydunit's value). The collapse of five slabs therefore spans
0.45 s of stagger plus a 0.45 s spring: under 1 s for the whole bar (BUILD_PLAN §8).

### 6.4 `MenuBarIcon.swift`

- **The glyph** (template, always present): three stacked rounded bars of decreasing width, left-aligned, 16×16
  (the weight bar in miniature; the same mark as the site's `#i-mark` and the app icon's foreground). Drawn with
  `Canvas` into an `ImageRenderer` once at launch, `isTemplate = true`, so it follows the menu bar's appearance.
- **The badge** (only while Ghosts exist, BUILD_PLAN §7.2): the glyph plus an amber capsule with the count in
  `.system(size: 10, weight: .semibold, design: .rounded)` near-black, rendered by `ImageRenderer` as a
  non-template `NSImage` at 2× scale, cached per count. VERIFY that `MenuBarExtra` keeps a non-template image's
  colour on macOS 13/15/26 (BUILD_PLAN §12); if not, fall back to the template glyph with the count as text beside it.
- The quiet state is the template glyph alone, never green: the menu bar stays quiet when the room is quiet.

```swift
enum MenuBarIcon {
    static let glyph: NSImage = render(count: nil)
    /// Cached per count; the count is capped at 999 ("999+").
    static func badge(count: Int) -> NSImage { cache[count] ?? { let i = render(count: count); cache[count] = i; return i }() }
    private static var cache: [Int: NSImage] = [:]

    @MainActor private static func render(count: Int?) -> NSImage {
        let r = ImageRenderer(content: Mark(count: count))
        r.scale = 2
        let image = r.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = count == nil
        return image
    }

    private struct Mark: View {
        let count: Int?
        var body: some View {
            HStack(spacing: 4) {
                Canvas { ctx, sz in
                    for (i, w) in [1.0, 0.72, 0.46].enumerated() {
                        let rect = CGRect(x: 1, y: 2 + CGFloat(i) * 4.5, width: (sz.width - 2) * w, height: 3)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(count == nil ? .black : .primary))
                    }
                }
                .frame(width: 16, height: 16)
                if let count {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Brand.onAmber)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Brand.amber, in: Capsule())
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
```

### 6.5 Screens

**First run** (`FirstRunView`, app-shell). A 480pt column over `Room()`: `OnFloor(height: 112) { Image(nsImage:
NSApp.applicationIconImage).resizable().frame(width: 112, height: 112) }` with `HoverTilt(max: 8, glare: true)`
and MOTION §3.1's arrival; "What Overstay reads" at 28pt semibold; one `.surface(16)` with two small-caps headed
columns, "Reads" (four `Label`s: `list.bullet.rectangle` the process table, `memorychip` memory footprint,
`text.alignleft` the arguments of matching processes, `folder` working folders) and "Never" (five: `lock.open`
no permissions, `wifi.slash` no network, `doc` no files touched, `power` no login item, `arrow.uturn.backward`
"no undo: a stopped process stays stopped"); the one `AmberButtonStyle` "Continue". VERIFY each symbol on macOS 13.

**Menu bar popover** (`PopoverView`, app-shell; 360pt wide). The window-style `MenuBarExtra` content:

- *Quiet:* a 36pt `checkmark.circle.fill` in `.green` (`.bounce(on:)` once when the state arrives, Compat), "All
  quiet. Nothing left behind." at 15pt semibold, "Checked 412 processes · 2 min ago" in 12pt secondary, a hairline,
  then "Open Overstay" and "Quit" as plain `.borderless` rows with `.keyboardShortcut`. No amber anywhere.
- *Leftovers:* header `HStack`: `OrbitRing(groups:)` at 56pt, then the total `Text("183")` at 28pt rounded
  semibold beside "leftover · 9.4 GB" at 15pt (one VoiceOver element: "183 leftover processes holding 9.4 GB");
  then a `List` of the top three groups (selection binding, `.listStyle(.plain)`, rows: the agent symbol in a 22pt
  neutral `well`, "Claude Code" 13pt semibold + `~/dev/foo` secondary, trailing `61 · 3.1 GB` in rounded
  `monospacedDigit`, under it "started 3 days ago" 11pt); "and 2 more groups" as a 12pt secondary line when there
  are more; the bottom bar on `barSurface()`: the `AmberButtonStyle` **Stop 183** (`.keyboardShortcut(.defaultAction)`),
  "Open Overstay", "Quit". Keyboard: ↑/↓ move the list selection, Return stops, Esc closes (VERIFY on macOS 13,
  BUILD_PLAN §7.1). While a stop runs the ring's `progress` animates to 0 and the number counts down with
  `.contentTransition(.numericText())`; the result line "Stopped 183. 9.4 GB was held." replaces the header.
- The popover is also shown in an ordinary window for `screens.yml` (BUILD_PLAN §9).

**Main window, groups** (`MainView` + `GroupsView`, 760×560 min). `NavigationSplitView`: the sidebar lists groups
(system `List` rows: checkbox, symbol in a 24pt `well`, title 13pt semibold, project secondary, trailing count ·
GB, under it the tier chips "61 Leftover" `.amber` and, when present, "2 Maybe"). The detail column's top is a stage
over `Room()`: a `Metric` row (`Metric("Leftover", "183")`, `Metric("Held", "9.4", unit: "GB")`,
`Metric("Groups", "5")`) separated by hairlines, the first value at 44pt rounded with `numericText`; below it the
**`WeightBar`** inside a `.surface(18)` with 12pt padding (the one lifted object); below that the "Maybe" disclosure
(a `.surface(16)` with collapsed rows). The bottom bar on `barSurface()`: "Stop 183 selected" (`AmberButtonStyle`),
"Select all leftovers", "Rescan". Toolbar: Rescan, Groups | Activity picker, Share, Preferences. A "Sample data"
`Tag` top-trailing in demo mode. Empty state ("All quiet." over `Room(strength: 0.5)`, a green check, "Checked 412
processes"); "nothing could be read for 3 processes" in a 12pt secondary line, never a warning colour.

**Group detail** (`GroupDetailView`). Header over `Room`: the symbol in a 44pt `well`, the title 22pt semibold,
"~/dev/foo · 61 processes · 3.1 GB · started 3 days ago" secondary; one `.surface(16)` holding the process tree:
`OutlineGroup`-style rows (parents before children, 16pt indent per depth, a 1pt `.separator` rail): executable
basename 13pt semibold, the why line 12pt secondary (`lineLimit(2)`), trailing size rounded mono-digit, the tier
`Tag`; "Details" as a borderless disclosure revealing the scrubbed argv summary and cwd in `.caption`
`.monospaced` on `terminal()` (Tirekick's recessed well), selectable; ancestry as one line: "Parent is gone, adopted
by launchd." Maybe rows are collapsed under a "4 Maybe" disclosure, each with its own `.bordered` "Stop this one…".
Rows flip in once per load with `.flip(reduceMotion)` on the existing 45 ms stagger (cap 8).

**Confirm sheet** (`ConfirmSheet`). `SheetHeader` style: "Stop 183 processes?" 22pt; a `.surface(16)` listing the
counts per group with the biggest three executables named ("61 in Claude Code · ~/dev/foo: node ×58, Chrome for
Testing ×3"); the receipt line in mono secondary: "SIGTERM first · leaf first · wait up to 5 s"; the fixed copy
"Only processes are touched, never files. This cannot be undone. Anything unsaved inside these processes is lost.";
Cancel (`role: .cancel`) and the `AmberButtonStyle` "Stop 183". No amber panel, no red.

**Running** (phase `.running`). The sheet stays; the weight bar collapses behind it as `finished` grows (MOTION
§3.2); a small `ProgressView` with "Stopping… 74 of 183" in rounded digits. The only loop is the system spinner.

**Result sheet** (`ResultSheet`). Over `Room()`: "Stopped 183. 9.4 GB was held." at 22pt with the number in
rounded; survivors in a `.surface(16)` with `clock.badge.exclamationmark` rows and a per-group `.bordered` "Force
stop…" (its own confirmation); "Left alone: 2 changed since the scan." and "macOS did not allow Overstay to stop 2
processes." as plain rows with `hand.raised` / red `xmark.circle.fill`; the **share card preview** (§6.6) lifted with
`HoverTilt(max: 4, glare: true)`; "Copy my number" (`AmberButtonStyle`), "Save as PNG…", "Open the log".

**Activity** (`ActivityView`). A `Table` (system) or plain `List` newest first: time (mono, 64pt), executable,
signature title, project folder, result (`TargetStatus.symbol` + word), why. Days grouped under small-caps
headers. "Reveal log in Finder" in the toolbar.

**Preferences sheet** (`PreferencesSheet`). `Form` + `.formStyle(.grouped)`, stock: the age gate picker (10 / 30 /
60 min), the never-touch list (add/remove rows; a removal only removes a user entry), (a notifications toggle is deferred, not in v1) "Include project names on the share card" (off), the auto-scan interval. No custom surfaces here.

**Edge states.** All plain: a secondary sentence over `Room(strength: 0.5)` or a plain row; the activity-log-not-
writable state is a sheet with "Overstay can't write its activity log, so nothing was stopped." and "Reveal folder".

**Dark mode.** The room gradient; surfaces white .055 with a white .10 rim; amber text uses `Brand.amberInk`.
Increase Contrast gives the plain window, 1pt primary strokes, slabs with a 1–2pt stroke and no amber shadow.

### 6.6 Share card (`ShareCardView`, app-share; the PNG; no materials, blur or shadows inside)

1200×630 at 2× from a 600×315pt view. The night room in every scheme (the card is an object, like Tirekick's paper
card): `#0F0D0B` → `#16130F` top to bottom, the door light as a plain amber `EllipticalGradient` at the leading
edge, three slabs drawn with `Slab`'s fills (no shadows) at the bottom-left whose widths are the top three groups.
Headline `ShareCardText.headline(card)` at 44pt rounded semibold `#F6F0E6`, the number in `Brand.amber`; subline at
18pt `#A79B8A`; the mark and "Overstay" at 16pt bottom-right; the "Sample data" watermark as a 14pt small-caps
amber `Tag` top-right when `isSample`; the footer line (the site address, passed in by the caller). No project
names unless `projectNames` is non-empty. `ImageRenderer` on macOS 13: VERIFY the 1200×630 output (BUILD_PLAN §12).

## 7. Icon and social image (infra: `tools/make_icon.py`, `tools/make_og.py`, stdlib SDF renderers)

- **App icon:** a warm near-black squircle (`#1E1A15` → `#0F0D0B`, a faint top highlight) with the door light as a
  vertical amber bar along the left edge (`#F2A93B`, core `#FFF3D8`, a soft spill to the right) and the **mark**:
  three stacked rounded bars of decreasing width in warm white (`#F6F0E6`), centred, lit from the left (a 1px amber
  rim on their left ends). Reads at 16px as "dark square, amber slit, three bars". No text, no vendor marks. Later,
  on a Mac: an Icon Composer `.icon` with three layers (room, door light, bars) and specular on the bars.
- **Menu bar:** the mark alone, template (§6.4).
- **OG image (1200×630):** the room edge to edge (door light at left, floor pool), the icon at 280px standing in the
  pool with its reflection, the wordmark under it. No sentence in the image; `og:title` carries "Overstay for Mac:
  find and stop the processes your AI coding agents left behind".

## 8. Acceptance and budgets

**Looks premium (a judge checks light and dark captures at 1440 and 390px, base and `prefers-contrast: more`,
against `refs/`):**

- [ ] The hero has no container edge: light comes only from the door; the floor reads as a floor; the dim laptop is
      behind, the ring of tokens stands around it, the popover is in front and the brightest object; the menu bar
      reads as macOS with an amber badge; everything is still after 2.4 s; pressing "Stop 183" sweeps the tokens out
      through the door and the header reads "Stopped 183. 9.4 GB was held."; "Rescan" brings them back.
- [ ] Exactly one accent is visible (amber); green appears only in dots and the All-quiet check; red only on a
      refused row's symbol; no tier gets a coloured panel.
- [ ] Every raised surface shows a lit top edge, a 0.5px hairline (1px rim in dark) and an ink-tinted shadow;
      slabs cast a long amber-tinted shadow; buttons have a lip and no glow; key-caps sink on press.
- [ ] Headlines are the system display face at 600 with tight tracking; numerals are rounded and tabular; readouts
      are mono; labels are small caps; nothing is ALL CAPS copy; no font file is requested (Network panel).
- [ ] Light mode is a warm paper room with the same door light, not a grey page; dark is warm near-black, never #000.
- [ ] Real screens appear only at ≤ 50% of their pixel width; no horizontal page scroll at 360px.
- [ ] Reduce Motion, no-JS and print show the found state; print is dark text on white; the sweep button swaps
      instantly under Reduce Motion and is hidden without JS.
- [ ] Every page carries "Overstay is not affiliated with or endorsed by any of the tools it detects."
- [ ] `python tools/build_site.py --check` passes with exactly two `:root` blocks, no `style=""`, the CSP exact.
- [ ] App, from CI captures: the popover shows the orbit ring and one amber button; the main window shows the weight
      bar as the one lifted object on the room wash with no grey-on-grey; tier chips carry words; the quiet popover
      has no amber; the share card has no project names unless opted in and shows the watermark in demo mode;
      VoiceOver labels and traits read the tier word and the counts.

**Budgets:**

| Item | Cap |
|---|---|
| `site/static/styles.css` | 40 KB (`BUDGET` in `build_site.py`) |
| `site/static/motion.js` | 6 KB: the shared 2.7 KB plus the sweep job (MOTION §2.4), under 1 KB |
| Webfonts | 0 files, 0 bytes |
| Home HTML (built) | ≤ 36 KB |
| First load (HTML + CSS + JS + icon + favicon) | ≤ 110 KB |
| Lazy screenshots | ≤ 110 KB each, 3 per scheme, only the active scheme loads |
| Third-party requests, CDNs, trackers, network calls from the app | 0 |
| Hero sequence | ≤ 2.4 s, once; the sweep ≤ 0.9 s on the button; ≤ 4 planes |
| CLS / LCP | 0 / the h1 text |
| App | CPU 0% within 2 s of any entrance; the collapse ≤ 1 s for the whole bar; `HoverTilt` ≤ 8 on screen (first run 1, result 1); new assets or dependencies: none |
| CSP | Tirekick's exact string; no inline script, style or handler |

**Security.** Nothing here touches the safety rules, `Signal.swift`, the entitlements or the data flow. The share
card path stays effect-free. Materials and glass are system APIs. The site makes no request beyond its own files.

## 9. Changes for other owners, decisions for the lead, VERIFY list

**By owner (proposed, not made):**

- **site (`site/**`):** §2–§5 and MOTION §2; the inline glyph sprite (§4.3); the `html[lang]` media rules; the
  `color-scheme` and two `theme-color` metas; `motion.js` = the shared file plus the sweep job.
- **infra (`tools/build_site.py`, `make_icon.py`, `make_og.py`):** `BUDGET` without a `fonts/*` entry and with
  `motion.js` 6 000; fail `--check` if any `fonts/` file exists; the icon and OG per §7.
- **app-shell (`PopoverView`, `MenuBarLabel`, `FirstRunView`, `MainView`):** §6.5's popover, first run and main
  window; `MenuBarLabel` uses `MenuBarIcon.glyph` / `.badge(count:)`; `activateApp()` from Compat.
- **app-content:** §6.5's groups, detail, confirm, result, activity, preferences, edge states.
- **app-share:** §6.6, using `Slab`'s fills and `Brand`.
- **core (`Format`):** nothing new; `Format.bytes` and `Format.count` are what the slabs print.
- **copy / lead (BUILD_PLAN §8):** the tier chip words "Leftover" / "Maybe" (§6.1; BUILD_PLAN never fixes the chip
  word and the UI should not say "Ghost"); the proof-strip numerals (§3 item 3); the FAQ questions; the 404 line;
  "and 2 more groups" in the popover.
- **BUILD_PLAN §8:** amend "Dark-first with a true light mode" with "the site follows the system scheme; the dark
  palette is the designed-first one and the one on the OG image"; add "no webfont" to the site line.

**Decisions for the lead:** (1) confirm no webfont (reverses the siblings' decision 1; the headline renders in
Segoe UI Variable on Windows); (2) confirm the sweep button in the hero (one Overstay-specific JS job, JS cap 6 KB);
(3) confirm the chip words "Leftover" / "Maybe"; (4) confirm that the quiet menu bar icon stays uncoloured (no
green badge).

**VERIFY (on a Mac or in Safari):** every SF Symbol in §6.1, §6.5 on macOS 13 (`cursorarrow`, `wind`, `curlybraces`,
`server.rack`, `sparkles`, `memorychip`, `wifi.slash`, `hand.raised`, `clock.badge.exclamationmark`);
`Font.smallCaps()` with SF; `EllipticalGradient` on macOS 13; `Canvas` in `ImageRenderer` for the menu bar glyph and
whether `MenuBarExtra` keeps a non-template image's colour; `OnFloor`'s shadow offset; `HoverTilt` signs; the
`.contentTransition(.numericText())` countdown while `finished` changes quickly; the ring's counter-rotated tokens
in Safari (`rotateZ … rotateX(-72deg)` inside a `rotateX(72deg)` parent) and the floor's mask on a rotated plane;
`-webkit-box-reflect` inside a 3D parent; `color-mix()` in the `.tag` and `.ring` rules on Safari 16.2+ (the
siblings already rely on it); the JPEG corner radius at half scale; `screencapture -o -l` for the popover window.
