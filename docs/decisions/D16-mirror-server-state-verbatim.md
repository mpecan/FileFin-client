# D16 — watch state mirrors what the server reports, including values it would reject on write

**Status:** accepted (M6.R) · **Touches:** `watch_state.dart`, `detail_state.dart`, F10
**Retires when:** upstream validates on read as well as on write.

## Context

The server validates a rating on **write** and not on **read**. A hand-edited
`meta.json` really does serve `rating: 99`, while
`POST .../rating {"rating": 99}` answers `400 rating out of range` (measured
M6.0/E-6). `WatchState` mirrors upstream's `UserState`
(`state/state.go:20-38`), and what upstream is storing in that case is 99.

## Decision

Every field is copied through exactly as reported, including a rating outside
`0..10`. The client does not normalise, clamp or zero anything on the read path.

## Alternatives rejected

**Read anything outside `0..10` as 0**, which is what the code did until M6.R.
It lost data. `applyWatchState` folds `state.rating` back onto the payload, and
`setFavorite`, `setWatched` and `clearWatched` all round-trip through it — so on
an item the server reports as 99, tapping the heart made the screen say *Not
rated* and deleted the notice explaining the value, while the server still held
99 (M6.R/P1.4). The write it followed is a total assignment to `favorite` in the
server's own fold and touches no rating at all, so the prediction was simply
wrong.

The invariant that normalisation was defending — "every state we construct is
one every mutator accepts" — did not need defending. `setRating` range-checks
its **argument**, not `state.rating`, and no other mutator reads the rating, so
no mutator refuses a state carrying 99. The only caller that could have tripped
it is `setRating(state, rating: state.rating)`, which nothing does: the picker
offers `0..10` and nothing else.

## Consequences

The UI must be able to render a value it would never let a user pick, and does:
an out-of-range rating is displayed with a notice explaining where it came from.
This is the read side of §8 — decode tolerantly — applied to a field we also
write.
