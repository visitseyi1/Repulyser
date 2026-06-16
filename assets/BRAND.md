# Repulyser brand assets

Everything you need to use the Repulyser mark in your own project, blog post,
documentation site, or social card.

## Mark

A hexagonal shield with a pulse waveform running through it. The mark
represents two ideas at once:

- **Shield** — trust and protection of the user's onchain identity.
- **Pulse waveform** — the stream of reputation signals that flow through the analyzer.
- **Two leads at the bottom** — input (signals from attestors) and output
  (the analyzed reputation score).

## Color palette

### Light theme

| Token | Hex | Use |
|---|---|---|
| Indigo | `#4F46E5` | Primary stroke / accent |
| Cyan   | `#06B6D4` | Secondary stroke / accent |

### Dark theme

| Token | Hex | Use |
|---|---|---|
| Light indigo | `#818CF8` | Primary stroke / accent |
| Light cyan  | `#22D3EE` | Secondary stroke / accent |
| Background  | `#0F172A` | Dark background slate |

## Files

| File | Format | Dimensions | Best for |
|---|---|---|---|
| `logo-horizontal.png` | PNG | 2752×1536 | README hero, blog headers, social cards, docs banner |
| `logo.png` | PNG | 1024×1024 | Square icon on light backgrounds, app icons |
| `logo-dark.png` | PNG | 1024×1024 | Square icon on dark backgrounds |
| `logo.svg` | SVG (vector) | scalable | Source for the light icon, infinitely scalable, editable |
| `logo-dark.svg` | SVG (vector) | scalable | Source for the dark icon |
| `favicon.png` | PNG | 256×256 | Browser favicon, app launcher |
| `repulyser-brand-pack.zip` | ZIP archive | — | Everything above bundled, plus this guide |

## Usage rules

- **Keep the colors.** Don't recolor the mark. The indigo→cyan gradient is part of the brand.
- **Keep the proportions.** The shield and the pulse waveform have a deliberate ratio. Don't stretch or squash the mark.
- **Keep clear space.** Pad the mark by at least the height of the pulse spike on all sides.
- **Use the right variant for the background.**
  - Light/white background → `logo.png` or `logo.svg` (indigo + cyan)
  - Dark background → `logo-dark.png` or `logo-dark.svg` (lighter shades)
- **Don't add effects.** No drop shadows, no glow, no 3D rotations. The mark is designed to be flat.
- **Don't modify the wordmark.** The "Repulyser" wordmark and the "Onchain Reputation Analyzer" tagline are part of the horizontal lockup. Don't re-typeset them.
- **Attribution is appreciated but not required** (MIT-licensed).

## Direct downloads

| File | Download |
|---|---|
| Horizontal hero | [logo-horizontal.png](./logo-horizontal.png) |
| Square icon (light) | [logo.png](./logo.png) |
| Square icon (dark) | [logo-dark.png](./logo-dark.png) |
| SVG source (light) | [logo.svg](./logo.svg) |
| SVG source (dark) | [logo-dark.svg](./logo-dark.svg) |
| Favicon | [favicon.png](./favicon.png) |
| **All-in-one brand pack** | [repulyser-brand-pack.zip](./repulyser-brand-pack.zip) |

## Quick embedding

### README / docs

```markdown
![Repulyser logo](assets/logo-horizontal.png)
```

### HTML

```html
<img src="https://raw.githubusercontent.com/visitseyi1/Repulyser/main/assets/logo-horizontal.png"
     alt="Repulyser — Onchain Reputation Analyzer" width="600" />
```

### SVG inline (best for docs sites)

```html
<!-- paste the contents of assets/logo.svg directly into your HTML for a crisp, theme-able icon -->
```

## License

MIT — same as the rest of the Repulyser project. See [LICENSE](../LICENSE).
