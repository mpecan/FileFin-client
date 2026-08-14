# D17 — F10's four writes are applied to the screen before the server answers

**Status:** accepted (M6) · **Touches:** `detail_state.dart`, `watch_actions.dart`, `watch_state_controls.dart`, F10
**Retires when:** upstream stops making these four writes total assignments —
i.e. if any of them starts deriving one field from another.

## Context

A toggle that waits for a server to answer is unusable over cellular: the tap
appears to do nothing for a second and people press it again.

## Decision

The screen is updated from `applyWatchState` **first**, the write goes out, and
the value is put back if the write fails. The failure is named rather than
swallowed.

Exactly one write is in flight at a time, and a tap during it is refused
visibly (G5).

## Why the prediction is exact, rather than merely likely

This is the half that makes the optimism honest. The four writes — `setWatched`,
`clearWatched`, `setFavorite`, `setRating` — are **total assignments** in the
server's own fold (`media.go:406/434/472/489`): each writes the field it names
and copies the rest through. `filefin_core`'s four mutators are those same
assignments, so the state handed to `applyWatchState` is the state the server
now holds.

**The contrast with F9 is what makes that safe to say.** `applyProgress` has an
ambiguity class — `WatchState.fromDetail` has to guess whether a wire `(0, 0)`
means a fresh pointer or an absent one (D15), and a crossing report on a
single-file item is where the guess can be wrong, which is why
`PlaybackOutcome.needsDetailRefetch` exists. None of these four reads a pointer,
infers one, or depends on how `(0, 0)` was read: `setWatched` keeps whatever
pointer it was given and `clearWatched` drops it outright.

So F10 needs **no divergence-refetch path** and no second `PlaybackOutcome`.

## Alternatives rejected

**A queue of pending writes.** With three writes pending, "what does a failure
revert to" has no answer a user could predict, and that ambiguity is exactly
what would turn the optimistic value into a lie. Refusing the second tap is
worse UX and better behaviour.

**Disabling controls while a write is in flight.** A control that greys out has
no way to say why. The controls stay tappable, a second tap is refused with a
sentence, and the only thing `busy` draws is a progress bar.

## Consequences

`applyWatchState` folds through `deriveView` rather than copying `WatchState`'s
fields across, because `MediaDetail` carries the derived view rather than the
stored pointer — which is what makes a pointer past the end of the file list
land as `0`/`0` here exactly as the server would report it. Every
`files[i].watched` moves with it; leaving the file rows stale was invisible
until something drew them.

The detail route pops `true` when it wrote, **including for a write still in
flight** (`wroteOrWriting`). `wrote` alone was wrong: the pop is read as the
screen closes, so *tap favourite, then Back before the server answers* popped
`false` and the home rows stayed stale for the rest of the session even though
the write landed (M6.R/P1.3).

The residual race is named rather than hidden: the reload is issued as the route
pops, so on a slow link it can overtake the write that caused it and refetch the
pre-write order. Closing that properly means holding the back gesture until the
write answers, which is a worse trade. STATE.md carries it as debt.
