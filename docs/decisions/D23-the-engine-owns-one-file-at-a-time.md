# D23 — the controller advances files itself, and every progress report is gated on the engine agreeing

**Status:** accepted (M4), hardened (M5) · **Touches:** `player_controller.dart`, F7, F9
**Retires when:** not expected to. Using mpv's playlist would reopen the whole
class of defect below.

## Context

`PlayerController` is the single source of truth for *which file is playing*,
and every progress report is keyed on it. libmpv is a second, independent source
of truth for the same fact, and the two are not synchronised: after a second
`open()` the engine keeps emitting the previous file's events until the new one
loads (`docs/field-notes.md` has the measured event order).

Every bug in this file has been a version of those two disagreeing.

## Decision

**We advance ourselves rather than using mpv's playlist.** A playlist index
would be a second source of truth for the fact every report is keyed on.

**Three mechanisms keep the reports honest**, and each is necessary because the
one before it is insufficient:

1. **`_switchTo` zeroes `_position` and `_duration`.** They are keyed on
   `_current`, and leaving them behind was user-visible data corruption
   (M4.R/P1): the first event after a second `open()` is deterministically
   `playing=false`, *before* any position or duration event, so the pause it
   triggers carried the finished file's seconds under the new file's index.
   Tapping Next at the end of an episode posted
   `{"file":1,"position":2.9,"duration":3}` and marked the whole show watched.

2. **`_positionIsCurrent` suppresses the report outright** until the engine has
   said where the new file is. Zeroing is necessary and not sufficient: a report
   of second 0 is still a claim about a file nothing has measured, and it would
   overwrite a pointer the server already holds.

3. **`_engineOwnsCurrent` gates every listener that feeds a report.** Neither of
   the above is sufficient *either*, because both assume the open that follows
   reaches `host.open`. When it does not — a refused pre-flight, a
   `playbackHeaders` throw — the engine keeps emitting the *old* file's events,
   which re-arm exactly what was just disarmed: a position tick sets
   `_positionIsCurrent`, a duration tick refills `_duration`, and the pair posts
   the old file's seconds under the new file's index. Measured after M5: file 0
   running to its end posted
   `{"file":1,"position":100,"duration":100,"event":"ended"}` and marked an
   episode nobody had opened fully watched.

`_engineFile` is written where the engine is handed a file and nowhere else —
**after** `host.open` returns, because until then what the engine holds is still
the previous file.

## The one listener deliberately not gated

`host.completed` has no `_engineOwnsCurrent` check, and the absence is measured
rather than an oversight. It reports `position: _duration`, which the two gates
above hold at zero for a file the engine does not own — so the report is
`notStarted` and never sent. A third gate would be a branch no input can
distinguish (§1); it survived the suite.

## Consequences

**No gapless preload**, because mpv's playlist is what would provide it. Stated
in STATE.md rather than discovered.

**One retry, bounded structurally.** `_open` takes `mayRetry` rather than
expressing the bound as a condition, because a bound written only as a condition
in front of a recursive call is one operator away from unbounded — and
`mutation_test` rewriting that `||` to `&&` made every failure retry forever,
hanging the whole gate for its 300 s timeout, three runs out of three. The
second open is now structurally incapable of asking for a third.

**A failed open pauses what is still playing.** Every failure lands *before*
`host.open`, so the engine keeps decoding whatever it had — and after `next()`
has moved `_current`, that is audio for a file the screen no longer describes,
behind a full-screen panel with no controls on it.

**`_retrySpent` is cleared by a position tick and nothing else**, because a tick
is the only evidence that playback demonstrably resumed. The guard used to latch
for the controller's whole life, and two things were wrong at once (M4.R/P2): a
genuinely broken file gave a black player with no text on it, and a session
dying mid-film after any earlier transient error never reached `api.me()` again,
so it never routed to sign-in.
