# Motion and Ambient Color Flow

`MotionTokens` is the shared source for interaction timing and curves. Use
`Motion.of(context)` for durations so system reduced-motion preferences turn
transitions into zero-duration UI animations.

- **Durations:** instant 90 ms, fast 160 ms, base 260 ms, slow 420 ms, hero 520 ms.
- **Curves:** standard (`easeOutCubic`), emphasized (`Cubic(0.2, 0, 0, 1)`), and exit (`easeInCubic`).
- **Drag settle:** `SpringDescription(mass: 1, stiffness: 320, damping: 26)`.
- **Layout scales:** spacing 4/8/12/16/20/24/32, radius 8/12/16/20/28, and elevation levels are centralized in `theme_tokens.dart`.

## Rules

1. Respect `MediaQuery.disableAnimationsOf(context)` for every new animation.
2. Keep animated work scoped to the smallest widget; use `RepaintBoundary` for independently painted content.
3. Do not allocate particle lists, paths, or paints in a per-frame painter.
4. Prefer transforms, fades, and bounded paints. Avoid large `BackdropFilter` and `saveLayer` surfaces.
5. Share tickers/notifiers between repeated rows; do not create an animation controller for every list item.

## Full-player Ambient Color Flow

Ambient Color Flow replaces the previous smoke effect with a single, static,
monochrome haze behind the full-player content. Several broad, overlapping
blurred shapes use one color selected from the current track's artwork. The
extractor favors colors that occupy a meaningful part of the image and have
enough saturation and brightness to read well as a background glow; it gently
normalizes that color's saturation and brightness. If no suitable artwork color
exists, the theme accent is used. The player background remains a flat theme
surface, with no extra color gradient. The haze changes directly with the
selected track; it does not animate, pulse, flash, or blend multiple colors.
Turning the setting off removes the haze entirely.
