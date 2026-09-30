---
name: sagip-flutter-design
description: Design rules for Project S.A.G.I.P. Flutter UI — the resident/responder Android app and the dispatcher/admin web dashboard. Use whenever creating, changing, or reviewing any screen, widget, theme, color, typography, layout, icon, map style, animation, or UI text in this repo.
---

# S.A.G.I.P. Flutter Design

S.A.G.I.P. should look like premium, precision equipment: the calm confidence of an aircraft glass cockpit, a luxury car's instrument cluster, or a top-tier native app. High-end here comes from restraint, precision, and craft, never from decoration. A frightened resident in the rain and a dispatcher on a 12-hour shift should both feel the system is serious, trustworthy, and in control.

Two goals that must both be met, in this order:
1. **Clarity under stress.** Emergency usability always wins a conflict.
2. **High-end finish.** Once clear, every detail is refined until nothing looks default.

## What makes it look high-end

1. **Restraint.** About 90% of every screen is neutral surfaces and type. Color appears only when it carries meaning (status, severity, the primary action). A calm canvas makes the red SOS feel powerful.
2. **Precision.** Strict 4/8-point grid, optical alignment, consistent icon weight, tabular numbers, identical padding for identical elements. Misalignment by 2 px is a bug.
3. **Depth through tone, not shadow.** Separate layers with tonal surfaces and 1 px hairline borders at low opacity. Use real shadow only for things floating above the map.
4. **Confident typography.** Large, tightly tracked numbers and headings; generous line height in body text; hierarchy from size and weight, not from colored words.
5. **Designed dark mode.** Dark mode is its own palette (deep bay navy), not inverted light mode. The command center defaults to dark.
6. **Crafted motion.** Short, physical, purposeful motion paired with haptics. Nothing loops for decoration.
7. **Custom map style.** A muted basemap tuned to the palette is the single biggest upgrade. Default Google/OSM tiles instantly look cheap.
8. **No stock parts.** No stock photos, clip-art illustrations, emoji icons, or unmodified default Material widgets on hero screens.

## Design tokens

Define in `packages/shared/lib/theme/`. Never hard-code colors, sizes, durations, or curves in widgets.

### Color

Neutrals (the canvas):

| Token | Hex | Use |
|---|---|---|
| `bay` | `#0B1724` | Dark mode background; deepest layer |
| `harbor` | `#132436` | Dark mode raised surface (panels, sheets) |
| `harborHigh` | `#1B3047` | Dark mode highest surface (drawer, hover) |
| `mist` | `#EEF2F5` | Light mode background |
| `porcelain` | `#FFFFFF` | Light mode surfaces |
| `ink` | `#0F1C2A` | Primary text on light |
| `slate` | `#5B6B7B` | Secondary text, icons at rest |
| `hairline` | ink at 8% (light) / white at 8% (dark) | Dividers and borders |

Signals (meaning only):

| Token | Hex | Use |
|---|---|---|
| `signal` | `#E5323F` | SOS, critical, confirmed incidents |
| `ember` | `#F5A524` | Warnings, Pending Verification, weather alerts (dark text on it) |
| `verdant` | `#19A06B` | Available, resolved, delivered/synced |
| `tide` | `#2E7CD6` | Primary actions, assigned, en route, links |
| `dusk` | `#7C5CD6` | On scene only |

Rules:
- Signals appear as small, confident accents: a dot, a chip, a thin left edge, an icon. Large fills of signal color are reserved for the SOS button and critical banners.
- Use signal colors at 12–16% opacity for chip backgrounds with full-strength text/icon on top; this reads premium and stays legible.
- Every text/background pair passes WCAG AA in both themes. Ember never carries white text.

### Status mapping (always via `StatusChip`)

| Status | Treatment | Label |
|---|---|---|
| pendingVerification | ember tint + hourglass | Pending verification |
| unverified | hairline dashed outline, slate text | Unverified |
| confirmed | signal tint + warning icon | Confirmed |
| assigned | tide outline | Assigned |
| enRoute | tide tint + navigation icon | En route |
| onScene | dusk tint + pin icon | On scene |
| resolved | verdant tint + check | Resolved |
| available (unit) | verdant dot + label | Available |

Status is always color + icon + text, never color alone.

### Typography

- Family: **Plus Jakarta Sans** (via `google_fonts`). A modern geometric sans designed for a Southeast Asian capital city: refined, warm, and very legible. One family only; hierarchy comes from size and weight.
- Numbers (ETAs, counts, timestamps, coordinates, risk scores) use `FontFeature.tabularFigures()` so they stay steady as they update.
- Tighten tracking on large sizes (letterSpacing about -0.5 at 24+, -1.0 at 40+). Keep body tracking at 0.
- Body line height 1.5; headings 1.15–1.25.
- Weights: 700 for big numbers and screen titles, 600 for section titles and buttons, 400–500 for body. Avoid 800+ except the SOS label.

| Style | Mobile | Dashboard |
|---|---|---|
| hero number (ETA, counts) | 48 / 700 | 32 / 700 |
| headline | 28 / 700 | 22 / 700 |
| title | 20 / 600 | 17 / 600 |
| body | 16 / 400 | 14 / 400 |
| label | 14 / 500 | 13 / 500 |
| caption | 13 / 400 | 12 / 400 |

Sentence case everywhere. No all-caps labels, no colored single words in headings. Respect system text scaling and test at 130%.

### Spacing, shape, elevation

- Spacing scale: 4, 8, 12, 16, 20, 24, 32, 40, 56. Screen side padding 20 on mobile, 24 on dashboard panels.
- Radius by hierarchy: 6 for chips and inputs, 12 for cards and list groups, 20 for bottom sheets and drawers, full circle for the SOS button and avatars.
- Elevation: none by default. Tonal surface step + hairline border for grouping. Soft, large, low-opacity shadow (blur 24–40, 8–12% opacity) only for elements floating above the map.

### Motion

| Token | Value | Use |
|---|---|---|
| `fast` | 150 ms | Press states, chip changes |
| `base` | 250 ms | Sheets, drawers, cross-fades |
| `emphasis` | 400 ms | SOS confirmation, new critical incident |
| curve (enter) | `Curves.easeOutCubic` | Things appearing |
| curve (exit) | `Curves.easeInCubic` | Things leaving |

- Pair key moments with haptics: SOS hold progress (light ticks), SOS sent (heavy impact), status change (selection click).
- Numbers that change (ETA, counts) animate smoothly between values instead of snapping.
- Respect reduced motion via `MediaQuery.of(context).disableAnimations`.

```dart
// packages/shared/lib/theme/sagip_colors.dart
abstract final class SagipColors {
  // Neutrals
  static const bay = Color(0xFF0B1724);
  static const harbor = Color(0xFF132436);
  static const harborHigh = Color(0xFF1B3047);
  static const mist = Color(0xFFEEF2F5);
  static const porcelain = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F1C2A);
  static const slate = Color(0xFF5B6B7B);
  // Signals
  static const signal = Color(0xFFE5323F);
  static const ember = Color(0xFFF5A524);
  static const verdant = Color(0xFF19A06B);
  static const tide = Color(0xFF2E7CD6);
  static const dusk = Color(0xFF7C5CD6);
}
```

Build light and dark `ThemeData` (Material 3) from these, overriding component themes (buttons, inputs, chips, navigation, dialogs, sheets) so no default Material look leaks through. Expose status colors, motion, and spacing via `ThemeExtension`s.

## Signature element: the SOS button

This is the one place the design is bold. Make it feel like a physical, precision-machined control.

- Large circle (about 200 dp) in `signal`, with two or three concentric rings in decreasing opacity behind it for depth.
- Subtle radial gradient (slightly lighter center) and a soft colored glow, so it reads as lit from within. Keep it subtle.
- Label: "SOS" in 800 weight, with a small caption below: "Hold for 2 seconds".
- Press-and-hold: a thin progress ring draws around the edge with light haptic ticks; release early cancels with a gentle snap-back. A tap alone never sends.
- States have their own visuals and text: holding, sending (the one allowed pulse), sent, saved on phone (Tier 1), sent by SMS (Tier 2), relaying to nearby phones (Tier 3), delivered.
- Everything around it stays quiet: no competing color, no clutter.

## Mobile app (resident and responder)

- Composition: generous whitespace, one clear focal point per screen, content anchored to a clean left edge.
- One-thumb reach: primary actions in the lower half; minimum touch target 48 dp.
- Minimal typing: large selectable chips for incident type, auto-filled location with a "Change" link, optional description.
- Offline banner: a slim, refined bar (not an alarm) with queued count, e.g., "Offline · 2 reports saved on your phone". Tap for details.
- Responder home: a large segmented status control (Available / En route / On scene) usable with gloves; the current assignment as a single elegant card with hero ETA.
- Navigation screen: full-bleed map, one floating card for next turn and ETA, nothing else.
- Performance is part of quality: target 60 fps on a 3 GB RAM Android 10 phone. Avoid `BackdropFilter` blur on mobile lists and maps; use tonal surfaces instead. Keep images and shaders light.

## Web dashboard (dispatcher and admin)

Think mission control, not admin template.

- Layout: left rail = Triage Queue; center = full-bleed styled map; right = detail drawer sliding over the map. A slim top bar for weather status, connection, and user.
- Default to dark theme (`bay` / `harbor` surfaces), with a polished light theme available.
- Queue rows: compact but airy, a thin signal-colored left edge for severity, tabular wait timer, vulnerable icon + label. Selected row uses `harborHigh` and a tide edge, never a heavy fill.
- Detail drawer: hero section (type, status chip, address, wait time), then suggested units ranked with ETA, then actions. Primary action ("Assign unit") is the only filled button.
- Floating map controls: rounded 12, harbor surface, hairline border, soft shadow.
- Data viz (analytics, forecast): thin lines, restrained gridlines, direct labels instead of legends where possible, signal colors only for meaning.
- Forecast heatmap: smooth gradient from transparent → ember → signal over the muted basemap, with a clean legend and the explanation panel (thresholds, accuracy, vulnerable count per barangay, FR4).
- Keyboard: arrow keys move through the queue, Enter opens detail, Esc closes. Visible, refined focus ring (2 px tide).
- Minimum layout 1366×768; scale gracefully to 1920×1080 and ultrawide.
- Admin-only screens are hidden, not disabled, for dispatchers.

## Maps

- Custom basemap style for light and dark: desaturated land, softened roads, muted labels, water in a deep tone matching `bay`. Barangay boundaries as faint hairlines. Apply via Google Maps JSON styling or custom vector tiles, depending on the chosen map provider.
- Custom markers drawn to match the design system: clean circles with an icon, signal ring for confirmed, dashed hollow for unverified, soft halo on the selected marker. No default pins.
- Cluster markers show a tabular count in a refined circle.
- Responder markers glide between GPS updates; show "Updated 2 min ago" when stale.

## Icons and imagery

- Material Symbols Rounded, one weight (400) and optical size throughout; 20 px on dashboard, 24 px on mobile.
- No emoji, no stock photography, no generic illustrations. Empty states use a single refined icon plus clear text.

## Writing UI text

Premium products speak briefly and precisely.

- Plain words, active voice, sentence case. Buttons say exactly what happens: "Send SOS", "Assign unit", "Mark on scene".
- An action keeps its name through the flow: "Send SOS" → "SOS sent".
- Errors say what happened and what to do, without apologizing: "Location unavailable. Turn on GPS to send your exact location."
- Empty states invite action: "No active incidents. New reports will appear here."
- Use words people know (barangay, rescue boat, responder), not system terms.
- All strings in `l10n`; keep them short so Filipino translations fit.

## Avoid (these instantly look cheap or generic)

- Default Material widgets, default map tiles, default pins
- Grids of identical cards with the same drop shadow; gradient washes as decoration
- Glassmorphism everywhere, neon glows, heavy blur on mobile
- More than one filled/colored button per view
- All-caps eyebrow labels, middle-dot meta strings everywhere, arrows appended to every button, monospace for small labels
- Colored single words in headings; mixing many font weights on one screen
- Emoji icons, stock photos, clip-art
- Red for non-emergency UI; status shown by color alone
- Spinners with no text on critical actions
- Anything that makes SOS easy to trigger by accident

## Every screen needs

- Loading (subtle skeleton matching the final layout), empty, error, and offline states
- Semantics labels on icon-only buttons and the SOS button
- Checks at 360×800 (mobile) or 1366×768 (dashboard), both themes, 130% text scale

## Review checklist before calling UI work done

- [ ] Clarity first: primary action obvious within 1 second
- [ ] Tokens and shared widgets only; no hard-coded values; no default Material look left
- [ ] Mostly neutral canvas; color used only for meaning
- [ ] Grid and alignment exact; identical elements have identical spacing
- [ ] Status shown with color + icon + label
- [ ] All four states implemented, including a refined skeleton
- [ ] Touch targets ≥ 48 dp; keyboard navigation on dashboard; focus ring visible
- [ ] AA contrast in both themes
- [ ] Motion uses motion tokens; reduced motion respected; haptics on key moments
- [ ] Smooth on a low-end Android device
- [ ] Screenshot reviewed side by side with a premium reference; one unnecessary element removed
