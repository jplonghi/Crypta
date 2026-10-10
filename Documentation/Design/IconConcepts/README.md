# Crypta icon proposals

Created 2026-10-08 using the built-in image-generation tool. Concept previews only; not installed as the app icon.

## Selected project icon

On 2026-10-09, the user selected **A — Centered Safe**, [04-copper-centered-dial.png](04-copper-centered-dial.png). This is now the source for the macOS AppIcon and welcome/unlock VaultEmblem asset sets. Earlier proposals below are retained as design history.

Production exports use macOS `sips` to resample the selected transparent PNG without changing the design. AppIcon includes every macOS 1×/2× slot from 16 to 512 points; the in-app emblem includes 128/256-pixel images.

## Original recommendation

**Jade Enclosure** is the strongest starting point: a large custom C surrounding a small protected core, with a distinct jade-on-charcoal palette. Simplify its lighting and verify the flat silhouette at 16–128 px before production.

| Proposal | Idea | Tradeoff |
| --- | --- | --- |
| [Jade Enclosure](01-jade-enclosure.png) | Crypta initial surrounding protected data | Strong branding; security meaning is abstract |
| [Copper Vault](02-copper-vault.png) | A tactile safe door with an engraved C | Immediately communicates storage; more detail at small sizes |
| [Sealed File](03-ivory-sealed-file.png) | Portable document wrapped by a C-shaped clasp | Matches the file-first product; clasp can read as a magnet |

The generated previews need production cleanup and native app-icon export after selection. The sealed-file preview has visible edge artifacts that should be removed during refinement.

## Online references

- [1Password brand refresh](https://1password.com/blog/1password-brand-refresh): describes its keyhole and distinguishes its company logo from its app/product icon. Lesson: use one recognizable primary mark, and adapt it across contexts.
- [Bitwarden brand guidelines](https://bitwarden.com/brand/): shield identity and a documented blue palette. Lesson: security symbols communicate quickly, but a blue shield is a crowded direction for Crypta.
- [Cryptomator press kit](https://cryptomator.org/presskit/): separate logo and platform app-icon assets. Relevant adjacent encrypted-file product and useful asset-delivery reference.

These references informed the exploration; their brand marks were not used as generation inputs.

## Exact generation prompts

### 01-jade-enclosure

Use case: logo-brand. Create one polished macOS app icon proposal for Crypta, a private offline encrypted file vault. Single icon, no text or presentation board. A bold custom geometric capital C made from a thick continuous jade ceramic band, squarish curved silhouette with precisely cut horizontal terminals on right, enclosing a small solid square core centered inside. C reads first, secure enclosure second. Restrained tactile relief, crisp near-flat geometry, no reflections obscuring shape. Jade #66D9BA symbol on deep charcoal #172623 softly rounded square tile, straight-on orthographic front view, subtle edge bevel and studio light from upper left. Tile fills 85% of square canvas with generous internal padding and transparent exterior. Premium calm native Mac utility, distinctive and legible when reduced to 32 pixels. No keyhole, no shield, no padlock, no gradients into rainbow, no chain, no cryptocurrency or coin imagery, no letters besides the custom C symbol, no existing brand marks. One centered icon only.

Tool setting: transparent_background=true.

### 02-copper-vault

Use case: logo-brand. Create one polished macOS app icon proposal for Crypta, a private offline encrypted file vault. Single icon, no text or presentation board. A minimal monolithic safe door: warm satin copper rounded rectangular slab, recessed thick square border and a single short horizontal dark handle at center-right. One small geometric C-shaped recessed groove centered on the door, subtle not typographic text. Four clean broad geometric shapes total; no knobs, bolts, numbers or tiny details. Warm copper #DDA078 on deep aubergine #292231 rounded square app tile, tactile refined shallow 3D relief, front-on orthographic view, soft upper-left light, elegant native Mac desktop utility aesthetic. Tile fills 85% of square canvas with generous internal padding and transparent exterior. Clear silhouette at 32 pixels. No keyhole, no shield, no cryptocurrency/coin, no wordmark, no existing brand marks. One centered icon only.

Tool setting: transparent_background=true.

### 03-ivory-sealed-file

Use case: logo-brand. Create one polished macOS app icon proposal for Crypta, a private offline portable encrypted FILE vault. Single icon, no text or presentation board. A single ivory document silhouette with subtly folded upper-right corner. A bold custom dark blue C-shaped clasp wraps the middle of the document from its left edge, ending in two short squared terminals on the right; the clasp is an integrated geometrical part of the document, not an extra pasted badge. Suggest 'your secure portable file' with few large shapes. Ivory #F4F0E7 and slate-blue #384F70 on a muted periwinkle #8998C4 rounded square tile. Restrained dimensional relief with soft studio light, crisp clean form, native Mac utility icon, front-on orthographic view. Tile fills 85% of square canvas with generous internal padding and transparent exterior. Legible at 32 pixels. No small writing, no lines of text, no keyhole, no shield, no padlock, no chains, no existing brand marks. One centered icon only.

Tool setting: transparent_background=true.
