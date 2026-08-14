# D15 — `continueIndex 0 / continueSeconds 0` is read as "no pointer"

**Status:** accepted (M4) · **Touches:** `watch_state.dart`, `detail_state.dart`, F8, F9
**Retires when:** the detail payload carries the stored pointer rather than the
derived view. Nothing suggests upstream intends that.

## Context

The server stores a resume pointer as a **ref string** — `"SxE"`, `""` for a
single-file folder, or `"#N"` 1-based (`state/engine.go:17-31`). The detail
payload does **not** carry it. It carries the *derived view*
(`continueIndex`, `continueSeconds`), and the two are not the same thing: an
unresolvable pointer is reported as `0`/`0`, which is indistinguishable from no
pointer at all.

So a client reconstructing state from a detail response has to guess, on
exactly one input.

## Decision

`WatchState.fromDetail` reads `0`/`0` as **no pointer**.

This is a tie-break, not a derivation. The two readings differ on one class of
input — a report that crosses 90% of an item with `fileCount == 1` — and agree
everywhere else. This one was chosen because a fresh or stale pointer is the
likelier ground truth behind `0`/`0`, and a stale pointer resolves to index -1
upstream, which is what an absent pointer resolves to.

## Consequences

**The residual divergence persists; it does not close itself.** On a single-file
item whose pointer genuinely sits at `(0, 0s)`, a crossing report makes this
client predict `seconds = round(position)` where the server keeps `0` — and
because the pointer only ever moves forward, the client stays ahead until a
later report *exceeds* its own value.

Transcribed from a live v0.20.3 session on a single-file film: after
`{position: 95, duration: 100}` the client holds 95 and the server holds 0;
after a rewind to `{position: 50}` the server moves to 50 and the client still
holds 95. Once the user rewinds, the optimistic value is simply wrong, and
`watched` being set does not hide it — un-watching returns the item to the
`continue` row with that stale offset.

A consumer must therefore **re-read the detail** after a crossing report on a
single-file item rather than trust the prediction. That is what
`PlaybackOutcome.needsDetailRefetch` is, and it is the only input for which F9
pays a round trip. STATE.md carries the divergence as a known limitation.
