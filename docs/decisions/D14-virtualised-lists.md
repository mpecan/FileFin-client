# D14 — every list is virtualised, because nothing on this server paginates

**Status:** accepted (M3) · **Touches:** `media_grid.dart`, `media_row.dart`, `visible_rows.dart`, NF2, SPEC L2
**Retires when:** upstream adds pagination. Nothing suggests it will.

## Context

No endpoint paginates (SPEC L2). A category returns every item in one array,
`/api/home` returns whole buckets, and `homeBucket` (`db/home.go`) applies no
limit — so a heavy user's *Watched* row is as long as their library. The
category list has no documented bound either.

The whole array therefore arrives at once, and the only remaining lever is what
the client does per frame.

## Decision

Every list is `.builder`-based with an `itemCount`, so per-frame build and
layout cost is O(visible) rather than O(everything).

Concretely, and this is what the tests assert:

- **`GridView.builder` / `ListView.builder` with an `itemCount`.** A `Column`
  or a `.map().toList()` over the items makes it O(everything) again.
- **`addAutomaticKeepAlives: false`**, so a tile scrolled away is really
  disposed — which is what cancels its poster request. With keep-alives on,
  every tile ever visited stays live and holds its bytes.
- **No sorting, filtering or copying in `build()`** — all three are O(n) per
  frame. The item list is whatever the caller loaded.
- **The category tree is flattened, not nested.** Nested `Column`s inside an
  expanded tile build every descendant on every frame whether or not it is on
  screen. This is the one place people expect a tree to be nested, and it is
  the one place NF2 cannot afford it.

## Consequences

`MediaGrid` is one widget for the category listing *and* for search results.
A second copy would be this virtualisation duplicated, and long before `just
dupes` objected it would be two places for the delegate to drift apart. The
proofs above are written once and inherited by both callers.

`addAutomaticKeepAlives: false` is stated as a **guard rather than a tested
invariant**: a keep-alive only exists once a child mixes in
`AutomaticKeepAliveClientMixin`, nothing under `apps/mobile/lib` does, so
flipping the flag today changes nothing a rendering test can see. It is there
for the tile that one day does, and the flag itself is asserted on the delegate
so it cannot be dropped silently.

`visibleRows` inserts children right after their parent, which makes the walk
depth-first. `insertAll` is O(n) each time, so the function is O(n²) worst case
— a category list is directories on a disk, and the alternative loop shape costs
more than the arithmetic saves.
