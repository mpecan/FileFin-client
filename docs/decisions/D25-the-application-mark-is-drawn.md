# D25 — the application mark is drawn from one painter, not shipped as an image

**Status:** accepted (M8.R) · **Touches:** `filefin_mark.dart`, `nav_glyph.dart`,
`tool/generate_app_icons.dart`, the launcher icons on both platforms
**Retires when:** the mark stops being a single flat shape — a gradient, a
photographic texture or per-size hand-tuning would all be reasons to ship
authored artwork instead.

## Context

The redesign gives the product a mark: a film folder with a sprocket row along
its front panel and a broad fin rising from behind the tab, the fin's base
hidden by the folder so the two read as one object. It appears in three places
at three sizes — the home-screen icon, the television rail's Home row at 24pt,
and the phone tab bar's Home tab at 20pt.

The usual way to do this is to export PNGs from the design tool and ship them:
one set for the launcher, another for the in-app glyph. That means the same
geometry exists in a dozen files, and nothing checks that they agree. A mark
retouched in one place and not the others is a defect no test can see.

Shipping an SVG instead would need `flutter_svg`, a dependency whose only
consumer would be one glyph.

## Decision

The geometry lives once, in `FileFinMarkPainter`, as Dart paths in a 96x96
square scaled to whatever size a caller asks for.

**The navigation draws it directly.** `NavGlyph` is a function rather than an
`IconData`, because the Home destination is a shape and not a character in a
font. Every other destination stays a font icon through `iconGlyph`.

**The launcher icons are rendered from that same painter** by
`tool/generate_app_icons.dart`, run with `just icons`. There is no second copy
of the geometry to forget to update.

**Cut out rather than painted over.** The folder erases the fin's base and the
sprocket holes are punched through, both with `BlendMode.clear` inside a saved
layer. Painting those in a background colour would have pinned the mark to one
ground; cutting them means the bar, the rail and the launcher tile each show
their own through the holes.

## Consequences

**The generator is not a gate, and the icons can go stale.** `just icons` is
run by hand and its output is committed. Nothing in `just check` re-renders and
diffs, because a gate that rewrites the tree it is measuring is the hazard
`mutants` already taught us — so a mark edited without re-running the recipe
ships an old launcher icon. The widget tests still catch the in-app half.

**It is shaped as a test.** Rasterising needs a real engine, so the generator
runs under `flutter test` and lives outside `test/` where the suite will not
collect it. It also needs `tester.runAsync`: under a test's fake clock the
first `toImage` never completes and the run hangs rather than failing.

**Android gains an adaptive icon.** The legacy mipmap alone would be shrunk
onto a white plate on Android 8 and up, ringing a nearly-black tile in pale
grey. The foreground layer is drawn on nothing and the ground moves to a colour
resource.

## Alternatives rejected

**Ship PNGs exported from the design tool.** The thing this exists to prevent:
twenty copies of one shape, no check that they agree.

**Ship an SVG and add `flutter_svg`.** A dependency for one glyph, and it would
still not produce the launcher icons — those must be PNGs either way, so the
second copy comes back.

**Build a custom icon font.** Makes the mark an `IconData` and leaves the
navigation untouched, which is genuinely tidier at the call site. Rejected for
the toolchain: a font is a binary nobody in the repository can regenerate or
review, which is the same opacity as the exported PNGs with an extra build step.
