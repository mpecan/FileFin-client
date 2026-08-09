# State

Where the project is, milestone by milestone, and what it knowingly owes.

| | |
|---|---|
| **Done** | **M0** — workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture, R1 retired, R4 licensing position recorded, then remediated against three adversarial reviews |
| **Done** | **M1** — `filefin_core`: wire models, extension-type IDs, URL building, the resume engine, `decide()`, then remediated against three adversarial reviews |
| **Done** | **M2** — `filefin_api`: the HTTP client, the cookie jar, F3's 401-retry, F15's certificate pinning, and `just it` against a real `filefin` |
| **Done** | **M3** — `apps/mobile`: the app shell, F1's add-server flow, F2's sign-in, and F4's category tree, virtualised poster grid and detail view; every gate's Flutter branch |
| **Done** | **M4** — playback, the direct path: F7, F8, F9, F13, NF6, D10's TLS refusal, and the `PlaybackHost` seam that makes libmpv testable |
| **Done** | **M5** — the HLS path and F12's messaging: `TranscodingDisabled`, a `HEAD` pre-flight that refuses before the engine opens, the panel that says why, and a live HLS suite against the real binary |
| **Done** | **M6** — F5, F6 and F10: search with a debounce and eleven scopes, the three home rows, favourite/rating/the two un-watches, and a three-tab shell whose tabs are built only when they are selected. All three proven against the real binary |
| **Exit criterion met** | `just check` exits 0 **and** `just it` exits 0 on a clean tree, on a machine with the binary. **NF2 is met BY PROXY** — see M3 below, and `docs/verification-backlog.md` row 1 |

**"Clean tree" is a claim this file has got wrong before, which is why it is
spelled out rather than asserted.** At M1 it was wrong: three
untracked probe files (`zz_attack_test.dart`, `zz_probe2_test.dart`,
`zz_probe_test.dart`) sat in `packages/filefin_core/test/` when M1 was declared
done. `just test` runs them, and one wrote to a hard-coded absolute path under a
scratch directory — it would have failed on any other machine. They were deleted and
M1 re-verified without them: `just check` exit 0, coverage 100%, 174 of 174
mutants, `git status --porcelain --untracked-files=all` empty. No figure this
file reports ever depended on them.

M2 hit the same class of problem from a different direction and it is recorded
in full below: `mutation_test` left rewritten sources on disk twice, in
**untracked** files where `git status` shows `??` and no diff can reveal
anything. `git add -N` on every new file is the practice adopted in response.

**M3 found the sharp edge on that practice, and it is worth knowing before it
costs someone an hour.** `git checkout -- <path>` on an intent-to-add path
**truncates the file to zero bytes** rather than refusing: there is no committed
blob to restore, so it restores the empty index entry. A probe loop that used
`git checkout --` to undo a deliberate edit destroyed `async_controller.dart`
outright, and the first sign of it was `dart format` reporting the file
"changed". `cp` to a temp file, not `git checkout --`, is the undo for a file
that has never been committed.


---

## M6 — what was built

**Search, home rows and F10 were the milestone, and all three are in.** The two
pure functions M6 rests on, the six endpoints, the port and the fake, F10 on
the detail screen, F6's three rows, F5's search, the shell that reaches them,
and three live suites against the real binary — including the POST/DELETE
watched distinction, which M6.0 measured for the first time in this
repository's history and `watch_state_test.dart` now gates.

**It was finished across two sessions.** The first landed M6.0-M6.4 and every
layer below F5/F6's UI and stopped on wall clock; the second landed M6.5-M6.8.
Both are recorded below in order, and the numbers are per session where they
differ.

### M6.0 — nine experiments, and three of the plan's own predictions were wrong

Every answer was taken against a **private copy** of `$FILEFIN_RUN` started on
a free port; the shared seed was never mutated.

#### E-1 — search is case-INSENSITIVE, substring, and escapes LIKE wildcards

`q ∈ {movie, MOVIE, mOvIe, Movie} × field ∈ {all, title}` produced **eight
byte-identical bodies**. The brief's "case-sensitive, measured at M2" is not
recorded anywhere in this repository and is wrong; `db/search.go:52` builds
every text predicate as `LOWER(<col>) LIKE ? ESCAPE '\'` and `likePattern`
lowercases `q`.

The match is a **substring** (`q=irect` finds *Direct Play Movie*) and the
wildcards are escaped: `q=%`, `q=_`, `q=100%` and `q=M_vie` each returned `[]`.
Those empties are the proof rather than an absence — an unescaped `%` would
match every row and an unescaped `_` would match any title with a character in
it.

All eleven scopes were exercised live and each returns rows for a matching
query, so **SPEC §3.2's list of seven was wrong** and M6 fixes it.

#### E-2 — the mirror is stale in a `FixtureRun` copy, and it is BACKWARDS

Predicted: three empty home rows. Measured: worse, and it changes how any live
F6 test has to be written. `FixtureRun._decorrelateWatched` rewrites `meta.json`
and never touches the copied `user_state` table, so every copy starts
internally inconsistent:

| | film `e4285edb34d5` | show `919ac9caad25` |
|---|---|---|
| `meta.json` (the truth) | watched **true** | watched **false** |
| `user_state` (the mirror) | watched 0, favorite 1, rating 8, has_progress 1 | watched **1** |
| `GET /api/media/{id}` | `watched:true, favorite:false, rating:0` | `watched:false` |
| `GET /api/home` | in `continue` **and** `favorites` | in `completed` |
| search / category listing | `watched:false` | `watched:true` |

So **every listing's `watched` flag is the opposite of the detail's**, in every
copy on every machine — which silently defeats `_decorrelateWatched`'s own
stated purpose for exactly the payloads a home screen renders. Three seconds
later the answers were byte-identical: `discoveryInterval: 0` really does mean
nothing reconciles.

One write repairs one row. After `POST .../favorite` on the film the mirror row
was rewritten from `meta.json` (`watched=1, favorite=1, rating=0,
has_progress=0`) and home, search and the category listing all agreed with the
detail.

**Consequence:** a live home suite must create the state it asserts on, and
`fixture_run.dart` has to write the mirror as well as `meta.json`. Neither is
done — see "What M6 did NOT finish".

#### E-3 — every write re-stamps `updated`, and that re-orders every bucket

`UpdateStateGet` (`importer/manager.go:79`) stamps `us.Updated =
time.Now().Unix()` whatever the fold did, and every bucket is
`ORDER BY us.updated DESC`. Measured with both items in `continue`: progress on
the show gave `[Show, Film]`; progress on the film gave `[Film, Show]`; and
**`POST .../rating 7` on the show gave `[Show, Film]`** — a rating re-ordered a
row that has nothing to do with ratings. The same held for `favorites`.

This is what makes home rows unpredictable client-side, and it is why the
detail route answers "did anything get written" rather than "what changed".

#### E-4 — `int.tryParse` vs `strconv.Atoi`: ONE divergence, and not the predicted one

Predicted: whitespace. **Wrong.** Dart's parser skips leading and trailing
whitespace itself — for U+00A0 as well as for a space — and Go's `TrimSpace`
trims the same set, so `.trim()` is belt-and-braces rather than the fix.

The real divergence is the **`0x` prefix**: `int.tryParse('0x7E4')` is 2020 and
`Atoi` refuses it. Proven live rather than inferred, because `0x7E4` *is* 2020:
`field=year&q=0x7E4` came back `[]` where `q=2020` returned the row, so the
empty answer can only be a refusal.

Everything else agrees: `+2020`, `02020`, ` 2020 `, `\t2020\n` all parse both
sides; `2e3`, `2_020`, `2020.0`, `٢٠٢٠`, `20 20`, `s` and `0b…` are refused
both sides; and the 64-bit boundary matches exactly at `9223372036854775807`
and above it. `decade` strips **one** trailing `s` after lowering, measured
both ways (`2020s` → one row, `2020ss` → none).

`searchIsRunnable` therefore validates the `Atoi` *grammar* — `^[+-]?[0-9]+$` on
the trimmed string — and range-checks with `int.tryParse`.

#### E-5 — the POST/DELETE watched distinction, exercised for the first time

Six steps against v0.20.3 on the two-file show:

| step | detail | home |
|---|---|---|
| `DELETE .../watched` (reset) | `watched:false, 0/0` | in no row |
| `POST progress {file:0, 45/100}` | `watched:false, 0/45` | **continue** |
| `POST watched {"watched":true}` | `watched:true, 0/45` | **completed** |
| `POST watched {"watched":false}` | `watched:false, **0/45**` | **continue** |
| `POST watched {"watched":true}` | `watched:true, 0/45` | completed |
| `DELETE .../watched` | `watched:false, **0/0**` | **no row at all** |

`meta.json` agreed at every step: the POST arm kept `progress {file:"1x1",
seconds:45}` and the DELETE removed the key. So SPEC §3.5, `docs/server-api.md`
and `filefin_core`'s `setWatched`/`clearWatched` doc comments are all correct,
and the wording M6.4 ships describes something that actually happens.

#### E-6 — a rating is validated on WRITE and not clamped on READ

Write: `-1` → `400 rating out of range`, `0` → `204`, `1` → `204`, `10` →
`204`, `11` → `400`, `99` → `400`, `-2147483648` → `400`.

Read: `meta.json` hand-edited to `rating: 99`, server restarted, `GET
/api/media/{id}` → **`"rating": 99`**. So `WatchState.fromDetail`'s
normalisation is reachable, and so is the detail screen's out-of-range notice —
which is not decoration but correctness, because a `DropdownButton` whose value
is not among its items asserts rather than rendering.

Two ordering facts fell out of the same run: `{"rating":99}` on a **nonexistent**
id is `400` while `{"rating":5}` on it is `404` (the range check precedes the
lookup), and a malformed body on a nonexistent id is `400` while a valid
`favorite` body on it is `404` (`decodeJSON` precedes `folderFor`).

#### E-7 — an unknown `field` degrades to `all`, and an empty `q` returns `[]`

`field` absent, `''`, `bogus`, `TITLE` and `Title` all behave as `all`. Proven
with `q=sine`, which appears in the *plot* only: `all` / `TITLE` / `bogus`
returned one row and `title` / `description` returned none. So the switch is
case-SENSITIVE and `TITLE` is an unknown value rather than a spelling of
`title`. `q` absent or empty answers `200 []`, never the library.

#### E-8 — `POST /api/admin/rebuild` does re-derive `user_state`

The stale show row (`watched=1, has_progress=1, updated=1786248868`) became
`watched=0, has_progress=0, updated=1` — exactly `meta.json` — and home and
search then agreed with the detail. C4 still forbids the client calling it;
`docs/verification-backlog.md` row G is the standing check per upstream bump.

#### E-9 — the `flutter_tester` deaths do NOT correlate with concurrency

Orphans killed first (there were none) and the tree clean. Twelve runs of the
app suite at the default concurrency and twelve at `--concurrency=1`:

| arm | failures | wall clock |
|---|---|---|
| default | **0 / 12** | 87 s (7.25 s per run) |
| `--concurrency=1` | **0 / 12** | 328 s (27.3 s per run) |

Neither arm reproduced a failure, so nothing here can attribute the four
historical sightings to concurrency — and the proposed remedy costs **3.8×**,
multiplied again by `just mutants`, which runs the suite once per mutant. **No
gate change.**

Two further sightings landed during M6's own `just check` runs, both
`TestDeviceException(Shell subprocess crashed with unexpected exit code -10)`
in `real_mpv_player_test.dart`, both green on an immediate re-run. Twenty-four
standalone runs clean and two failures inside `just check` is a pattern the
concurrency hypothesis does not explain; `docs/verification-backlog.md` row H
carries the numbers.

### What M6 built, step by step

**M6.1 — `filefin_core`.** `applyWatchState(MediaDetail, WatchState)` folds a
watch-state write back onto the payload it came from, through `deriveView` so a
pointer past the end of the file list lands as `0`/`0` exactly as the server
reports it — and it folds **every `files[i].watched`**, which
`media_detail_page.dart` was not doing. That screen folded four fields and left
the file rows carrying whatever the last fetch said: invisible while nothing
drew them, wrong the moment something did.

F10's optimistic update needs no divergence-refetch path, and the doc comment
says why rather than asserting it. The four writes are total assignments in the
server's own fold (`media.go:406/434/472/489`) and none of them reads or infers
a pointer, so the `(0, 0)` ambiguity that forces
`PlaybackOutcome.needsDetailRefetch` on F9 cannot arise. `PlaybackOutcome` was
not extended and no second one was invented.

`searchIsRunnable(query, field:)` answers whether the server will actually run
a query. It validates the `Atoi` grammar rather than trusting `int.tryParse`,
for the reason E-4 measured.

Both directions on the fold, on real code rather than on a hypothetical:
deleting `|| i < pointerIndex` from `deriveView` turns *"the file rows move too,
and they are what the page was dropping"* red; reversing the per-file index
turns that plus two properties red; deleting the `files:` fold entirely turns
four tests red. Restored, green.

**Scout fix, in its own commit.** `startSecondsFor` switched over sealed
`ResumeChoice` and ended `_ => 0`, because its `ResumeAvailable` arm is
*guarded* and a guarded pattern cannot make a switch exhaustive. Proven both
ways: with a third variant added to the sealed class,
`dart analyze --fatal-infos` reported "No issues found" against `_ => 0` and
failed with `non_exhaustive_switch_expression` against the two explicit arms.

**M6.2 — `filefin_api`.** `home()` and `search()` join `client_browse.dart`;
F10's four writes are `client_watch_state.dart`, a `part` for the same reason
`client_playback.dart` is one; `_sendDelete` joins `_send` and `_sendJson`, and
exists because the VERB is what separates the two un-watch operations.

`client.dart` was 363 lines and could not absorb six routes, so the read-only
routes moved to `client_browse.dart` first, in a commit of their own — a pure
move, all 178 tests untouched.

`setRating` guards `0..10` locally and throws a `RangeError`, tested at −1, 0,
10 and 11 with the stub asserting it saw **no request at all**. The matcher
asserts the error's `invalidValue`, `start`, `end` and `name`: three mutants
living inside `RangeError.range`'s own arguments survived a bare
`isA<RangeError>()` and are killed by that.

**M6.3 — the port and the fake.** Six abstract methods, six delegations, and
the four writes deliberately NOT routed through `FakeLibraryApi._answer` —
with `T` bound to `void` its throw arm is unreachable, so a fake set up to fail
quietly succeeds (measured at M4; this is the third place the trap has to be
named, and it matters most here because F10 reverts on failure). `_write` takes
a `Completer` gate rather than a delay, because "one write in flight" needs a
write provably still running when the second tap lands.

`calls` records `setWatched(id, false)` and `clearWatched(id)` as two different
strings — the tripwire a collapsing UI trips — and the port test asserts the
wire sees `POST` then `DELETE` on ONE path, because the path alone cannot tell
them apart.

**M6.4 — F10 on the detail screen.** `watch_actions.dart` imports no widget, so
every case is a plain `test()`. It publishes optimistically, reverts on a
`FileFinApiException`, allows exactly one write in flight, and refuses a second
with a sentence rather than by greying a control out — a greyed control has no
way to say why. `busy` draws a progress bar; that is its only consumer, and it
is a real one.

The watched control is the honest surfacing of the asymmetry: an unwatched item
gets *Mark watched*; a watched one gets a menu of two entries, each with its
consequence written out — *"Keeps where you left off, so it goes back to
Continue watching"* and *"Forgets the position too, so it leaves every list."*

The rating is a whole-number picker with *Not rated* as its first entry,
because 0 is how the server clears one. **The out-of-range branch survived
E-6 and is correctness rather than polish**: the server does not clamp on read,
and a `DropdownButton` whose value is not among its items asserts rather than
rendering. Tested at −1, 0, 10, 11 and 99.

**The centrepiece proof, run in both directions.** Pointing
`markWatched(watched: false)` at `api.clearWatched` turns *"Mark as unwatched
keeps the position: Continue 0:45 is back"* red, along with two more; pointing
`clearWatchState` at `api.setWatched(false)` turns *"Clear watch state forgets
it: no Continue anywhere"* red. Restored byte-for-byte and green.

**M6.5 — the grid out, and the rows in.** `MediaGrid` is `CategoryGridPage`'s
body, moved unchanged so search could draw the same thing: the same builder
delegate, the same max-extent grid, the same explicit 400 px cache extent, the
same `addAutomaticKeepAlives: false`. What stayed behind is what is genuinely
about a *category* — which listing to fetch, the leaf in the app bar, and an
empty state whose sentence search could not share, because "no matches for X"
has to quote a query the grid knows nothing about.

`HomePage` draws the three buckets `GET /api/home` returns, in the order it
returns them, and `MediaRow` is one labelled strip of it. Both are virtualised:
`homeBucket` applies no limit, so a heavy user's *Watched* row is as long as
their library. **Refetched, never predicted** — every write re-stamps `updated`
and every bucket is `ORDER BY us.updated DESC` (E-3), and a prediction that was
*more* right than the stale mirror would still look like a bug.

Tested from `home_populated.json` because it is captured rather than written
and carries one property no hand-written literal would have thought to include:
**the film is in `continue` AND in `favorites`.** The buckets are independent
predicates over one `user_state` row, not a partition. The fixture asserts that
property itself before anything is drawn, so a re-capture that lost it fails
loudly instead of making the headline case vacuous.

**M6.6 — search, and the three ways it can show nothing.** Four files:
`SearchQuery` is what is being asked for, `search_field_labels.dart` is every
word the screen says about a scope, `MediaSearchController` is the debounce and
the request, `SearchPage` is the widgets.

The three ways are a blank box, a query the server will not run, and a query
that ran and matched nothing. **On the wire they are indistinguishable** — all
three are a `200` with an empty array, or no request at all — so if the client
does not tell them apart nobody can. `searchNotice` is one pure function
holding that decision and the page has no branching of its own.

Every switch over `SearchField` is exhaustive with no default arm, because
`db/search.go:70` degrades an unrecognised `field` to `all` rather than
erroring: a scope the client can send but cannot describe would produce
plausible results under the wrong label.

`MediaSearchController`, not `SearchController`: `package:flutter/material.dart`
already exports one and two in scope is an ambiguous-import error.

**M6.7 — the shell, and what a cold start costs.** `LibraryShell` owns Home,
Library and Search and the routes out of them. **Tabs are built on first
selection**: `IndexedStack` and `TabBarView` both build every child
immediately, so either would have made a launch fetch the home rows, the
category list and an empty search at once, for two screens the user may never
open. A cold start issues exactly one request and it is `home`. A detail route
that wrote reloads the rows exactly once, from any tab, including when Home has
never been on screen.

`TickerMode` is paired with `Offstage` because `Offstage` stops layout and
paint and **not** tickers — and it had to be asserted directly, since inverting
its condition passed all 518 tests. That was the one survivor `just mutants`
found in this step.

Ten existing cases were rewired: Home is tab 0, so anything about the tree taps
Library first, and the two app-level `SessionExpired` cases now fail `home()`
too, because a dead session is dead for every route.

**M6.8 — the live suites.** `watch_state_test.dart` is the exit criterion: six
ordered steps, each differential in the way `playback_test.dart`'s are — the
prediction `applyWatchState` makes from the payload the server HAD, compared
field by field against the payload it has AFTER, plus which home bucket the
item landed in. `search_test.dart` pins E-1 against the binary rather than
against a fixture that could be re-accepted, and ends with a differential case:
for fourteen inputs, `searchIsRunnable` false implies the server returned
nothing, with a positive control so "everything was empty" cannot pass for a
proof. `home_search_live_test.dart` drives the two new screens over payloads a
real server sent.

Both floors were raised, **43 → 56** and **25 → 30**, and each raise was proven
to refuse by deleting one test.

### The E-2 decision, and why the harness was left alone

E-2 measured that a `FixtureRun` copy starts with the `user_state` mirror
**contradicting** `meta.json` in both directions, so `/api/home`, search and
every category listing report the OPPOSITE of `/api/media/{id}` until something
writes. The plan offered two answers: teach `fixture_run.dart` to write the
mirror, or have every live home/search suite create the state it asserts on.

**The suites create their own state, and the harness was left alone.** Three
reasons, in order of weight:

1. Writing the mirror means transcribing `db.UpsertUserState`'s projection —
   which columns, which predicates — into our harness. That is a second copy of
   upstream logic in a place no test covers, and an upstream schema change would
   make it **silently wrong** rather than loudly absent. `_repointCache` already
   shows what it costs to keep such a transcription honest: it has to verify
   itself afterwards, precisely because a moved column would otherwise leave the
   harness doing nothing.
2. A suite that writes what it reads is reproducible on a machine whose seed was
   never captured against, which is the same argument `_decorrelateWatched`'s own
   comment makes for replacing the whole `state.<user>` block.
3. It exercises the write path on the way to the read, so the state under test
   was produced the way a user would produce it.

The cost is named rather than hidden: `fixture_run.dart` still hands every suite
a copy whose mirror disagrees with its truth, and any future suite that reads a
listing without writing first will see it. That is why the divergence is
**asserted** — `watch_state_test.dart`'s last case pins it in both directions
and then repairs it with one write, so the day upstream starts reconciling on
startup, this repository finds out from a red test rather than from a user.

### The mutation numbers, per commit and as a distinct union

Summing per-commit runs double-counts, because a file changed in two commits is
mutated twice — M5.R/G-F5 says so and M6 is the first milestone where the gap
is large. Both figures:

| commit | files | mutants | undetected |
|---|---|---|---|
| `refactor(core)` scout fix | 1 | 9 | 0 |
| `feat(core)` applyWatchState + searchIsRunnable | 3 | 25 | 0 |
| `refactor(api)` the read routes into a part | 2 | 16 | 0 |
| `feat(api)` home, search, the four writes | 3 | 29 | 0 |
| `feat(app)` the port and the fake | 1 | 3 | 0 |
| `build` the mutation cap | 0 | — | — |
| `refactor(ui)` the file list out | 4 | 137 | 0 |
| `feat(ui)` F10 on the detail screen | 4 | 91 | 0 |
| `docs` M6 | 0 | — | — |
| **sum, first session** | | **310** | **0** |
| `build` the per-mutant timeout | 0 | — | — |
| `refactor(ui)` the grid out | 2 | 6 | 0 |
| `feat(ui)` the home rows | 2 | 21 | 0 |
| `feat(ui)` search | 4 | 43 | 0 |
| `feat(app)` the shell | 2 | 28 | 0 |
| `test(it)` the live suites | 0 | — | — |
| **sum, second session** | | **98** | **0** |
| **union, second session** | 10 | **98** | **0** |

**The distinct union is 230**, measured in one run against the milestone's base
(`FILEFIN_MUTANTS_BASE=53dbeff just mutants`): 167 over 7 files in
`apps/mobile`, 29 over 3 in `filefin_api`, 34 over 4 in `filefin_core`, 0
undetected in all three. So summing overstates by 80 — `client.dart`,
`client_browse.dart`, `media_detail_page.dart` and `file_list.dart` were each
mutated twice.

The `apps/mobile` arm took **25m19s**, which is why the first session stopped
where it did: each further UI commit cost that much gate time, and three were
left.

**The second session's distinct union is 98 — the same as its sum — and that is
a property of the diffs rather than luck.** Its four code commits touch **ten
lib sources and no file twice**:

| commit | lib sources |
|---|---|
| `refactor(ui)` the grid out | `media_grid.dart`, `category_grid_page.dart` |
| `feat(ui)` the home rows | `home_page.dart`, `media_row.dart` |
| `feat(ui)` search | the four `search_*.dart` |
| `feat(app)` the shell | `library_shell.dart`, `app.dart` |

`git show --name-only` over the four confirms the sets are disjoint, so the
double-counting M5.R/G-F5 warns about — and which cost the first session 80
mutants of overstatement — cannot arise here. **Keeping each commit's diff to
one file set was the deliberate lever on wall clock**, and this is the
arithmetic that shows it worked: 98 mutants measured once rather than 178
measured twice.

A confirming whole-union run (`FILEFIN_MUTANTS_BASE=8dd0d3e just mutants`, ten
files in one pass) was started and **abandoned at ~50 minutes** rather than
being allowed to hold the tree. It left a live `ScrollCacheExtent.pixels(-400)`
in `media_grid.dart`, found by diffing the lib sources immediately afterwards
exactly as CLAUDE.md says to, and restored before anything else was done. The
number above stands on the disjointness argument, which is checkable from the
git history in a second rather than in an hour.

### Gate proof log — M6

| Gate | Direction | Evidence |
|---|---|---|
| exhaustive switch | fail | a third `ResumeChoice` variant against `_ => 0`: `dart analyze` exit **0**, "No issues found" |
| exhaustive switch | pass | the same probe against the two explicit arms: exit **3**, `non_exhaustive_switch_expression` |
| `deriveView`'s per-file fold | fail | `|| i < pointerIndex` deleted: one named test red |
| `applyWatchState`'s files fold | fail | index reversed: three tests red; fold deleted: four red |
| `markWatched` / `clearWatched` | fail | each pointed at the other: the matching widget case and the matching `WatchActions` case red, both ways |
| `setRating`'s guard | fail | three mutants inside `RangeError.range`'s arguments survived `isA<RangeError>()`; killed by asserting `invalidValue`, `start`, `end`, `name` |
| mutation whole-run cap | fail | cap forced to 5 s: exit **1**, "exceeded its 5s whole-run cap" |
| mutation whole-run cap | pass | real cap 1932 s: exit **0**, 137 mutations, 0 undetected, 19m30s |
| per-mutant timeout | fail | at `baseline * 6` (42 s) a **detected** `-400` cache-extent mutant reports as a timeout: exit **1** |
| per-mutant timeout | pass | at `baseline * 12` the same diff exits **0**, 6 mutations, 0 undetected, 0 timeouts |
| `MediaRow`'s empty guard | fail | deleted: *"an empty bucket draws no heading"* and *"an empty row is nothing at all"* red; the one-item side stays green |
| home de-duplication | fail | `favorites` filtered against `continue`: *"the captured payload really does hold the film twice"* red |
| the search scope on the wire | fail | `field: asked.field` → `SearchField.all`: four cases red across two files |
| the unrunnable short-circuit | fail | deleted: *"an unparseable year is refused before the socket"* and its page twin red |
| `searchNotice`'s `&&` | fail | `&&` → `||`: *"a RUNNABLE year with no rows says no matches"* and its page twin red |
| lazy tabs | fail | all three built in `initState`: the two *"costs no request"* cases red |
| the home reload | fail | unconditional: *"a detail that wrote NOTHING does not reload"* red; removed: the two write cases red |
| `TickerMode` | fail | condition inverted: *"an offstage tab stops ticking"* red — and it passed all 518 tests before that case existed |
| `setWatched` verb | fail | pointed at `_sendDelete`: `watch_state_test.dart` step 3 red against the real binary |
| `clearWatched` verb | fail | pointed at `_sendJson {"watched": false}`: step 6 red, `Expected: <0>  Actual: <45>` |
| integration floor, api | fail | one test deleted: exit **1**, "only 55 tests ran … the committed floor is 56" |
| integration floor, app | fail | one test deleted: exit **1**, "only 29 tests ran … the committed floor is 30" |
| `file-size` | ratchet | **6 warnings → 4**, held at 4 through the second session |
| `comments` | ratchet | held at **1** — see the note below |
| `MAX_UNCOVERED` | ratchet | held at **0**; coverage 100% |
| constitution | ratchet | 0 across all seven, unchanged |

**`comments` rose to 2 and was paid back inside the milestone.** Extracting
`file_list.dart` carried its `//` rationale with it into a much smaller file,
and 13 of 63 lines is 20% where the same comments were under the line inside a
414-line page. Paid the way M3.R paid it: the rationale moved into the `///`
doc comment of the declaration it describes. Recorded here rather than left for
a reviewer to find, because the gate reports a warning and exits 0 — the
"never rise" half of that ratchet is enforced by review, not by the script.

### Two things the milestone found that were not on anyone's list

**The mutation gate's whole-run cap counted FILES where it meant MUTANTS.**
`run_cap` read `(n * cmd_timeout + baseline_secs) * 2` with `n` the number of
changed files, so for any diff under eight files it collapsed to the 600-second
floor. A four-file diff needing 19m30s was killed at 10:00 and reported as a
wedge. Fixed to a per-mutant budget (40 per changed file at the measured
baseline, doubled), proven both directions.

**The kill left a live mutant on disk, and `dart analyze` passed on it.**
`playback_settings_sheet.dart` was left carrying `500 * -1000 * 1000` in
`meteredWarnChoices`. It was found by a test asserting the value, not by any
gate — and `git diff --stat` did not reveal it either, because the mutant sat
inside a hunk that had a legitimate change in it. CLAUDE.md already says "after
any interrupted run diff the lib sources before doing anything else"; what M6
adds is that **`--stat` is not diffing them**.

### What M6 did NOT finish, stated plainly

The first session left F5 and F6 without screens and both floors at 43 / 25.
The second session built `media_grid.dart`, `media_row.dart`, `home_page.dart`,
the four search files and `library_shell.dart`, added the three live suites and
raised both floors, so **that gap is closed**. What is left is listed under
"Debt" below rather than here, because none of it is a half-built thing.

Two items the first session flagged, and where they stand:

1. **E-2's consequence is answered by decision rather than by code** — the live
   suites create the state they assert on and `fixture_run.dart` is unchanged.
   The reasoning is under "The E-2 decision" above, and the cost is that any
   *future* suite reading a listing without writing first will still see a
   mirror that disagrees with its truth.
2. **The listing `watched` flag is now tested against the real server in both
   directions.** `watch_state_test.dart`'s last case asserts that a fresh copy
   really does report the opposite of the detail, and that one write repairs it.

**Two flakes were seen and neither is new.** `real_mpv_player_test.dart` sank
two `just check` runs with `TestDeviceException` (segfault, then exit code -10)
and was green on the file alone both times; `playback_live_test.dart` sank one
`just it` with "did not complete" and was green on re-run. Both are
`docs/verification-backlog.md` row H, and E-9 already showed the concurrency
hypothesis does not explain them. No gate was changed for either. The count for
this milestone is now **four sightings in this session on top of the two the
first session recorded**, which is worth knowing before anyone reads a single
red run as a regression.

### Debt this milestone knowingly accepts

- **Search remembers nothing between visits.** The tab is rebuilt on first
  selection and the box starts empty, deliberately: a search box that reopens
  holding somebody's last query is a surprise rather than a convenience. There
  is also no filter within a category (no server route, C3).
- **`fixture_run.dart` still hands every suite a copy whose `user_state` mirror
  disagrees with its `meta.json`**, by decision (E-2, above). A future suite
  that reads a listing without writing first will see it, and nothing in the
  harness will say so — the tripwire is `watch_state_test.dart`'s last case.
- Tags are still not built (A11 renewed): `GET /api/tags` is documented and
  captured, the `tag` scope takes typed text rather than a vocabulary, and
  building a `Tag` model now would be §1 speculation. Recorded again with the
  reason so a third milestone need not re-derive it.
- F10 is on the detail screen only. Nothing writes watch state from a grid tile
  or a home row.
- Home rows are refetched rather than predicted, and the reason is E-3 rather
  than convenience.
- One write in flight per screen; the queue was named and rejected because
  "what does a failure revert to" has no predictable answer with three pending.
- **The mirror-vs-truth divergence is exposed, not reconciled.** `docs/server-api.md`
  gained "The mirror and the truth"; nothing in the client tries to repair it.
  It is now *asserted*, which is a different thing from being fixed.
- Large-response behaviour and the debounce under real typing are unmeasured —
  `docs/verification-backlog.md` rows E and F. Both screens are virtualised on
  M3's NF2 proxies (a bounded live-widget count and a `SliverChildBuilderDelegate`
  over 500 and 2000 items), which is the same evidence F4's grid has and the
  same distance from a frame-timing measurement.
- **The 300 ms debounce is asserted on both sides of its boundary under a fake
  clock**, which is the opposite of the case it exists for: `flutter_test` types
  twelve characters in zero simulated milliseconds. Row F is the device
  measurement and it has not been made.
- Backlog rows **A, B and C** are filed against M6 and are **not** retired by
  it. A (libmpv and a `503` segment) and B (HLS seek latency, one ffmpeg per
  session) both need a long seeded item, which is a seeding change that would
  re-cut the captured fixtures for no M6 behaviour; C (`Media(start:)` on the
  shipped Android and iOS libmpv) needs a device, which M6 never had. Each
  re-filed here with its reason rather than slipped silently, as M5 re-filed
  row 22.
- **`FILEFIN_MUTANTS_TIMEOUT` is a fifth environment override that CLAUDE.md's
  "three, and they are the complete list" does not mention.** It arrived at
  M5.R and is a per-mutant timeout — it relaxes a bound, which is the class the
  ratchet section is about. Not touched here; named so it is a decision next
  time rather than an omission.

---

## M5 — what was built

| Step | Deliverable |
|---|---|
| M5.0 | A measurement session, no commit. **Twelve experiments; one destroyed a premise of the plan, two confirmed the two the design rests on, and one destroyed a prediction in the reassuring direction** |
| M5.1 | `TranscodingDisabled` in `errors_playback.dart`, the `415` mapper arm, `describeApiError`'s arm — and the **`_` default arm deleted** from `describeApiFailure`, which is the hole §1 of the plan found |
| M5.2 | `FileFinClient.requirePlayable` — a `HEAD` pre-flight on the file route, `validateStatus < 400` so the `307` returns, `_refuseHtml` on **2xx only** |
| M5.3 | `LibraryApi.requirePlayable` and an argument-aware fake for it, deliberately not through `_answer<void>` |
| M5.4 | The guard in `PlayerController._open()`, `unplayable`, and the tests that pin it on **both** sides |
| M5.5 | `_UnplayablePanel` — full-screen, because the engine was never opened and there is nothing behind a banner |
| M5.6 | `capture_fixtures.sh` emits the four blocks that were hand-appended, adds the FILE route's 415 against a transcoding-disabled server, and puts the config back; three new `check-fixtures.sh` assertions, each proven to fail |
| M5.7 | `FixtureRun.create(transcoding:)` and five integration tests against a real disabled server; floor 38 → 43 |
| M5.8 | `hls_live_test.dart` and `transcoding_disabled_live_test.dart`; floor 15 → 22 |
| M5.9 | This section, four verification-backlog rows, and the nine document errors the plan listed |

### The verdict, up front

**Playback itself needed no client change at all.** `PlaybackRequest.url` was
already `api.fileUrl(...)`, `transport.dart` never fetches media bytes, and
libmpv follows the `307` and decodes the server's HLS unaided — measured before
a line was written (M5.0/E-C): duration, an audio track, a position past one
second, a backwards seek and completion, all through the unmodified
`MediaKitPlaybackHost`. So M5 is **one error variant, one bounded pre-flight,
one `if`, one panel and the tests**, and saying that plainly is better than
inventing an "HLS adapter" to justify the milestone.

### M5.0 — the twelve answers

Two servers were run side by side over private copies of the seeded run
directory (`transcodeEnabled: null` and `false`). **`$HOME/development/filefin-test/run`
was never modified**, which matters: a stray `false` there turns the existing
307 integration test red on unmodified code.

- **E-A — the pre-flight is a `HEAD`.** Go 1.22's `ServeMux` matches a `GET`
  pattern for `HEAD`, so it really reaches `handleStream`: `307` for the
  transcoding show, `200 video/mp4` for the film, `415` on the disabled server,
  `404` for a bad index, `401` unauthenticated, and `200 text/html` for a path
  the SPA catch-all answers. A one-byte `GET Range: 0-0` gives identical
  statuses and moves a body — 81 bytes of Go's redirect HTML on one arm, a
  media byte on the other.
- **E-B — `transcode` stays `true` with transcoding off.** LOAD-BEARING, and it
  holds. `fileNeedsTranscode` never consults whether transcoding is *enabled*,
  so the client's guard still fires. File route → `415 transcoding disabled`;
  hls route → `415 not transcodable`; the film still answers `200` with
  `Accept-Ranges: bytes`.
- **E-C — the `307` plays.** duration **3023 ms** (mpv takes `#EXTINF:3.023`
  from the playlist, not the 3.000 s source), one audio track, first position
  past 1 s at 1023 ms, completion at 2956 ms.
- **E-D — `Media(start:)` IS honoured on an HLS VOD playlist.** LOAD-BEARING,
  and nothing had ever tested it. `startAt: 1200 ms` → `[0, 1200, 1289, …]`;
  the `startAt: 0` control → `[0, 89, 156, …]`. F8 over HLS works and M5 owes
  no fallback.
- **E-E — the event order after a second `open()` is IDENTICAL on both paths.**
  The prediction that they might differ is destroyed, in the reassuring
  direction: `tracks=∅ → playing=false → position=0 → duration=0 →
  playing=true → tracks=1 → duration → first real position`, mid-playback, on
  both. `_switchTo`'s zeroing and `_positionIsCurrent` cover `next()` between
  two HEVC episodes exactly as they cover the direct path, so **the
  data-corruption bug this experiment was looking for does not exist.** One
  refinement: an emptied `tracks` precedes `playing=false`; the load-bearing
  half of the claim in `player_controller.dart` — `playing=false` before any
  position or duration event — holds.
- **E-F — a backwards seek over HLS lands.** 2223 ms → 400 ms, no new
  `filefin-hls-*` session directory, no ffmpeg process observable at all.
- **E-G — the pre-flight starts no transcode.** 10 HEADs + 10 one-byte GETs
  created **zero** session directories (13 → 13 → 13); one playlist request
  created one (13 → 14).
- **E-H — `503 segment unavailable` is unprovokable here, and that is the
  answer** rather than a claim that the behaviour is fine. The playlist is one
  `seg0.ts` with `#EXT-X-ENDLIST` and the segment answered in 1.3 ms. Backlog
  row A.
- **E-I — the "before".** Real client, real libmpv, disabled server:
  `PlayerController.failure` was mpv's own sentence, verbatim —
  `Failed to open http://127.0.0.1:8299/api/media/919ac9caad25/file/0.` — over
  a black surface, with `_recover` spending its retry on a failure that can
  never succeed. That is what F12 exists to replace.
- **E-J — the compile alarm reaches three files, and not the one that
  mattered.** `error_presentation.dart:50`, `error_presentation_test.dart:329`,
  `error_mapper_test.dart:354`. **`player_controller.dart` was absent**, because
  `describeApiFailure` had a `_` arm — §1 of the plan found it by grep and this
  measured it.
- **E-K — dio returns the `307`, and the plan was wrong about the guard.**
  `validateStatus: (s) => s < 400` makes a `3xx` return with `Location`
  present; the `415` throws `badResponse`, with an **empty body under HEAD**.
  And the finding that changed the design: **the `307` carries
  `Content-Type: text/html; charset=utf-8`**, because `http.Redirect` writes an
  HTML body. The plan's "`_refuseHtml` on the response" would have refused the
  success case while letting the SPA catch-all's `200 text/html` through —
  backwards. The guard is 2xx-only and is tested at 206, 300 and 302.
- **E-L — the gate numbers, before any edit.** `file-size` **6 warnings**,
  `comments` **1 warning and 13 files under 20 counted lines**, constitution
  clean, coverage **100% (2201/2201)** with the ratchet at **0**. STATE.md said
  both gates reported zero; they do not, and that sentence is corrected above.

### The design, and the three things it deliberately does not do

```
PlayerController._open()
  ├─ if (file.transcode) await api.requirePlayable(detail.id, _current)
  │        415 → TranscodingDisabled → F12's panel, engine never opened
  │        307 → proceed          2xx → proceed
  ├─ await api.playbackHeaders()          (unchanged)
  ├─ subtitles, listen                    (unchanged)
  └─ host.open(...)                       libmpv follows the 307 itself
```

**Eager, not classify-on-error**, because a 415 is deterministic and permanent:
there is nothing for `_recover`'s retry to achieve, the eager path never puts a
black surface in front of anyone, and the lazy path would weave a second
question into a three-line function M4.R had to fix three defects in.

**Guarded on `file.transcode`**, because SPEC §3.4 makes a 415 on the file
route reachable only for a file that needs transcoding. The flag can be stale;
that is accepted debt and it self-heals, because a file that became
direct-playable answers `200` and the pre-flight passes.

Not done, each because a document suggested it: `followRedirects` stays **off**
(dio never fetches media bytes, and turning it on re-opens M2's measured
downgrade attack for no benefit); no `RefuseReason.transcodingDisabled`,
because every variant of that enum must be constructible from `decide`'s own
inputs and a 415 is not (A10, M1); and `transcode.DirectPlayable` is not
reimplemented.

### What the gates said

- `just check` **exit 0**; `just it` **exit 0**.
- `file-size` **0 errors, 6 warnings** — held, not raised. `error_mapper_test.dart`
  crossed 400 when the 415 cases were added to it and they were moved into
  `errors_playback_test.dart` rather than left to raise the count.
- `comments` **0 errors, 1 warning** — held. `error_presentation.dart` crossed
  15% under a four-line rationale comment, which moved into the variant's
  `///` doc where it belongs.
- Coverage **100%**, `MAX_UNCOVERED` **0**.
- The constitution baseline is unchanged at **0 across seven checks**.

### Gate proofs, both directions

- **`dead_types`.** With every construction **and** every `switch` pattern for
  `TranscodingDisabled` renamed away, `just constitution` reports
  `dead_types — 1 violation(s), baseline 0` and exits non-zero; restored, `no
  new violations`, exit 0. **Worth recording: the gate's regex cannot tell a
  constructor call from a `switch` pattern**, so a variant that is only ever
  *matched* satisfies it. Deleting the mapper line alone — which is what the
  plan proposed as the proof — leaves the gate green, because the tests
  construct it.
- **The three new `check-fixtures.sh` assertions.** Each was proven by editing
  `error_shapes.txt`, running `fixtures-accept` so the checksum half passes,
  and confirming the structural half fails: dropping the `transcoding disabled`
  line → exit 1, dropping `not transcodable` → exit 1, re-adding the retracted
  `decided by EXTENSION` block → exit 1. Restored: exit 0, and the manifest is
  byte-identical to before the probes. **The first attempt at those greps was
  satisfiable by prose** — the capture writes a comment above each block naming
  the same words, so an unanchored `grep` passed against a file whose payload
  line had been deleted. They are `grep -qx` now.
- **The `file-size` and `comments` budgets** were re-measured before and after
  every commit rather than assumed.
- **The two integration floors** are raised from 38 → 43 and 15 → 22 and the
  suites run exactly that many.

### Mutation

95 mutants over the M5.1 diff, all killed. 119 over the pre-flight diff, of
which **two survived the first pass** and both are worth keeping:

**The per-commit figures do not add up to a distinct total, and adding them was
wrong.** `just mutants` is diff-scoped but re-mutates whole FILES, so a file
touched by two commits contributes its whole mutant set twice. The union over
the M5 diff is **255 distinct mutants**, all killed; the sum of the per-commit
runs is 314 and means only "314 mutant runs happened" (M5.R/G-F5).

- `client_playback.dart` — `if ((response.statusCode ?? 0) < 300)` rewritten to
  `<= 300`, and nothing objected. The tests exercised 206 and 302, which sit
  either side of the boundary without touching it; `300 Multiple Choices` is a
  redirect status and must be allowed through. **That is M4.R/T9's lesson
  recurring: a boundary tested on one side only.** A `300` case kills it.
- `player_page.dart` — `fontSize: 18` rewritten to `-18` in the new panel.
  Nothing can assert a point size that carries no meaning, so the literal was
  deleted rather than asserted; the panel now inherits the type scale like its
  two siblings, which also stops it fixing the size against the system font
  setting (backlog row 13).

### Debt M5 knowingly accepts

- The pre-flight is one extra round trip on every transcoding open, including
  every `next()`. It is bounded, it starts no transcode (E-G), and it is
  guarded so a direct-play open never pays it.
- It is guarded on a `transcode` flag that can be stale. Self-heals.
- The seeded HLS item is **3 seconds and one segment**, so every multi-segment
  behaviour is unmeasured: segment 503 recovery (row A), seek latency and the
  one-ffmpeg-run-per-session promise (row B).
- HLS was measured against **Homebrew's** libmpv 0.41.0, not the shipped
  Android and iOS builds — `Media(start:)` in particular (row C).
- Nothing verifies what the HLS path **draws** (row 16).
- The disabled server is configured through `.filefin.json` rather than through
  the admin route a real administrator would use, because C4 forbids calling
  one.
- Backlog row 22 stays open a second milestone, now with a stated reason.
- `hlsIndex`/`hlsSegment` keep no production consumer, deliberately.

### Two things found in passing that are not M5's

- **`real_mpv_player_test.dart` segfaults intermittently.**
  `TestDeviceException(Shell subprocess crashed with segmentation fault.)`
  takes the whole file down and reports every test as "did not complete".
  Measured at HEAD with all M5 changes stashed: **1 failure in 6 runs**; with
  them, 1 in 5. It sank three `just check` runs. It is a property of that file
  and libmpv rather than of any diff, it needs its own investigation, and per
  §11 that makes it a note here rather than a guess in the code.
- **Five orphaned `flutter_tester` processes, eight hours old**, four of them
  still pointing at a `scratchpad/mutcopy/` mutation copy from a session before
  this one. They were killed. Whether they were what made the segfault frequent
  is not established — the flake reproduced at HEAD before they were found —
  but they are the cheapest thing to check first, and CLAUDE.md now says so.
- **A latent fixture hazard, fixed:** `curl -D -` writes real HTTP headers,
  which end CRLF, and `git config core.autocrlf=input` strips them **on
  commit**. So a `SHA256SUMS` accepted from a freshly captured working tree
  would not match a fresh clone, and `fixtures-verify` would go red in CI for a
  reason nobody could reproduce locally. Measured: HEAD's committed
  `error_shapes.txt` carries 0 CR bytes and a freshly captured one carried 13.
  The capture now pipes through `tr -d '\r'` and refuses any CR it finds.
- **`fixtures-capture` was not idempotent, in the same way `just it` was not at
  M4.R.** `meta.json` is filesystem truth, so the favourite, rating and
  progress the script POSTs survived it — and the *next* run captured them into
  `media_detail_directplay.json`, whose entire job is to be the payload with no
  state on it. Measured: a second consecutive capture turned `favorite:false
  rating:0 continueSeconds:0` into `true / 8 / 2` and gave the show
  `watched:true` and `continueIndex:1`. The script now clears per-user state
  before capturing and asserts the result, and two consecutive captures produce
  byte-identical fixtures.

### What a review pass found, and what was done about it

- **`next()` does not pause the engine when the new file's pre-flight
  refuses.** `_switchTo` zeroes the position bookkeeping and `_open()` fails
  before `host.open`, so mpv is still holding — and still playing — the
  *previous* episode behind a full-screen panel that says nothing can play.
  This is not new: every `_open()` failure since M4 has left the old media
  loaded, including a `playbackHeaders` throw. What M5 changed is how visible
  it is, because the panel replaces the controls a user would reach for.
  Recorded rather than patched: pausing on the failure path is a behaviour
  change that wants its own test on both sides, and inventing it at the end of
  a milestone is how an untested branch gets shipped.
  **RETRACTED, and it was worse than under-stated.** This paragraph ended
  "it is reachable only by turning transcoding off between two episodes of one
  item", which is false: SPEC §3.4 decides per FILE, so a mixed-codec item on a
  statically configured `transcodeEnabled:false` server reaches it with nothing
  changing and no administrator doing anything. And the consequence was not
  only the audible one described above — M4.R/P1's data corruption came back
  through it. Both are fixed in M5.R below.
- A dead position collector in `hls_live_test.dart`'s resume arm — written and
  never read — was deleted.

### Checked and found already consistent

CLAUDE.md §4 and `docs/architecture.md` on version pinning. The M5 plan listed
this as an open contradiction "since M2"; it is not — §4 says "Every dependency
is pinned exactly on introduction… not only pre-1.0 ones" and
`docs/architecture.md` records the M3 reconciliation that made it so. Nothing
to fix, and it is recorded here so a fourth pass does not go looking again.

### M5.R — remediation of three adversarial reviews of M5

Three reviews, each in its own worktree with its own seeded server: C
(correctness), T (test genuineness), G (gates and fixtures). Twenty-two
findings. **One was user-visible data corruption and the two reviewers
disagreed about it**, so the first thing done was to reproduce both.

#### The disagreement, settled by reproducing both

C measured `postsAfterRefusal = []` after a refused `next()` and concluded the
pointer does not advance. T re-emitted a duration event and reached a corrupt
POST. **Both are right, under conditions one line apart**, and running them
side by side is what shows which:

```
PROBE C-F1  AFTER-NEXT unplayable=true hostCalls=[open(…/file/0), play] current=1
            AFTER-TICK current=1 position=0:00:43 duration=0:00:00 reports=[]
PROBE T-F1  AFTER-DURATION-REEMIT reports=[file1@44.0/100.0:checkpoint]
            AFTER-COMPLETED       reports=[file1@44.0/100.0:checkpoint,
                                           file1@100.0/100.0:ended]
```

`_switchTo` zeroes `_duration`, and `decideReport` skips a zero duration as
`notStarted` — so with **real libmpv**, which emits `duration` once per open,
nothing is posted and C's measurement is exactly right. Emit one more duration
event and the skip stops firing: file 0 running to its end posts
`{"file":1,"position":100,"duration":100,"event":"ended"}` and marks an episode
nobody opened, and cannot open, fully watched. **That is M4.R/P1 verbatim,
through a second route, and it was protected only by a rule about something
else.**

Two more halves of the same defect, both reproduced:

```
PROBE C-F1 blast   AFTER-RECOVER opens=[…/file/0@0ms, …/file/1@2400ms]
PROBE C-F3         failure=Playback could not start: ConnectionFailed: …
                   unplayable=null opened=0 calls=[] — no retry, no way back
```

#### The fix: the guard is keyed on FILE IDENTITY, which is what C-F2 asked for

`_engineFile` records the file the engine was actually handed, written after
`await host.open` returns and nowhere else. `_engineOwnsCurrent` gates the
`position` and `duration` listeners. `_openFailed` pauses the engine when it is
holding anything, and routes everything that is not a `TranscodingDisabled`
through the same bounded retry `_recover` uses.

Three deviations from what the reviews prescribed, each with its reason:

- **`_positionIsCurrent = false` on the refusal path: not added.** With the
  identity gate the old file's ticks never set it, so on the `next()` path the
  assignment is dead — and on the other path, where `_recover` re-opens the
  file the engine is still holding, it is live and *wrong*: that flag is what
  preserves F8's resume offset.
- **The `completed` listener is NOT gated.** It reports `position: _duration`,
  and the two gates above hold `_duration` at zero for a file the engine does
  not own, which `decideReport` skips. Measured: with the other two gates in
  place, removing the `completed` gate left **all 179 tests green** — a branch
  no input can distinguish is a §1 violation and an unkillable mutant.
- **C-F3 took the retry option, not the Retry button.** The banner over a
  never-opened engine is still a black rectangle with live controls; that is
  recorded below rather than fixed.

**And the retry is bounded TWICE, because the first version hung `just
mutants`.** Expressed only as a condition — `if (error is TranscodingDisabled
|| _retrySpent) return;` before a recursive `_open()` — the bound is one
operator away from not existing: `mutation_test` rewrote that `||` to `&&`,
every failure retried forever, and the gate ran into its 300 s per-command
timeout. It reported `Undetected Mutations: 1, Timeouts: 1` with **`0 not
detected` in each of the three files** — a gate that hangs cannot tell a
survivor from an interruption, which is the shape CLAUDE.md's `mutation_rules`
already excludes whole loop rules for. It reproduced **three runs out of
three**, so it was not the machine.

Found by sampling `git diff` of the mutated sources every ten seconds
throughout a run and looking for the mutant that stayed on disk for 300 s:
`&&` where the neighbouring sample had `||`. `_open` now takes `mayRetry`, and
the one retry calls `_open(mayRetry: false)` — the second open is
**structurally incapable** of asking for a third. Under the same `&&` mutation
the suite now finishes in seconds and **three tests go red**.

#### Every finding, and what happened to it

| ID | Verdict | What was done |
|---|---|---|
| T-F1 | **Confirmed, critical** | `_engineFile` + `_engineOwnsCurrent`; `_openFailed` pauses; 4 new tests |
| C-F1 | Confirmed, and its blast radius understated | same fix; the `_recover` offset poisoning has its own test |
| C-F2 | Confirmed | the same identity key — that IS C-F2's prescription |
| C-F3 | Confirmed | non-415 pre-flight failures go through the bounded retry; 3 tests |
| C-F4 | Confirmed | one `CancelToken` for the controller, cancelled by `dispose`, passed to all three requests; `_open` returns before `_listen` when disposed; 3 tests |
| C-F5 | Confirmed | the 415 arm is `when _isFileRoute(requested)`; 7 tests |
| C-F6 | Confirmed | "The file you asked for", and "turn it on" rather than "back on" |
| T-F2 | **Confirmed, decoy** | `isNot(anyElement(startsWith('open(')))` at both sites; whole suite grepped |
| T-F3 | Confirmed | asserts the pre-flight COUNT and the second sentence, not `host.opened` |
| T-F4 | Confirmed | a third live test: the same show against a transcoding-ENABLED server |
| T-F5 | Confirmed | the claim deleted; `playback_no_cookie_test.dart` now controls BOTH routes; every `_measure` wait is named |
| T-F6 | Confirmed | `hasLength(1)` |
| T-F7 | Confirmed | reworded: it reproduces production's sequence and claims no coverage |
| T-F8 | Confirmed | `try/finally`, and every `firstWhere` replaced by a subscription this function can cancel |
| G-F1 | Confirmed | five more anchored assertions, each proven to fail |
| G-F2 | Confirmed | PROVENANCE.md lists all twelve blocks, in the order the capture writes them |
| G-F3 | Confirmed | `grep -qiE` over an alternation, in both scripts |
| G-F5 | Confirmed | 314 is a run count; the union is 255. Corrected above |
| G-F7 | Confirmed | `git rev-parse --git-path hooks` / `--git-common-dir` |
| G-F8 | Confirmed | the `-x` rationale now says three of five |
| reap | Confirmed | orphans only (`ppid == 1`), directories older than an hour |
| G-F4, G-F6 | Left | recorded by G as pre-existing/cosmetic and unchanged this pass |

#### Proof log — every fix broken, and the test that went red

Applied to production source with `cp` for the undo, suite run, source restored
and compared byte for byte. `real_mpv_player_test.dart`'s known segfault is
excluded from the readings below.

| Mutation | Result |
|---|---|
| the `position` identity gate deleted | `player_refusal_test.dart: … reopens the new file at ZERO` RED |
| the `duration` identity gate deleted | `… no ended report ever marks the unopened file watched` RED |
| **all identity gates deleted (the M5 behaviour)** | **3 RED, including `… nothing the old file does is posted under the new index`** |
| the `completed` gate deleted | ALL GREEN — see the deviation above; the gate was removed |
| `await host.pause()` deleted | `… the engine is PAUSED rather than left audible` RED |
| the whole retry deleted | 2 RED in `a transient pre-flight failure is retried, once` |
| `\|\|` → `&&` in the retry guard (**the mutant that hung the gate**) | 3 RED, in seconds — it used to run for 300 s and report nothing |
| `_retrySpent` dropped from `_openFailed`'s guard | `a recovery that already spent the retry does not spend a second` RED |
| `_retrySpent = true` deleted from `_recover` | `transcoding turned off mid-session stops at one retry` RED — **it was green before T-F3's fix** |
| `if (_disposed) return` deleted from `_open` | `… nothing is opened on an engine dispose has already torn down` RED |
| `_work.cancel()` deleted from `dispose` | `… the request itself was cancelled` RED |
| `cancelToken:` dropped from `requirePlayable` | same test RED |
| `cancelToken:` dropped from `playbackHeaders` | `… every request the open makes carries the token` RED |
| `cancelToken:` dropped from `subtitleText` | same test RED |
| `415 when _isFileRoute(...)` → `415 =>` | 6 RED in the route-scoping group |
| `[^/]+$` → `[^/]+` in the route predicate | the `/sub/{k}` case RED |

**T-F2's decoy, proven in isolation** rather than by argument, over the exact
list `FakePlaybackHost` records when `open` IS called:

```
+0: THE DECOY: passes even though open was called
+1 -1: THE FIX: fails, as it must [E]
  Expected: not some element a string starting with 'open('
    Actual: ['open(PlaybackRequest(http://nas/file/0))', 'play']
```

#### Gate proofs, both directions

- **The five new `error_shapes.txt` assertions.** Each line deleted from the
  fixture, `fixtures-accept` run so the checksum half passes, `verify`
  re-run: `bad file index`, `rating out of range`, `WEBVTT`,
  `Content-Range` and the `401…429` sequence all → **exit 1**. Restored →
  exit 0 and the fixture bytes are identical to before the probes.
- **The widened retracted-claim tripwire.** `decided by the EXTENSION`,
  `decided by extension` and `decided by the file suffix` appended in turn,
  each accepted and re-verified: **exit 1** for all three. The old
  case-sensitive literal caught none of them.
- **`hooks-status` in a linked worktree.** Old script, run with the worktree as
  cwd: `ERROR: … pre-commit (not installed) post-commit (not installed)`,
  exit 1 — structurally unsatisfiable, because `.git` is a file there. New
  script: exit 0 from the worktree **and** from the main checkout. Still fails
  correctly on a hand-made stub: `pre-commit (a plain file, not a symlink …)`,
  exit 1.
- **The scoped reap.** One server whose parent is a live shell and one
  reparented to pid 1, both matching `pgrep -f "$BIN serve"`:
  `LIVE SURVIVED (correct)` / `ORPHAN REAPED (correct)`. The old code killed
  both, which is how it reaped a reviewer's server mid-session.

#### What the gates say

- `just check` **exit 0**; `just it` **exit 0** (68 tests: 43 + 25).
- Tests **1440** (404 + 178 + 858), up from 1422. Live floor **22 → 25**.
- Mutation: **140 mutants over the M5.R diff** (106 in `apps/mobile` across
  `player_controller.dart`, `player_failure.dart` and `player_page.dart`, 34 in
  `error_mapper.dart`), **all killed, 0 timeouts, 16m15s** — against 21m and
  38m with the hanging mutant burning the 300 s bound. `!mayRetry` is the one line in the diff the
  rule set produces no mutant for — a brace-less `if` with no operator in its
  condition — and it is deliberately redundant with `_retrySpent`: it exists to
  make the recursion structurally impossible, not to be the bound.
- Coverage **100% (2269/2269)**, ratchet **0**.
- `file-size` **0 errors, 6 warnings** — held. `player_controller.dart` reached
  the 600-line HARD limit when the `CancelToken` landed, so
  `describeApiFailure` and `PlaybackOutcome` moved into `player_failure.dart`
  as a **part**: no import churn, and the warning count is unchanged because
  the controller is still over 400 and the new file is not.
- `comments` **0 errors, 1 warning** — held. The part file's rationale lives at
  the `part` directive rather than in the part, which is where a reader looking
  for "why is this split" actually is.
- Constitution baseline unchanged at **0 across seven checks**. The first draft
  of `_isFileRoute` used a `RegExp` spelling the path out and
  `undocumented_endpoint` counted it as a new endpoint — correctly, since a gate
  cannot tell a pattern from a route. It compares path SEGMENTS instead.
- `test/fixtures/SHA256SUMS` changed for **PROVENANCE.md only**, which is in the
  manifest by design (§8): the provenance table is part of what the bytes mean.
  `KEYS.txt` is unchanged.

#### Left undone, plainly

- **C-F3's UI half.** A pre-flight failure that survives its retry still
  renders the failure banner over `host.buildSurface()` and a live
  `PlayerControls` for an engine that was never opened — a black rectangle with
  controls that drive nothing. The retry closes the dead-end; the surface is
  still wrong, and a Retry button on `_FailureBanner` when nothing was opened is
  the remaining half.
- **`hls_live_test.dart`'s memoised measurement still collapses five tests into
  one failure.** The waits are named now, so the message says which stage died,
  but a broken stage still reddens all five.
- **The `real_mpv_player_test.dart` segfault: re-measured, not explained.**
  **0 failures in 12 consecutive runs of that file alone**, against M5's 1 in 6
  and 1 in 5 — but it then took down a whole `just check` anyway, with
  `TestDeviceException(Shell subprocess crashed with unexpected exit code
  -10.)` on `mutation_test`'s BASELINE run, which aborts the gate before a
  single mutant is applied. So: still live, still roughly M5's rate, and the
  file-alone measurement says nothing useful. And T-F8's leak cannot be the cause of *this* file's crash —
  the leak is in `test_live/hls_live_test.dart`, which `just test` never runs
  and which gets its own `flutter_tester` process. What T-F8 did fix is real
  and was measured as a condition rather than as a crash: `_measure` left
  listeners on an mpv context `tearDownAll` was about to dispose, which is the
  condition M4.R/T4 named. Treat the flake as open.
- **G-F4** (`dead_types` counts constructions in test files) and **G-F6**
  (`capture_fixtures.sh` exits 0 on some SIGTERM interruptions) are unchanged;
  both were recorded by review G as pre-existing or cosmetic.

---

## M4 — what was built

| Step | Deliverable |
|---|---|
| M4.0 | A measurement session, no commit. **Nine experiments; two answers reversed a plan premise and one reversed a documented server behaviour** |
| M4.1 | `filefin_core`: `ProgressEvent`, `roundReportedSeconds`, `PlaybackTransport`, `RefuseReason.unverifiablePlaybackTls`, `progressIntervalSecs`, `playback/progress_policy.dart`, `playback/resume_choice.dart` |
| M4.2 | `filefin_api`: `BadRequest`, `postProgress`, `subtitleText`, `playbackHeaders`, `fileUrl`, `subtitleUrl`, `playbackTransport`, and `PlaybackSessionHeaders` — named so `secret_tostring` watches it |
| M4.3 | `app_no_raw_http` refuses `package:media_kit` outside two named adapter files, **landed before the first import**; `check-toolchain.sh` gained libmpv; CI installs `libmpv2` |
| M4.4 | `PlaybackHost`, `NetworkStatus`, `PlaybackPrefs`, `SavedServer.wifiOnly`/`allowUnverifiedPlayback`, and `LibraryApi`'s seven new methods with an argument-aware fake for every one |
| M4.5 | `mpv_player.dart` and `media_kit_playback_host.dart` — the only two files that may import media_kit — plus a libmpv-backed suite inside `just test` |
| M4.6 | `ProgressReporter` (F9): no timer, no clock, `lastSent` advancing only on a successful POST |
| M4.7 | `PlayerController` (F7, F8, F13, NF6, playback's half of F3) |
| M4.8 | `PlayerPage`, `PlayerControls`, the metered prompt, the D10 banner, Play/Continue on the detail screen and tappable file rows, and `PlaybackSettingsSheet` — reached from the signed-in tree's app bar, and the only thing that makes `wifiOnly` and `allowUnverifiedPlayback` **writable** rather than only readable |
| M4.9 | `integration_test/playback_test.dart` and `test_live/playback_live_test.dart` + `playback_no_cookie_test.dart`, both `run-integration.sh` floors raised and proven |
| M4.10 | This section, six verification-backlog rows, and the SPEC/CLAUDE.md corrections the measurements forced — including E5's retraction |
| M4.R | Remediation of three adversarial reviews. **One user-visible data corruption**, one unnecessary ratchet raise resting on a false measurement, two vacuous live tests and a suite that was not reproducible against its own fixture capture — all below |

**Mutation after M4.R: 270 mutants over the remediation diff, all killed** —
221 in `apps/mobile` across 7 files, 49 in `filefin_core` across 2, 0 timeouts.
The first pass left exactly one survivor and it is recorded under T9 below,
because it is the interesting one: a boundary guard tested on one side only.

**Numbers as measured, and re-measured after M4.R.** `dart analyze
--fatal-infos --fatal-warnings .` clean; **1385 unit tests** — 372 in
`apps/mobile`, 155 in `filefin_api`, 858 in `filefin_core`. Coverage **100%
(2201/2201)** with
`MAX_UNCOVERED` **back at 0** — the M4 raise to 2 was unnecessary and its stated
reason was false; see M4.R/G1. **`file-size` and `comments` do NOT report zero,
and this sentence used to say they did** (corrected at M5.0/E-L, by running
them): `file-size` is **0 errors and 6 warnings** and `comments` is **0 errors,
1 warning and 13 files under 20 counted lines**. Those are the budgets — a gate
warning may fall or hold and never rise — so a reader who took the old number at
face value would have treated their first warning as a regression they had
caused. `dupes` is under the 5% threshold. The constitution
baseline is still **0 across seven checks**, now with two more greps under
`app_no_raw_http`. `just it` is **53 tests across two live suites**.

**Mutation: 576 mutants in the M4 diff, all killed** — 327 in `apps/mobile`,
110 in `filefin_api`, 139 in `filefin_core`, 0 timeouts. That number was reached
in two passes and the first one is the interesting half.

### The 17 surviving mutants, and what each cost

The first complete run left **16 undetected in `apps/mobile` and 1 in
`filefin_core`**. Seven were killed with assertions, six by changing the code so
the mutant became killable, and four were excluded as genuinely equivalent.

**Killed by assertions (7).**
- `player_controls.dart` — the scrubber's three `max <= 0` guards, in both
  directions. Writing the assertion found a **real bug**: `.clamp(0, max.toInt())`
  ran *before* every guard, so a negative duration — which mpv reports for a
  stream it has not finished reading — threw `ArgumentError: 0` out of `build`
  and took the whole player screen with it. Three copies of the guard became one
  `scrubbable` flag read twice, and the clamp now runs against the clamped max.
- `player_controls.dart` — `index < 0` in the subtitle menu. `<=` makes the
  **first** sidecar in every list silently turn subtitles off, and the two
  existing subtitle tests tap `Slovenian` (index 1) and `Off` (-1), so both
  still passed. The new test taps `English` (index 0).
- `player_controller.dart` — two mutants that widen the NF6 lifecycle guard's
  third disjunct to "anything that is not `hidden`", which would make a
  `detached` app pause and report. The list of three states is now the contract,
  asserted.
- `playback_settings_sheet.dart` — `'Wi-Fi only'` → `'Wi+Fi only'`, the
  arithmetic rule reaching inside a string literal. The four row labels are now
  asserted by their exact words.
- `progress_policy.dart` — `>= watchedThreshold` → `==`. Every single-file
  `isTrue` case in the suite sat at exactly 90/100, so the boundary had only one
  side. `==` is also the shape a real player spends its whole crossing in: mpv's
  ticks land where they land and 90.0/100.0 exactly is the one value it will
  almost never report.

**Killed by changing the code (6).** `formatPosition` and `PlayButtons._clock`
each carried two `% 60` literals, and Dart defines `a % b` to land in
`[0, b.abs())` — so `% 60` and `% -60` are the same function for every input and
the mutants were **unkillable by construction**. Routing both through one
`const perMinute = 60` makes the same mutation rewrite the neighbouring `~/`,
where the sign is very much observable: `Continue 2:05` becomes `Continue -2:05`
and `3:07` becomes `57:07`. An equivalent mutant turned into a killable one beats
an exclusion. `player_page.dart`'s survivor was the argument-swap rule matching a
run of closing parentheses in `UnverifiedTlsBanner` and producing a
**whitespace-only** rewrite; hoisting `Theme.of(context).colorScheme` into a
local collapsed the `TextStyle(...)` onto one line and the match disappeared —
at a cost of 3 mutants in that file (31 → 28), the other two being
compiler-killed paren shuffles.

**Excluded as genuinely equivalent (4), each measured with `--dry -v`.**
- `PlaybackPrefs.hashCode` and `PlaybackTrackRef.hashCode` argument order — the
  third and fourth instances of the case `PosterKey` documents. **Both cost two
  mutants, not one**, and in both the second is an `&&`-negation from the `==`
  above running into the excluded statement and failing to compile. A first
  draft of each comment predicted one; the `--dry -v` diff corrected it. That is
  now three of the four entries in this family with the same second casualty,
  and `mutation_rules.xml` says so: do not predict it, diff it.
- `MpvPlayer.setProperty(String name, String value)` — a **parameter rename** in
  an abstract declaration, on two positional parameters of the same type. No
  input separates the two versions. Cost measured at exactly 1. Its retirement
  condition names the right fix — a narrower `setVerifyTls({required bool
  verify})`, which the rule cannot match at all — and says why it is not this
  milestone's.
- One exclusion was **deleted**: `SavedServer.hashCode`'s. Its retirement
  condition fired when M4 added `wifiOnly` and `allowUnverifiedPlayback`, so the
  exact pattern stopped matching — but the mutants did not come back, because a
  six-argument `Object.hash(` broken over seven lines gives the swap rules
  nothing to match. Measured: settings.dart reports **38 mutations with the
  stale pattern and 38 without it**. An exclusion matching nothing reads as a
  decision still being honoured, so it went.

### M4.0 — nine experiments, and three answers changed the design

**E1 — does `flutter test` still work with `media_kit` in the pubspec? YES.**
All three packages pass, and `run-coverage.sh`'s Flutter branch still sees
`SF:lib/…` and rewrites it repo-relative.

**E2 — does a `Player` construct headlessly? YES, and this is the answer the
milestone turned on.** `media_kit` 1.2.6's core is pure Dart over `dart:ffi`;
only `media_kit_video` is a plugin. Against Homebrew's libmpv (mpv 0.41.0), under
`flutter test` with `NativePlayer.test = true`: the seeded MP4 opened by
`file://`, `duration` arrived as `0:00:03`, `position` passed 1 s,
`state.tracks.audio` carried a real `aac` entry beside mpv's synthetic
`auto`/`no`, and `completed` fired. **So `mpv_player.dart` did not become
uncovered debt.** `MAX_UNCOVERED` still had to rise, by **2** — see E-video.

**E2b — `libmpv:` and `LIBMPV_LIBRARY_PATH` both work, and the platform defaults
do not.** `media_kit`'s macOS default-name list is `['Mpv.framework/Mpv']` and
nothing else, so with neither set the probe failed with *"Cannot find
Mpv.framework/Mpv"*. `test/support/libmpv.dart` resolves explicitly and **fails
rather than skipping**.

**E3 — HTTP with a cookie: YES. The negative control initially FAILED TO FAIL,
and that is the most useful thing this session found.** With the cookie, duration
arrived. Without it, in the same process, duration **also** arrived — because
`Media`'s constructor is `httpHeaders ?? cache[uri]?.httpHeaders` over a
**global static cache keyed by URI**, so the second `Media` inherited the first's
cookie. Re-run in a fresh process it failed correctly:
`Failed to open http://127.0.0.1:8099/api/media/…/file/0`. A negative control
sharing a process with its positive is vacuous here; CLAUDE.md now says so.

**E4 — `SubtitleTrack.data` renders: YES.** The server's own `text/vtt` body,
fetched through `dart:io` with the cookie, handed straight to
`SubtitleTrack.data`, produced the cue `Hello fixture` on `stream.subtitle`.
That is why `SubtitleSource` carries **text rather than a URL**: the sidecar
route is authenticated, so fetching it through `LibraryApi` keeps the cookie jar,
F3 and F15, where a `sub-add` would use libmpv's own unverified HTTP.

**E5 — does the server call a VP9/Opus MKV browser-native? YES, once the row has
been probed. The first answer recorded here was NO, and it was wrong.**

The original E5 seeded a VP9+Opus Matroska into a scratch library, saw
`transcode: true` and a **307**, saw a `.webm` copy of the same stream answer
**200**, concluded that "browser-native is decided by file extension", amended
SPEC §3.4 and §10, and declared M4's exit criterion unsatisfiable. Every
observation in that paragraph is real. The conclusion drawn from them is not.

`fileNeedsTranscode` (`internal/server/playback.go:78-83`, v0.20.3) reads:

```go
if f.Container != "" && f.VideoCodec != "" {
    return !transcode.DirectPlayable(f.Container, f.VideoCodec, f.AudioCodec)
}
return transcode.NeedsTranscode(f.Ext)
```

The extension branch is the **fallback for a row the probe agent has not
reached**, and `tool/testserver/seed.sh` never probes: it rebuilds the cache and
stops. Measured directly in the cache SQLite —

```
sqlite> select idx, ext, quote(container), quote(video_codec), quote(audio_codec)
   ...>   from media_files;
0|.mkv|''|''|''
sqlite> select count(*) from probe_tasks;
0
```

— every seeded row has empty format columns and no probe task has ever existed.
So the whole five-row table below was the extension fallback, five times, and
none of it was ever the probed branch.

`tool/spikes/e5_mkv_direct_play.sh` is the correction, and it runs **both arms
over the same file** so the control is structural rather than remembered:

| Arm | `media_files.container / video_codec / audio_codec` | `transcode` | `GET file/0` |
|---|---|---|---|
| unprobed (what the seed leaves) | `'' / '' / ''` | true | **307** → `…/hls/index.m3u8` |
| after `POST /api/admin/probe/scan` | `'matroska,webm' / 'vp9' / 'opus'` | false | **200**, `Accept-Ranges: bytes`, `Content-Type: video/x-matroska` |

`DirectPlayable` (`internal/transcode/transcode.go:84`) crosses
`mkvFamily = {matroska, webm}` with `webmVideo = {vp8, vp9, av1}` and
`webmAudio = {opus, vorbis, ""}`, so a probed VP9/Opus Matroska is direct-play
**whatever the file is called**. SPEC §3.4 was right as written; §10's M4 row
and the CLAUDE.md "playback truths" bullet have both been corrected, and the
retracted claim is named in each rather than quietly deleted.

**What this does and does not change in the client.** Nothing in the code:
`decide()` already reads the server's own `transcode` flag and was explicitly
forbidden from reimplementing `DirectPlayable`, so the client is correct under
either branch. What it changes is the exit criterion, which is met.

**The MKV item was still not added to the shared seed, and the reason is churn
rather than doubt.** `seed.sh`'s library is asserted on by name and by count in
six places — `browse_test.dart`'s `tree.map(...) == ['Films','Shows']` and
`categoryMedia(films).single`, `browse_live_test.dart`'s two equivalents, the
captured category fixtures and their SHA-256 manifest. A third item plus a probe
scan would rewrite all of them to prove a server behaviour that the spike
already proves in both directions, and no client code branches on it. The seeded
library is therefore deliberately left **unprobed**, which is also the harder
case for the client: it is the branch that produces a 307 on an MKV.

**E6 — libmpv verifies no certificate, and `tls-verify` is both settable and
load-bearing.** At the CLI, against this repository's own committed
`server_a.crt`: default → rc 0 and the Python TLS server logged
`"GET /movie.mp4 HTTP/1.1" 200`; `--tls-verify=yes` → rc 2,
`error:0A000086:SSL routines::certificate verify failed`, and the server's log
line count **did not move**. Through `media_kit`: `setProperty('tls-verify','yes')`
then reading it back gives `yes`; opening the same self-signed URL with it on is
`REFUSED` and with it off `PLAYED duration=0:00:03`. **This is D10's entire
basis.**

**E7 — `ConnectivityPlatform.instance` substitutes headlessly: YES**, the same
seam `PathProviderPlatform` gave M3. It also produced a correction nobody asked
for: the enum has **eight** values, not the seven C4 listed — `satellite` was
added since. `networkTypeOf` maps all eight and a test asserts the count, so the
next addition is a red test rather than a silent fall-through.

**E8 — CI's `ubuntu-latest` gets a loadable libmpv: YES.** Measured in an
`ubuntu:24.04` container (what `ubuntu-latest` is): `apt-get install -y libmpv2`
succeeded, installed `/lib/<arch>/libmpv.so.2`, and `dlopen("libmpv.so.2")`
succeeded — which is the **second** entry in `media_kit`'s Linux default-name
list, so no path needs to be passed. `libmpv.so` and `libmpv.so.1` both failed to
open and are not needed. **Caveat, stated rather than hidden:** the container was
aarch64 (the local podman machine) and GitHub's runner is x86_64. The package
name and the loader behaviour are architecture-independent; the first real CI run
is what confirms it, and it fails loudly if not. **The plan's "scratch CI run"
was impossible — this repository has no git remote at all.**

**E9 — `just dupes` still passes**: 7 exact clones, 183 lines, **0.79%**, against
a 5% threshold.

**E-video — an experiment the plan did not list, and it is the one that raised
the ratchet. Its conclusion was overstated and M4.R reverted the raise.** What
was measured is that a probe which built a `VideoController` and **pumped** a
`Video` never returned and was killed at five minutes. What was written down was
that `VideoController(player)` "does not construct", and `tool/coverage-gate.sh`
raised `MAX_UNCOVERED` from 0 to 2 on that sentence. It constructs fine; what
never returns is `Player.dispose()` afterwards. See M4.R/G1 for the three-way
re-measurement. `buildSurface` still lives on `MpvPlayer` rather than in the
translation layer, and that placement is still right — it keeps the one
platform-channel expression out of the file holding every translation
decision — but it is no longer uncovered.

### The gates, and what had to change

- **`app_no_raw_http` refuses `package:media_kit` under `apps/*/lib` except
  `playback/mpv_player.dart` and `playback/media_kit_playback_host.dart`.** The
  exclusion filters the **file array**, never `grep -v` on the output — a path
  filter on output matches a path appearing anywhere in the line, so any file
  merely *mentioning* the adapter's name would have been exempt. Proven in four
  directions, including a third file under the same directory.
- **`check-toolchain.sh` checks libmpv**, guarded on an `apps/*` package
  existing, and refuses a `LIBMPV_LIBRARY_PATH` that points at nothing —
  an environment variable pointing at a missing file is worse than an unset one,
  because media_kit then falls through to platform defaults and the error names
  a framework nobody asked for.
- **`ci.yml` installs `libmpv2` before resolving**, with E8's measurement as the
  reason and `libmpv-dev` explicitly ruled out.
- **`tool/coverage-gate.sh`'s `MAX_UNCOVERED` rose from 0 to 2**, for the first
  time in this project — and **M4.R put it back to 0**, because the raise was
  unnecessary and the measurement in its justification was wrong. The file keeps
  the whole episode, including what actually does not terminate.

### Deviations from the plan, with the reason

- **`buildSurface()` is on `MpvPlayer`, not in `MediaKitPlaybackHost`.** The plan
  put it in the host as "the only platform-channel call in the file". Moving it
  one layer down keeps the uncoverable expression out of the file that holds
  every translation decision, and that file is now fully covered.
- **The VP9/Opus item was dropped, and then the reason for dropping it turned
  out to be wrong.** The ratified fallback was "if it 307s, drop the item and
  record the measurement" — the item did 307, so it was dropped. What the first
  pass then recorded was a *rule* ("the extension decides") that the measurement
  did not support: the seeded cache rows are unprobed, so the 307 was the
  documented extension fallback. See E5 above. The item stays out of the seed on
  a different and narrower reason — fixture churn, named there — and
  `tool/spikes/e5_mkv_direct_play.sh` carries both arms instead.
- **`AudioTrack`'s positional arguments are `(id, title, language)`**, read off
  `media_kit`'s `track.dart:152` — not the order the names suggest. The first
  implementation put the label in `language`, and only an assertion on the
  *fields* (rather than on a call count) caught it.
- **`FakeLibraryApi.postProgress` does not go through `_answer<void>`.** With `T`
  bound to `void`, `result is! T` is false for every value, so the throw arm is
  unreachable — measured: four `ProgressReporter` failure tests passed against a
  fake that never threw. That is a fake that cannot fail, which is the
  gate-that-cannot-fail wearing test clothes.

### The concurrency hazard bit again, and it was caught by the discipline

A `just check` was interrupted by a command timeout, and it left a live mutant on
disk: `if (title != null && title.isNotEmpty)` rewritten to
`if (title != null || title.isNotEmpty)` in `media_kit_playback_host.dart`. It
was found by running `dart analyze` immediately afterwards, per CLAUDE.md — it
surfaced as an `unchecked_use_of_nullable_value` **error**, not as a test failure.
Separately, `git checkout --` on an **intent-to-add** path truncated
`network_status.dart` to zero bytes, exactly as STATE.md's M3 note warns; `cp` is
the undo, and the file was rewritten.

### Debt this milestone knowingly accepts

- ~~**`MAX_UNCOVERED` is 2, raised from 0.**~~ **Paid at M4.R**: the two lines
  are covered by a direct-call test and the ratchet is back at 0. What genuinely
  cannot run headlessly is disposing a `Player` a `VideoController` has attached
  to, and what cannot be checked at all is what those lines DRAW — backlog row
  16, still open.
- **`just check` now requires libmpv**, exactly as it requires Flutter.
  `toolchain-check` refuses first so the failure names the cause.
- **The headless player suite runs against Homebrew's libmpv, not the shipped
  Android/iOS builds.** Backlog rows 18 and 20.
- **F15 does not extend to playback**, and that is measured rather than assumed
  (E6). D10 makes it a per-server choice defaulting to refuse, with a persistent
  banner rather than a dismissible dialog.
- **A mid-playback session loss is detected indirectly** — mpv surfaces no status
  code, so a non-401 failure costs one wasted `me()` round trip. **One retry per
  stretch of playback** (M4.R/P2): a file that errors, retries and never ticks
  gets mpv's own sentence on screen rather than a second attempt, and a Next to
  another file inherits that spent retry until the new file ticks.
- **F13 samples the network once, at start**, and the sample is now memoised so
  that re-deciding per file (M4.R/P4) does not quietly retire this. A switch to
  cellular mid-film is still not handled.
- **A metered Wi-Fi hotspot is classified unmetered.** `connectivity_plus`
  reports a transport, not a cost. Backlog row 21.
- **No gapless next-file advance.** We open each file ourselves so that "which
  file is playing" — the key every progress report carries — has one source of
  truth. Nothing is reported for a newly opened file until the engine has said
  where it is, which is what M4.R/P1 cost to learn.
- **Embedded subtitles stay deferred; embedded AUDIO is used**, because the API
  lists no audio tracks at all and nothing else can satisfy F7.
- **Any pre-M4 `settings.json` is discarded** by the new strict `playback` block.
  §13 says that is correct; it still happens to a developer with a saved server,
  and `settings_store_test.dart` asserts it rather than leaving it to be
  discovered.
- **A failed progress report is not queued or retried on a timer.** The next
  trigger carries a newer position.

### M4.9 — the live suites, written last

`packages/filefin_api/integration_test/playback_test.dart` (12 tests) and
`apps/mobile/test_live/playback_live_test.dart` (6) plus
`playback_no_cookie_test.dart` (2). `just it` is **53 tests across two suites**,
and both floors were raised — `packages/filefin_api/integration_test` 26 → 38,
`apps/mobile/test_live` 7 → 15 — with the raise proven in both directions by
deleting one test from each suite and watching the gate refuse (37 < 38, then
14 < 15).

**The differential check is the reason the API suite exists.** Every report is
posted to the live server, the detail re-read, and the server's own
`continueIndex`/`continueSeconds`/`watched` compared against what
`applyProgress` + `deriveView` predicted from the state the server *had*. The
601 captured vectors prove the transcription against `internal/state` run
directly; this proves the HTTP route in front of it stores what the engine
returns. Proven able to fail: perturbing **only the prediction side**
(`.copyWith(continueSeconds: 99)`) turned four of the four differential tests
red with `continueSeconds: the server and applyProgress disagree`, and left the
eight non-differential tests green.

Both arms of the last-file asymmetry are asserted on the **show**, not the film,
and that is forced rather than chosen: `FixtureRun._decorrelateWatched` makes
the single-file film `watched: true` in every copy, which would make "2.9/3.0
sets watched" vacuous. The show is two unwatched files, so crossing file 0
(non-last) advances the pointer to file 1 at 0 seconds with `watched` unmoved,
and crossing file 1 (last) sets `watched` and leaves the pointer where it is.
There is no client method for un-watching an item — `watched` is M6 — so this is
the only shape available.

**The app's live suite is the milestone's real proof**: a real cookie from
`playbackHeaders()`, a real `MediaKitPlaybackHost` over `RealMpvPlayer` with
`NativePlayer.test = true`, opening the seeded MP4 over HTTP. Duration ≈ 3 s,
an audio track with mpv's synthetic `auto`/`no` dropped, position past 1 s, a
seek to 2 s landing, `completed` firing, and the sidecar — fetched through
`LibraryApi` and handed to `SubtitleTrack.data` — rendering the cue
`Hello fixture`.

**The negative control is a SEPARATE FILE, and that is E3's finding made
structural.** `Media`'s constructor is `httpHeaders ?? cache[uri]?.httpHeaders`
over a global static cache keyed by URI, so a cookie-less open in the same
process inherits the previous cookie and the control passes for the wrong
reason. `flutter test` gives each file its own `flutter_tester` process, and the
control additionally opens a distinguished URI (a query parameter `playback.go`
never reads). Measured: it waits out the full 15 s without a duration and mpv
reports the failure on its error stream — which is all mpv can report, since it
surfaces no status code.

### M4.R — remediation of three adversarial reviews of M4

Reviews P (playback correctness), G (gates and mutation work) and T (test
genuineness). Everything below was re-proven in **both** directions: the fix
green, the code broken, exactly the intended test red, the code restored.

**P1 [CRITICAL] `next()` posted the previous file's position under the new
file's index — user-visible data corruption.** `_position`/`_duration` are keyed
on `_current`, and `next()` advanced `_current` while leaving them behind.
Against real libmpv the first event after a second `open()` is deterministically
`playing=false`, **before** any position or duration event
(`playing=false / position=0 / duration=0 / playing=true / duration=3000ms`), and
`playing == false` reports a pause. Replayed against the real v0.20.3 server on
the seeded two-episode show:

```
POST {"file":0,"position":2.9,"duration":3,"event":"stop"}  -> 204
POST {"file":1,"position":2.9,"duration":3,"event":"pause"} -> 204
VIEW watched=True continueIndex=1 continueSeconds=0 perFile=[True, True]
```

**Tapping Next at the end of episode 1 marked the whole show watched**, and in
general Next at *x* of file *n* wrote the resume pointer into file *n+1* at that
same absolute second. It was **unpinned in both directions** — the review
measured that applying the fix left all 145 `test/playback` tests green, twice.

Fixed in two parts, because zeroing the fields is necessary and not sufficient:
`_switchTo()` resets both, and `_positionIsCurrent` suppresses the `playing ==
false` report until a position tick for the current file has arrived (a report
of second 0 is still a claim about a file nothing has measured). Three tests
now pin it, and each kills exactly one mutation and no other:

| Mutation | Red |
|---|---|
| no reset in `_switchTo` | `the old position is never posted under the new file` |
| `if (!p)` — suppression removed | `a duration alone does not say where the new file is` |
| `_positionIsCurrent` never set true | `the new file reports normally once it has ticked` |

Before the fix the first of those failed on `watchState.watched` — `Expected:
false / Actual: <true>` — which is the corruption itself, not a proxy for it.

**P2 [HIGH] mpv's error text never reached the user and every error after the
first was swallowed.** `_recover(String message)` never read `message`, and
`_recovering` latched `true` for the controller's whole life. A genuinely broken
file therefore produced a **black player with no message** (the opposite of what
F12 asks for), and a session dying mid-film after any earlier transient error
never reached `me()` again and so never routed to sign-in. The guard is now "the
retry is spent until playback demonstrably resumes", which a position tick says
and nothing else does; `_failure` is set from `message` when the retry is spent.
A third bug in the same three lines went with it: `_startAt = _position` with no
tick yet threw away F8's resume offset when the very first open failed. Four
mutations, four different tests red.

**P3 [MED-HIGH] F9's local reflection had no production reader — WIRED, not
deleted.** `ProgressReporter.state` and `needsDetailRefetch` were computed,
validated against 601 captured vectors and thrown away: `app.dart` pushed the
player with `unawaited(...push(...))` and `MediaDetailPage` loaded once in
`initState`, so returning from the player showed the resume offset from before
playback started and M1's divergence latch discharged nothing.

**Deleting the members was the other option offered and it is the wrong one**:
they are not speculative surface, they are SPEC F9's second clause ("reflect
resulting watched/continue changes locally without a full refetch") and M1's
named escape hatch. Removing them would have deleted a requirement's
implementation and left §5 satisfied by subtraction. So the value now travels:
`PlaybackOutcome` (state + `needsDetailRefetch`), popped by `PlayerPage` **after**
the awaited final `stop`, returned by `app.dart`'s `_play`, and applied by
`MediaDetailPage` — `deriveView` folded onto the loaded detail through the new
`AsyncController.replace` in the ordinary case, and a real `load()` in the one
input class `applyProgress` provably cannot match. Five mutations, five tests
red, including `pop()` without the outcome.

**P4 [MED] `next()` bypassed `decide()`, so F13 never saw any file but the
first.** Measured: file 0 = 10 B, file 1 = 9 GiB, metered — file 1 opened with
no prompt. `next()` now goes through `_decideAndOpen()`. **The network sample
stays once per session** (that is documented debt, and re-taking it here would
have retired it silently), so the sample is memoised with `??=` and only the
*decision* is re-taken. Both halves are pinned: routing `next()` back to
`_open()` and dropping the memo each redden the same test for different reasons.

**P5/T5 [MED] the D10 banner was keyed on the setting, not the transport.** With
`allowUnverifiedPlayback` on and `playbackTransport() == osTrustedTls` the
controller passes `verifyTls: true` and **mpv does verify** — while the banner
asserted "the player checks no certificate". Factually false, and the same
over-fire on `plainHttp`. No under-fire, so D10's guarantee never depended on
it; the defect was a cry-wolf banner. Now `pinnedTls && allowUnverifiedPlayback`.
T5's other half was that **nothing asserted the banner's absence** — dropping
the guard entirely passed all 358 mobile tests. Two negative arms now exist, and
the plain-http one is deliberate: a *pinned* server with the flag off is
**refused**, and the refusal panel replaces the column the banner sits in, so
that arm would have passed for a reason unrelated to the guard.

**P6/T10 [LOW-MED] the volume slider was write-only.** `value: 1` was a literal,
so the thumb snapped back to full on the next rebuild while mpv held the dragged
value; mutating the literal to `0` left all 149 playback tests green. The
controller now holds the volume and the slider draws it. Both the literal and
the controller's memory are pinned.

**T9 [HAZARD] the subtitle menu indexed a later snapshot than it built from —
the third instance of the clamp-before-guard class.** `itemBuilder` numbers one
snapshot of `controller.subtitles`; `onSelected` read a later one, and
`_open()` replaces `_subtitles` wholesale — on `next()`, and asynchronously from
`_recover()` on any mpv error. The review could not reproduce it (it needs a UI
race) and flagged it; the tests here **do** reproduce it, by leaving a menu open
across an advance to a file with fewer sidecars.

**It took two tests, and the mutation gate is what said so.** The first version
shrank the list by exactly one — tapped index 1 into a list of 1 — which pins
`>=` against `>` and leaves `>=` against `==` alive, and that mutant survived the
whole 372-test suite. The second case tapped index 1 into an emptied list, which
pins `==` and leaves `>` alive. Neither alone pins the operator; both together
kill all 24 mutants in the file. A guard tested at only one side of its boundary
is the same defect the guard exists to fix.

**P7 [LOW] three wrong doc statements, one of which was showing users a number
they never chose.** `decision.dart` said the three playback settings "are one
per-server block on disk" — two are on `SavedServer` and two are the global
`PlaybackPrefs`. `progress_policy.dart` described `SentReport.positionSeconds`
as "what the server stored"; it is what the client last **sent**, and the two
part company on every crossing report. And `humanSize` divided by **1024** under
**kB/MB/GB** labels, so `PlaybackPrefs`' own default of `500 * 1000 * 1000` came
out of the settings dropdown as **"476.8 MB"**. Fixed by making it decimal
through one constant, and the choice list — which mixed `100 * 1024 * 1024` with
`500 * 1000 * 1000` — is now four powers of 1000, so every option renders as the
round number it claims to be.

#### Gates

**G1 [WEAKENING] `MAX_UNCOVERED` 0 → 2 was unnecessary, and its justification was
false. REVERTED TO 0.** `tool/coverage-gate.sh` claimed `VideoController(player)`
"**hangs** under `flutter test`". Re-measured three ways in a plain `test()` body
with a binding up:

```
VideoController(player)      -> returns
Video(controller: …)         -> returns
player.dispose() afterwards  -> NEVER returns
```

The constructor body is a fire-and-forget `() async { … }()` whose first
statement awaits `addPostFrameCallback` (`video_controller.dart:71`), so it parks
a closure rather than the caller. M4.0's real measurement was that **pumping** a
`Video` never returned; the gate generalised it from pumping to constructing,
and coverage only ever needed the latter. **That sentence was the entire basis
for the first ratchet raise in this project's history.**

The review's own demo would have tripped over the third line, which nobody had
measured: `VideoController` sets `isVideoControllerAttached`, and
`Player.dispose()` then awaits a completer only that parked closure completes —
so using the suite's shared player took four tests down with it. The test gives
itself its own `Player` and never disposes it, and additionally pins the `??=`
memo, which nothing tested before.

```
Coverage: 100% (2201/2201 lines), floor 50%, target 80%
Uncovered: 0 line(s), ratchet 0
```

Both directions: dropping that one test → `ERROR: 2 uncovered line(s), ratchet
allows 0` and exit 1. `check-coverage.sh`'s header now points at
`coverage-gate.sh` for the value in force rather than stating one of its own.

**G2 [FALSE REASON] the "seeded per process" sentence is gone from all three
hashCode exclusions.** The fact is true and the inference was not: both sides of
`expect(r.hashCode, Object.hash(a, b))` are computed in the **same** process.
Measured over three runs — the value moved (458304581 / 435016163 / 508756647)
and the assertion was stable and distinguished the swap every time. The mutants
**are** killable; the honest reason to reject the test is the other one the
comments already gave, that it copies the implementation into the test file. The
exclusions stand; the wrong reason is replaced by the measurement, because a
false premise inside an exclusion is how the next widening starts.

**G5 [FRAGILE → STRUCTURAL] the three argument-swap rules can no longer match a
run of closing parentheses.** M4 removed one unkillable whitespace-only mutant by
*hoisting a local so `dart format` collapsed a call onto one line* — an exclusion
enforced by formatting, with the same pathology still live at
`_FailureBanner`. `)` is now excluded from every argument group, which loses
nothing legitimate: an argument may not contain `(`, so an argument containing
`)` is necessarily an enclosing call's. Measured, and this is the whole
argument:

| | wide rules | narrowed |
|---|---|---|
| `player_page.dart`, hoisted (as committed) | 33 | 30 |
| `player_page.dart`, **un-hoisted** | **36** | **30** |
| `playback_host.dart` with the `Object.hash` exclusion | 6 | 6 |
| `playback_host.dart` **without** it | 8 | 8 |

The formatting no longer changes the mutant count, and every existing exclusion
still bites. Every mutant removed was inspected in the `--dry -v` diff and every
one is source re-punctuation — `Map<String, Object?>` shuffled across a `),`
run, `icon: const Icon(\n ,Icons.audiotrack));`. The one genuine neighbour in
those files, `clamp(1 << 31, 0)`, survives the narrowing.

**G6 [INCOMPLETE] the media_kit confinement now covers `export` and `part`, not
only direct imports.** Both bypasses passed silently: a `part` file uses `Player`
with no import line at all, and a re-export hands `Player`, `Media` and `Tracks`
to any third file. Neither construct exists in `apps/mobile/lib`, so the correct
count is 0 and the ratchet holds it there. Proven in both directions —
`export 'package:media_kit/media_kit.dart';` in `mpv_player.dart` and
`part 'mpv_part.dart';` in `media_kit_playback_host.dart` each fail the gate,
naming the file and line; the clean tree passes.

#### Test genuineness

**T1 [HIGH] `just it` was not idempotent with respect to `just
fixtures-capture`.** `capture_fixtures.sh` POSTs favourite, rating, watched
**and progress** against the shared seed and they land permanently in
`meta.json`; `_decorrelateWatched` normalised `watched` and deliberately
preserved `progress`. Reproduced exactly: clean seed → `just it` exit 0, 53
tests; `just fixtures-capture` → the show gains `progress {"file":"1x2"}` →
**`just it` exit 1, two failures on unmodified code**
(`a report is accepted and stored where the engine says`, `every event value is
accepted`), both asserting absolute literals that hold only when the pointer is
unset. `_decorrelateWatched` now replaces the whole `state.<user>` block. With
the **same polluted seed** still on disk, `just it` is back to exit 0 and 53
tests. A copy that starts from a state it wrote itself is the only kind that
answers the same on two machines.

**T2 [VACUOUS] the seek test proved nothing.** It seeked *forward* to 2 s and
waited for `position >= 1.9 s`, which ordinary playback reaches on its own — so
`seek()` replaced by a total no-op left all six tests green. It was also a
tautology of the `firstWhere` that produced the value. It now plays past 2.5 s,
**pauses**, seeks **back** to 0.5 s and asserts the next tick is under a second.
Nothing but a real seek moves position backwards, and the no-op mutation now
reddens the suite.

**T3 [VACUOUS] the completed test proved nothing.** `expect(completedFired,
isTrue)` cannot be false — `firstWhere((done) => done)` only completes with
`true` — so `completed → Stream.value(true)` left all six green and collapsed
the suite. It now asserts the position at completion is within 500 ms of the
duration and that the stretch took non-trivial wall time. **The first attempt at
this still passed under the mutation**, because the position high-water mark and
the stopwatch had already been fed by the real playback up to 2.5 s; both are
now reset immediately before the wait, and the constant `completed` fails with
`Expected: a numeric value within <500> of <3000> / Actual: <0>`.

**T4 [STRUCTURAL] one `setUpAll` for six live tests made per-test attribution
illusory.** Every failure reported as `(setUpAll)`, and under one mutation the
run was `+0 -1` — five tests silently did not run. The work is now a memoised
`Future` awaited from each body: it still happens exactly once, and every test
keeps its own name, pass and failure. Visible in the proofs above — the no-op
seek reports `+0 -6` with each test named, and the constant `completed` reports
`+5 -1`. One thing had to be preserved: the mpv context is torn down in
`tearDownAll` and nowhere else, because disposing it from inside a test body
while its streams still have listeners crashes `flutter_tester` outright
(SIGBUS, measured).

**T6 [DOC] the `Media` header-cache hazard is UNREACHABLE through this code.**
`Media`'s constructor is `httpHeaders ?? cache[uri]?.httpHeaders`, so the cache
is consulted only when `httpHeaders` is null — and `MediaKitPlaybackHost.open`
always passes `request.headers`, which `PlaybackRequest` declares non-nullable.
The null branch cannot be taken from here. CLAUDE.md and the live suite's own
header stated it as live for this path; both now say what it is, a trap in the
library rather than a defect in ours. **The control is kept**: the separate file
and distinguished URI are defence in depth against a future caller that stops
passing headers.

#### One finding the reviews did not make

`just fixtures-capture` is **destructive to `test/fixtures/error_shapes.txt`**:
it rewrites the file with only the shapes the script itself captures, dropping
four blocks a later hand-append had added (the 400s, the subtitle route, and —
usefully — the now-retracted "the extension decides" note). It is caught:
`just fixtures-verify` refuses on the SHA-256 manifest, naming the file. Recorded
rather than fixed, because the gate closes it and the fix is a decision about
where hand-recorded shapes should live.

### What M4 did NOT finish, stated plainly

- **The MKV item is still not in the seed.** E5's correction proves an `.mkv`
  direct-plays once probed, but proving it in `just it` means a third seeded
  item plus a probe scan, which rewrites six name-and-count assertions and the
  captured category fixtures. `tool/spikes/e5_mkv_direct_play.sh` carries the
  measurement instead. The reason is churn, not doubt.
- **The live suites' widget half is still the M3 gap.** A request initiated
  inside a `testWidgets` body registers its timers in that body's `FakeAsync`
  zone and never completes, so `playback_live_test.dart` drives the host from
  plain `test()` bodies. Nothing here proves `PlayerPage` issuing the call
  itself; that is `docs/verification-backlog.md`'s row, not a claim rounded up.
- **A player already running does not pick up a changed interval**, and the
  detail screen behind it now DOES pick up what playback did — see M4.R/P3,
  which is what F9's second clause needed and did not have.
- **The settings sheet writes `settings.json` and nothing re-reads it mid-session
  except the two places that need it.** `app.dart` keeps the changed
  `SavedServer` in its own state and the player route reads
  `settings.read().playback` at push time, so a sheet opened *from* the player
  screen would not exist — it is on the tree screen only. A player already
  running does not pick up a changed interval until the next open. Stated
  rather than discovered.
- **`MpvPlayer.setProperty` is still a generic string property setter** used for
  exactly one property. `mutation_rules.xml` carries its exclusion and names the
  replacement (`setVerifyTls({required bool verify})`), which would delete the
  exclusion with it. Deferred because it moves the yes/no conversion across
  three files and two fakes, which is not a change to make on the way out of a
  milestone.

---

## M3 — what was built

| Step | Deliverable |
|---|---|
| M3.0 | A measurement session, no commit. Six questions answered by running things; two of the plan's premises turned out false |
| M3.1 | `apps/mobile`, its Android/iOS platform config, and **every gate's Flutter branch**, each proven in both directions |
| M3.2 | `filefin_core`: `buildCategoryTree` — and a real nested category in the seed, which the plan listed as an experiment that might fail |
| M3.3 | `filefin_api`: `posterBytes` — and a seeded poster, which closes CLAUDE.md's DoD item 5 against `docs/server-api.md`'s "No fixture" |
| M3.4 | `UiState`, `AsyncController`, `AsyncView`, `ErrorPanel`, `describeApiError`, `LibraryApi` (D-Q1), plus a `dead_types` fix |
| M3.5 | `settings.json` persistence, F1's add-server flow, F2's sign-in, the scope |
| M3.6/7/8 | The category tree, the virtualised poster grid (the exit criterion) and the detail view, wired to each other |
| M3.9 | `apps/mobile/test_live/` against the real binary, and `just it` over two suites |
| M3.10 | This section, `docs/verification-backlog.md`, and the SPEC/architecture updates |

**Numbers as measured, not as hoped**, and re-measured after the M3.R
remediation below. `just check` exits 0 on a clean tree with **zero gate
warnings and zero gate errors** — the comment gate additionally names the 12
files under its 20-line size exemption, one of which (`credentials.dart`, 18%)
is over a line and stated rather than hidden. `just it` exits 0: **33
integration tests across two suites** — 26 in
`packages/filefin_api/integration_test` and 7 in `apps/mobile/test_live`, with
separate committed floors. Coverage **100% (1456/1456 lines)**, **0 uncovered
against a ratchet of 0**. **1124 unit tests**: 194 in `apps/mobile`, 133 in
`filefin_api`, 797 in `filefin_core`. The constitution baseline is **0 across
seven checks** — `app_no_raw_http` is new at M3.

(At the end of M3 itself the figures were 1111 unit tests — 181 in
`apps/mobile` — and 100% of 1446 lines. The remediation added 13 app tests and
10 covered lines.)

The whole-M3 mutation run (`FILEFIN_MUTANTS_BASE=0529f65`, the last M2 commit)
produced **263 mutations over 23 changed lib sources, 0 undetected, 0
timeouts**. **The app's share is 225 of them**, over 19 sources, and it is worth
stating separately: before M3.1 the mutation gate could not run on a Flutter
package at all. The largest single files are `media_detail_page.dart` (47),
`add_server_page.dart` (33), `category_tree.dart` (22) and `settings.dart` (22).
`ui_state.dart` and `library_api.dart` produce **0** each — declarations and
delegation, the same shape `filefin_core`'s wire models have, and the same
standing caveat: a healthy count elsewhere is not assurance about them.

### M3.0 — six questions, and two of the plan's premises were wrong

Answered by running things, before a line of M3.1 was written.

1. **`dart pub get` with a Flutter member SUCCEEDS.** The plan's premise — "a
   workspace with a Flutter member cannot be resolved by `dart pub get`" — is
   **false**: the `dart` on PATH is the Flutter SDK's own and resolves
   `sdk: flutter` (`+ sky_engine 0.0.0 from sdk flutter`), rc 0. What it does
   **not** write is `apps/mobile/.flutter-plugins-dependencies`, which is what
   registers a plugin with the Android and iOS builds; `flutter pub get` does.
   Measured both ways with `path_provider` declared. CI moved to `flutter pub
   get` for the real reason rather than the assumed one.
2. **Root `dart analyze --fatal-infos --fatal-warnings .` handles Flutter
   fully** — it resolves `package:flutter/material.dart` and reports genuine
   Flutter type errors (`const Text(42)` → `argument_type_not_assignable`,
   rc 3). **No `flutter analyze` branch was needed.**
3. **`flutter test --coverage` emits `SF:lib/src/…`** — package-relative, as
   predicted, and a lib source no test imports is absent entirely.
4. **It honours `// coverage:ignore-file`** — the file disappears from the lcov
   completely. So `run-coverage.sh`'s existing refusal of that comment in
   hand-written lib source protects the app unchanged.
5. **A global `<commands>` in `mutation_rules.xml` runs IN ADDITION to a
   per-document one** — measured, not reasoned. With `flutter test` in the
   targets XML and `dart test` still in the rules, `dart test` ran inside
   `apps/mobile` and killed the run.
   **But the predicted failure mode is wrong, and this is the correction that
   matters most.** The plan called this the milestone's single most dangerous
   item: "every mutant reads as detected, 100% over nothing". That does **not**
   happen. `mutation_test` runs the command set against unmodified code first
   and **aborts**: `Error: Running the test commands failed with unmodified
   code! Aborting.`, rc 1, with no `Found N mutations` line at all.
   `check-mutants.sh` refuses that twice over — rc != 0, and `found == 0` is its
   own hard failure. The old wiring was **fail-closed**. The fix is still
   mandatory, because the gate could not run on a Flutter package at all, but
   the risk was misclassified.
6. **A real request does NOT complete outside `tester.runAsync`.** Untouched,
   `HttpOverrides.current` is `_MockHttpOverrides` and a request completes with
   **400** — so a forgotten `= null` gives 400s, not a hang. With
   `HttpOverrides.global = null`, outside `runAsync`: `done=false, err=null`
   after two `pump(5s)`. Inside: a real **200**.

**A seventh answer nobody asked for, and it turned out to matter twice.**
`flutter test --reporter expanded <dir>` where `<dir>` holds **no
`*_test.dart`** silently runs the package's **default `test/` directory** and
prints "All tests passed!", exit 0. A *nonexistent* directory exits 1. That is a
vacuity mode CLAUDE.md's list did not have, and M3.9 demonstrated it end to end:
with `run-integration.sh`'s guards removed, `just it` reported **"181 tests,
floor 1"** over the unit suite and exited 0.

### The gates, and what had to change

Every branch below landed at M3.1, before a screen existed, and every one was
proven in both directions on the real script.

- **`run-tests.sh` picks the runner by LOCATION and fails on a disagreement
  with the pubspec.** `packages/*` is `dart test`, `apps/*` is `flutter test`.
  Guessing from the pubspec would exempt a package the moment the pubspec is
  what changed — the same defect `core_purity` had at M2. It also captures the
  output and refuses `~N` and `+0`, which `just it` already did.
- **`run-coverage.sh` gained a Flutter branch that ASSERTS the `SF:lib/` shape**
  before rewriting it repo-relative. A blind rewrite of a different shape
  produces a record naming no file — which reads as "every app source is
  missing" in the good case and as a false match in the bad one.
- **`check-mutants.sh` writes the test command into the targets document** it
  generates, and refuses a `<commands>` block in the rules file. The refusal
  strips XML comments first, and it has to: the first version failed on a
  **correct** file, because the comment explaining the rule contained the
  element name. That is "an assertion satisfiable in prose" with the sign
  flipped — a rule a comment can break is as broken as one a comment can
  satisfy.
- **`check-toolchain.sh` checks `flutter`**, guarded on an `apps/*` package
  existing, with a 3.44 floor.
- **`check-constitution.sh` gained a seventh check, `app_no_raw_http`**, scoped
  to `apps/*/lib` only. The app may not open its own socket, because
  `filefin_api` is the only place a 401 is interpreted, a certificate is pinned,
  or a cookie jar exists — and a widget that bypasses it bypasses all three
  silently, with a request that simply succeeds. The concrete temptation is
  `Image.network` on the poster route. Baseline 0.
- **`check-deps.sh` scans `test_live/`** — M2.7's finding in a new location.
- **`check-codegen.sh` unchanged**, confirmed: the app declares no
  `build_runner` and the loop already keys on that.
- **`run-integration.sh` carries a two-suite table** with per-suite floors,
  because a suite that lost tests must not be covered by one that gained some.

### Two gate blind spots M3's own code walked into

**`dead_types` was blind to generic sealed hierarchies**, and M3 introduces the
tree's first one (`UiState<T>`). The declaration pattern required
`class Name extends Base` with a space before `extends`, so
`final class EmptyBox<T> extends Box<T>` matched **nothing at all**. Measured on
a probe before the fix: the generic form exited 0, the byte-identical
non-generic form exited 1. Type parameters are now optional in the declaration
pattern and in the construction search — `EmptyBox<int>(…)` is a construction
and `\bEmptyBox[[:space:]]*\(` does not match it — and all four directions were
re-proven.

**A `mutation_rules.xml` exclusion that covers only part of the mutated range
excludes NOTHING, and does so silently.** Found while excluding two genuinely
unkillable mutants: `Object\.hash\(server, media, size\)` — which contains the
arguments the rule rewrites — changed nothing, and neither did the broader
`Object\.hash\([^)]*\)`. Both runs looked identical to one with no exclusion.
Only a pattern covering the whole statement worked (53 mutants with it, 56
without). Anyone adding an exclusion should check the count moved rather than
trusting that a plausible pattern did something.

### Three experiments the plan said might fail, and did not

**Nested categories are real, and the seed has one now.** Measured against the
binary at v0.20.3: a directory inside a category directory, carrying its own
`config.json` with a `parentId`, becomes a category with that parent. Two facts
the UI depends on came out of the capture, and only one of them was in the doc:
`name` is the **full path** (`Films/Documentaries`) and `leaf` is the **display
name**. A tree rendering `name` prints the whole path on a row already sitting
under its parent. The nested category is deliberately empty, so `media: 0` and
`empty: true` enter a captured payload for the first time — the case the UI must
not read as "empty library", since `library.go:73-81` returns 0 for both when
the cache is down.

**The poster gap is closed, and CLAUDE.md's DoD item 5 no longer conflicts with
`docs/server-api.md`.** That section said "No fixture" on two grounds. The first
— "the seeded items have no poster" — stopped being true: the importer picks up
a file named exactly `poster.jpg` in a media folder and writes it to the cache's
`media.poster` column, which is what `hasPoster` is derived from. `seed.sh` now
copies one into the **film** and deliberately not into the **show**, so both
branches have the real binary behind them. The second — "a blob no model
decodes" — is true and beside the point: what the fixture asserts is that
`http.ServeFile` returns the seeded bytes **unchanged**, and it is
byte-reproducible because the seed input is a **committed** file rather than a
fresh encode (an `ffmpeg` run produces different bytes on a different libjpeg
and would rewrite the manifest on every machine). Verified byte-identical.

**The mutation gate can fail on app code**, proven on real code rather than a
spike: deleting the `find.text` assertions from `app_test.dart` gave 1 of 5
undetected, rc 1; restoring gave 5 of 5, rc 0.

### NF2 is met by proxy, and here is the number and what it is not

**60fps cannot be measured headlessly, structurally.** `flutter test` runs
`flutter_tester` under `AutomatedTestWidgetsFlutterBinding`: fake clock, frames
pumped on demand, no vsync, no rasterizer, fabricated `FrameTiming`. The real
instrument needs a connected device.

Gated instead, over **5000 items decoded once by the real `FileFinClient` over a
real `dart:io` `HttpServer`**: a live `PosterTile` count under 80 at the top,
the middle and the end; poster requests far below 5000 and never above the tiles
ever built; the listing fetched exactly once across twenty scrolls **for the
category that was opened**; a scrolled-away tile cancelling its request; the
grid's children delegate being a `SliverChildBuilderDelegate`; tile size and
both tap-target guidelines.

**Narrowed at M3.R, because two of the three regressions this was said to catch
were not caught.** The live-widget count catches "the sliver lays everything
out" — `shrinkWrap: true` takes it from under 80 to 5000 — and nothing more:

- `GridView(children: [...])` builds all 5000 widgets on every frame and used to
  **pass**, because `SliverChildListDelegate` still mounts only the visible
  range. The delegate assertion above is what separates them, and it goes red on
  that rewrite.
- `addAutomaticKeepAlives: false` is inert in this tree: nothing under
  `apps/mobile/lib` mixes in `AutomaticKeepAliveClientMixin`, so there are no
  keep-alives to disable and flipping the flag changes nothing any test can see.
  It stays as a guard for a future tile that does, and both the docstring and
  `category_grid_page.dart` now say so instead of claiming it is gated.

Reported and **deliberately not gated**: **1460 µs/frame** over 60 scrolled
pumps of the 5000-item grid. That is **not frame time and is not evidence of
60fps** — build and layout only, debug JIT, `flutter_tester`, no rasterization,
and the fake clock advancing between frames. It is a number for a human to
notice moving. A flaky timing gate in `just check` would be worse than none.
`docs/verification-backlog.md` row 1 carries the real experiment.

**Why the 5000 items are decoded in `setUpAll` and the widgets driven over those
objects.** A request *initiated* inside a `testWidgets` body registers its
timers in that body's `FakeAsync` zone and never completes — `runAsync` makes
real time pass, it does not move a pending socket into the real zone. The first
draft of `grid_test.dart` pumped the page and waited two real seconds for tiles
that could never arrive. `setUpAll` runs outside `FakeAsync`, which is why the
real half lives there. The same constraint shapes `test_live/`, and the gap it
leaves is backlog row 14.

### Deviations from the plan, with the reason

- **`scope.dart` landed at M3.5, not M3.4.** `AppDependencies` holds a
  `SettingsStore` and a `SavedServer`-keyed factory, neither of which existed at
  M3.4. Building it a step early would have meant fields nothing read (§1, §5).
- **`run-integration.sh`'s two-suite table landed at M3.9, not M3.1.** The plan
  listed it among M3.1's gate edits and also under M3.9; doing it at M3.1 would
  have pointed the gate at a directory that did not exist yet, and the gate
  correctly fails on that.
- **The deferred mutation proof was executed at M3.1, not M3.4**, on real app
  code. At M3.4 the same experiment on `AsyncController` produced **no**
  survivor, and the honest reason is that `mutation_test` generates no mutant
  for `!identical(a, b)` or `?.cancel()` — neither is an operator or a literal.
  What is proven for `AsyncController` instead is that each guard is
  individually pinned: deleting the generation check, `_token?.cancel()` in
  either place, or the `RequestCancelled` arm each turns a **named** test red.
- **The live suite's widget layer does not issue its own calls** (above). The
  plan's "every await inside `tester.runAsync`" is necessary and not sufficient.
- **`PosterImageProvider` fetches; `PosterTile` owns the token.** The plan
  described them separately; cancellation only works if the token reaches the
  fetch, so the provider takes one.

### Gate proof log — M3

Every row executed against the real script, both exit codes observed.

| Gate | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `toolchain-check` | PATH with `dart` but no `flutter`, app present | **1**, names flutter | normal PATH | 0 |
| same | `PATH=/usr/bin:/bin` | **1**, names dart first | normal | 0 |
| same | a stub `flutter` reporting 3.19.0 | **1**, "below the 3.44 floor" | real 3.44.9 | 0 |
| `test` — zero tests | every `*_test.dart` moved out of `apps/mobile/test/` | **1** | moved back | 0 |
| `test` — `@Skip` | `@Skip('probe')` + `library;` on `app_test.dart` | **1**, `+9 ~1` refused | reverted | 0 |
| `test` — `skip:` | `skip: true` on one app test | **1**, `+11 ~1` refused | reverted | 0 |
| `test` — runner cross-check | `sdk: flutter` into `packages/filefin_api/pubspec.yaml` | **1** (and `constitution`/`core_purity` **1**) | reverted | 0 / 0 |
| same | the `sdk: flutter` deps deleted from `apps/mobile/pubspec.yaml` | **1** | restored | 0 |
| `coverage-check` | an untested 8-line function in an app lib source | **1**, `99% (767/771)`, 4 uncovered vs ratchet 0 | removed | 0, `100% (767/767)` |
| `run-coverage` — missing record | `apps/mobile/lib/src/orphan.dart`, nothing imports it | **1**, names the file | deleted | 0 |
| `run-coverage` — ignore comment | `// coverage:ignore-file` in an app lib source | **1**, names the file | removed | 0 |
| `run-coverage` — `SF:` shape | a PATH-shadowed `flutter` writing an **absolute-path** lcov | **1**, prints the offending `SF:` | real flutter | 0 |
| `mutants` — rules `<commands>` | a real `<commands>` element in `mutation_rules.xml` | **1** | element removed, comment naming it left | 0 |
| `mutants` — on app code | the `find.text` assertions deleted from `app_test.dart` | **1**, 1 of 5 undetected | restored | 0, 5 of 5 |
| `mutants` — on core code | the sibling-order tie-break assertions weakened | **1**, 2 of 23 undetected | restored | 0, 23 of 23 |
| `constitution` / `app_no_raw_http` | `final c = HttpClient();` in an app lib source | **1** | reverted | 0 |
| same | `import 'package:dio/dio.dart';` there | **1** | reverted | 0 |
| same | `HttpOverrides.global = null` there | **1** | reverted | 0 |
| same — scope, must NOT fire | all three in `apps/mobile/test/` | **0** | — | 0 |
| same — scope, must NOT fire | `filefin_api`'s real dio and `HttpClient` use | **0** | — | 0 |
| `constitution` / `dead_types` — generics | `final class EmptyBox<T> extends Box<T>`, never constructed | **1** (was **0** — invisible) | constructed as `EmptyBox<int>()` in a test | 0 |
| same — control | the byte-identical **non-generic** probe | **1** before and after | constructed | 0 before and after |
| `fixtures-verify` — nesting | the pre-M3.2 flat `categories.json` | **1**, names the seed line that fixes it | re-captured payload | 0 |
| `fixtures-verify` — poster | every `hasPoster` flipped to false | **1**, names `tool/testserver/poster.jpg` | restored | 0 |
| `deps` — `test_live` scope | undeclared `package:kiri_check/` in `test_live/` | **1** (was **0** without the directory in the source list) | import removed | 0 |
| `it` — zero test files | every `*_test.dart` moved out of `test_live/` | **1** | moved back | 0 |
| `it` — `@Skip` on the app suite | `@Skip('probe')` library annotation | **1** | reverted | 0 |
| `it` — `flutter_test.yaml` | an empty one in `apps/mobile` | **1** | deleted | 0 |
| `it` — the app floor | one live test deleted | **1**, "only 6 ran; the floor is 7" | restored | 0 |
| `it` — the unit-suite leak | the app suite pointed at an empty directory, **both guards removed** | **rc 0**, "181 tests, floor 1" — the entire unit suite standing in | guards restored | **1**, names the directory |

### Builds — what a device cannot be asked but a toolchain can

| Build | Result | What it proves |
|---|---|---|
| `flutter build apk --debug` | **rc 0**, `app-debug.apk` | the merged manifest carries `android:minSdkVersion="26"`, `android:networkSecurityConfig="@xml/network_security_config"`, `android:usesCleartextTraffic="true"` and `android.permission.INTERNET` — read out of `build/app/intermediates/merged_manifest/` |
| `flutter build ios --no-codesign` | **rc 0**, `Runner.app` 16.7 MB | the **built binary** plist carries `NSAppTransportSecurity` → `NSAllowsLocalNetworking: true`, the `NSLocalNetworkUsageDescription` string, and `MinimumOSVersion 15.0` — read with `plutil` |
| `flutter build apk --release` | **rc 0**, `app-release.apk` **50.7 MB** (50,725,304 bytes) | the artefact C6 says we distribute can actually be produced. **Debug-signed**, by the decision recorded at `android/app/build.gradle.kts:29-34`: C6 makes distribution a direct APK rather than a store upload, so there is no release keystore and inventing one before there is a release to sign is a §1 violation. Re-measured at M3.R on the remediated tree |

Neither proves a socket opens. Backlog rows 3–6.

### Debt this milestone knowingly accepts

- **NF2's exit criterion is met by proxy.** The invariants are gated; the
  1460 µs/frame number is labelled and ungated; real frame timing is backlog
  row 1.
- **There is no platform `SecretStore`**, so the password is re-typed on every
  cold start. Unchanged from M2, now visible to a user. Backlog row 12.
- **No poster disk cache.** SPEC §7's `cache/posters/` is deferred; memory is
  bounded by Flutter's `ImageCache`, which is backlog row 7 because nothing here
  approaches its limit.
- **No golden tests, against SPEC §9.** Nothing verifies pixels. A committed
  golden is stable for one platform and one engine revision, and this repo
  develops on macOS while CI runs `ubuntu-latest`. Layout and accessibility
  assertions stand in — and did catch a `RenderFlex overflowed`. Backlog row 9.
- **The Android network security config and the iOS ATS keys are asserted by
  content and compiled, never exercised on a device.** Backlog rows 3–5.
- **iOS will not reach a plain-http server outside the local network**, because
  `NSAllowsArbitraryLoads` is deliberately not set. F1's warning says so in
  words; backlog row 5 checks whether the words are true.
- **The live suite's widgets do not issue their own calls** — backlog row 14.
  Narrowed at M3.R: the identifiers those widgets pass are now asserted, so the
  remaining gap is the socket rather than the wiring.
- **A seventh constitution check**, `app_no_raw_http`, baseline 0.
- **One mutation exclusion added**, for two mutants that are genuinely
  unkillable: every permutation of `Object.hash`'s arguments satisfies
  `hashCode`'s only contract. Verified by hand, including the swapped-pair test
  that passes either way. It costs a third mutant, and the pattern has to cover
  the whole statement — recorded above. **The third one is not "a permutation
  already being killed", as this said until M3.R:** a `--dry -v` diff shows it
  is the builtin `&&`-negation rule running into the excluded statement and
  producing text that does not compile, so it was killed by the compiler rather
  than by an assertion. Consequence nil, but `other.size == size` now has no
  mutant at all and field order rests on the two constructor swaps.
- **`FILEFIN_MUTANTS_ALLOW_ZERO` was not used at M3, and WAS used once at
  M3.R** — for `packages/filefin_api`, whose only changed lib source is a
  barrel of `export` declarations. Which of the two causes it was, and the
  evidence, is in the M3.R section below.
- **`MAX_UNCOVERED` was not raised.** It came close twice and both times the
  answer was code rather than the number: `const FileFinApp()` was uncoverable
  because a canonicalised const invocation executes nothing (one test builds it
  with a runtime key), and `_depthOf`'s "gave up" return value was a line no
  input could reach, so it was deleted (§1).
- **`just it` is still local-only**, now over two suites, so the app's live path
  is unprotected in CI as well.
- **`flutter_lints` and `cupertino_icons` were deleted** from `flutter create`'s
  output in the commit that produced it, along with `web/`, `macos/`, `linux/`,
  `windows/`, the scaffolded `widget_test.dart` and the app-level `.gitignore`
  the root already covers.
- **CLAUDE.md §4 vs `docs/architecture.md` on pinning is RESOLVED**, not
  outstanding. The user approved amending the constitution to state exact
  pinning throughout; both edits are in the tree and `docs/architecture.md`'s
  pinning section now opens "Reconciled at M3".

---

## M2 — what was built

| Step | Deliverable |
|---|---|
| M2.0 | Two gate fixes, alone, with both-directions proofs: `secret_tostring` blind to `interface`/`mixin` class modifiers; `check-deps.sh` not scanning `integration_test/` |
| M2.1 | `ServerId` in `filefin_core` — closes A2 |
| M2.2 | `packages/filefin_api`: pubspec, barrel, the sealed error hierarchy, `mapDioException` |
| M2.3 | `test/support/stub_server.dart`, `transport.dart`, `json_response.dart`, `probe_result.dart` + `server_probe.dart` (F1) |
| M2.4 | `lib/src/tls/` — `CertificateFingerprint`, the pure `decidePin`, `CertificatePinner`, `pinnedAdapter`, two committed test certificates (F15) |
| M2.5 | `secret_store.dart`, `credentials.dart`, `session.dart` (F2), plus a third gate fix |
| M2.6 | `auth_interceptor.dart` (F3) and `client.dart`, plus a fourth gate fix |
| M2.7 | `tool/run-integration.sh`, `just it`, `check-all: check it`, four integration suites |
| M2.8 | This section, `docs/architecture.md`, `docs/risks.md` R5, and the SPEC/server-api corrections |
| M2.9 | Remediation of three adversarial reviews — one exploitable pinning bypass, two gates that could not fail, four vacuous tests |

**Numbers as measured, not as hoped**, after M2.9. `just check` exits 0 on a
clean tree with **zero gate warnings**. `just it` exits 0: **20 integration
tests in 4 seconds** against the real `filefin` v0.20.3 binary, with a committed
floor of 20 and a runtime refusal of any skipped test. Coverage **100%
(749/749)** with **0 uncovered lines against a ratchet of 0**. **896 tests** in
all (124 in `filefin_api`, 772 in `filefin_core`), plus the 20 integration
tests, which `dart test` counts separately because they are a separate suite.
The M2.9 diff produced **97 mutations over 9 changed lib sources, 0 undetected,
0 timeouts**. The constitution baseline is still **0 across all six checks**.

The pre-remediation figures, for comparison: 19 integration tests, 726/726
lines, 884 tests, and 138 of 138 mutants over the whole milestone
(`FILEFIN_MUTANTS_BASE=7412862`, the last M1 commit) — `filefin_core`'s single
M2 change, `ServerId`, produces **0 mutants** on that run, which is the
declaration-only case the one use of `FILEFIN_MUTANTS_ALLOW_ZERO=1` covers.

### Four gate scripts had to change, and three of the four were found by real code

Every one is recorded here rather than buried in a diff, and every one was
proven in both directions on the real script.

**1. `secret_tostring` could not see `interface` or `mixin` class modifiers.**
The awk modifier alternation was `(abstract|sealed|final|base)`, so
`abstract interface class TokenStore { … }` matched the declaration pattern not
at all and was exempt from §9 entirely — while the byte-identical
`class TokenStore` was flagged. The pattern is what decides whether a class is
looked at, so a missing keyword is not a weaker check, it is no check.

**2. `secret_tostring` stopped reading a class at its first braced member.** The
declaration line was consumed by `next` *before* brace counting began, so
`depth` started at 0 and the first member line holding a balanced `{…}` read as
the class closing. Traced on real M2 code: `class Credentials {` was declared
closed at `const Credentials({required this.username, …});` on line 13, so the
`toString()` on line 38 was never seen, and **all three** new secret-bearing
classes were reported as violations while every one of them overrode it. A gate
that cries wolf teaches people to rename the class, which is the answer §9 does
not want. The declaration line now seeds the count.

**3. `check-deps.sh` did not scan `integration_test/`.** Its source list was
`lib test bin tool example`. An undeclared import in an integration suite was
therefore reported by nothing — and Dart resolves one anyway when a sibling
workspace member pulls it in, which is exactly how an undeclared dependency
survives to break a clean checkout. The proof was deliberately deferred two
steps, to M2.7, because it needs a suite to run against; it was executed there
and is in the table below.

**4. `check-mutants.sh` could wedge itself permanently.** It built temp files
with `mktemp "$TMPDIR/filefin-mutants-XXXXXX.xml"`. **BSD/macOS mktemp only
substitutes the `X`s when they END the template**: given a suffix it creates a
file called *literally* `filefin-mutants-XXXXXX.xml`, and the next run gets
`mkstemp failed … File exists` and the gate cannot run at all. The trailing
`rm -f` normally hides this; an interrupted run never reaches that line, and
from then on the gate is dead until someone deletes a file with six literal X's
in its name. Now one `mktemp -d` directory with fixed names inside.

### The mutation tool rewrote sources in place — twice — and git could not see it

Both times a `mutation_test` run was killed by a command timeout, and both times
it left a **mutated source on disk**. Both files were **untracked**, so
`git status` showed `??`, `git diff` had nothing to compare against, and
`dart analyze` was clean:

| File | What was left behind | How it presented |
|---|---|---|
| `lib/src/tls/fingerprint.dart` | `i += 2` rewritten to `i = 2` | a test that had passed minutes earlier exhausted the heap |
| `lib/src/auth_interceptor.dart` | `handler.next(options);` **deleted** | every F3 test timed out at 30s with the server never receiving the request; `analyze` stayed clean because a `void` method may return without calling its handler |

Neither was found by a gate. The first took a variant bisect over dio adapter
configurations; the second took wrapper interceptors inserted around the chain.

**Two things changed as a result.** `git add -N` is now used on every new file
as soon as it is written, so `git diff` can see an in-place rewrite even before
the first real commit. And `_group`'s indexed loop in `fingerprint.dart` was
replaced by a regex over byte pairs — not cosmetics: `for (var i = 0; …; i += 2)`
hands the gate an `i += 2` to rewrite as `i = 2`, and the resulting infinite
loop is reported as a **timeout**, which `mutation_test` counts as *undetected*
rather than killed. A mutant that turns a failure into a hang is a mutant the
gate cannot score.

### F15 was built differently from the plan, because the plan leaked the request

The plan pinned OS-trusted certificates through dio's `validateCertificate`.
Measured against dio 5.11.0 with a real TLS server:

| Hook | When it runs | Server recorded |
|---|---|---|
| `badCertificateCallback` → false | inside the handshake | **nothing** (`[]`) |
| `validateCertificate` → false | after the response headers arrive | **the request** (`[/w]`) |

So `validateCertificate` rejects; it does not block. A design resting on it
would hand the request — session cookie included — to a server whose
certificate had changed, and only then object. But `badCertificateCallback`
alone is not enough either, because dart:io calls it only for a chain the
context does not trust, so an OS-trusted certificate never reaches it.

**What was built:** whenever a pin exists, the client is constructed on
`SecurityContext(withTrustedRoots: false)`, which routes *every* certificate
through the handshake-time hook and makes the pin decision happen before any
bytes are sent. With no pin, the default context is used and ordinary public
HTTPS behaves exactly as the OS says. Both hooks remain wired to the same pure
`decidePin`, because one is per **connection** (a pooled connection skips it)
and the other per **response**.

Every refusal test asserts the TLS server recorded **zero requests**. That is
what makes "blocking" a measurement rather than a claim.

### Both concurrency guards were proven necessary, separately

The plan predicted one test would discriminate both. It does not:

| Guard deleted | Which test goes red |
|---|---|
| the generation counter | "a stale generation returns without a request at all" |
| the in-flight future | "eight concurrent callers cause exactly ONE login" |

The 8-concurrent test alone would **not** have caught a missing generation
counter, because the in-flight future collapses that case. Both tests exist.

### The stale-socket surprise did not happen, so nothing was written for it

The plan warned that after `server.restart()` a pooled TCP connection might
surface `HttpException: Connection closed before full header was received`
instead of a clean 401, and that F3 — which keys on a status code — would then
never fire. Measured: it does not. The restart produces a clean 401 and F3
recovers, across all four integration suites. **No retry-on-`connectionError`
was written**, per §1, and the evidence that none is needed is that 19 tests
pass without one. If a device ever shows the other shape, that is the moment.

### Deviations from the plan, with the reason

- **`SecretStore` is an `abstract base class`, not `abstract interface class`.**
  `base` forces subtypes to `extend` rather than `implement`, which makes the
  redacting `toString` *inherited* instead of merely recommended — an interface
  could only ask. `secret_store_test.dart` proves it with a store that
  overrides nothing and still prints `ForgetfulSecretStore(<redacted>)`. The
  M2.0 gate fix that this shape motivated stands on its own: `interface class`
  and `mixin class` are shapes this tree can still produce, and both were
  proven with a probe.
- **`ProbeResult` is in `probe_result.dart`, separate from `server_probe.dart`**,
  for the same reason `errors.dart` is separate from `error_mapper.dart`:
  `dead_types` requires construction outside the declaring file.
- **A non-2xx from `GET /api/state` is `NotAFileFinServer`, not
  `ServerUnreachable`.** That route is unauthenticated and always answers 200
  (`install.go:24`), so anything else proves the thing at that URL is not
  FileFin's state route. Only a transport failure is "unreachable" — the two
  lead a user to different actions, and merging them is how a wrong port looks
  like a wrong product.
- **`transport.dart` sets `ResponseType.plain`**, which the plan did not
  specify. dio's default decodes the body itself when it likes the content
  type, which hands two decisions to a dependency that belong here. Measured
  consequence of the default: a malformed body under an `application/json`
  header makes dio's transformer throw, arriving as `DioExceptionType.unknown`,
  which `mapDioException` can only read as a connection failure — so a
  truncated payload would be reported as "could not reach the server".
- **`Credentials` has no `==`/`hashCode`.** It had; the mutation gate reported
  four survivors over them because nothing compares two Credentials. Deleted
  rather than tested: four untested branches nothing needs are §1 and §5, and
  deleting a comparison beats excluding a mutant.

### Gate proof log — M2

Every row was executed against the real script. Both exit codes were observed.

| Gate | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `constitution` / `secret_tostring` — modifiers | `abstract interface class TokenStore`, no `toString()` | **1** (was **0** before the fix) | the same class with a `toString()` | 0 |
| same | `mixin class SecretHolder`, no `toString()` | **1** (was **0**) | probe deleted | 0 |
| `constitution` / `secret_tostring` — brace counting | the three real M2 classes, **all of which override `toString()`** | **0** (was **3** false positives) | — | — |
| same | `Credentials` with its `toString()` deleted | **1** | restored | 0 |
| same | M0's original probe, `class SessionCookie` with no `toString()` | **1** | — | — |
| same | `SessionCookie` with a `toString()` **after** a braced member | **0** (was **1**, wrongly) | — | — |
| `deps` — `integration_test` scope | `import 'package:kiri_check/…'` in `browse_test.dart`, undeclared in that pubspec but declared by a sibling workspace member | **1** (was **0** — invisible) | import removed | 0 |
| `mutants` — mktemp | the old `…-XXXXXX.xml` template, called twice | 1st **rc 0 with a LITERAL path**, 2nd **rc 1**, gate wedged | `mktemp -d …-XXXXXX` twice | 0 and 0, two distinct dirs |
| `it` — missing binary | `FILEFIN_BIN=/nonexistent just it` | **1**, names the binary and prints the build command | real binary | 0 |
| `it` — zero tests | every `*_test.dart` moved out of `integration_test/` | **1**, "a recipe over zero tests reports success" | moved back | 0 |
| `it` — a skippable test | one test marked skippable | **1**, names the file and line | reverted | 0 |
| `it` — F3 itself | `AuthInterceptor`'s 401 branch short-circuited | **1**, the restart test fails | restored | 0 |
| F1's conjunction | the `needsSetup` half of the probe's key check deleted | **1** test red, exactly the discriminating one | restored | 14 of 14 |
| F15's policy | `decidePin`'s changed branch inverted to Accept | **5** tests red including "pinned to A, served B" | restored | 26 of 26 |
| F3's concurrency | the generation guard deleted | the stale-generation test red | restored | 25 of 25 |
| same | the in-flight future deleted | the 8-concurrent test red | restored | 25 of 25 |

**Nothing is deferred out of M2.** M2.0(b)'s proof was deferred two steps by
design and executed at M2.7.

### M2.8 — remediation of three adversarial reviews

Three reviews (gate, security, contract) went at M2. One finding was an
exploitable pinning bypass; two gates could not fail the way they claimed; four
tests were vacuous. What follows is what changed and what was measured.

**S1 [CRITICAL] — the pin was compared against the CA, not the leaf, and the
cookie went out before the leaf was checked.** `badCertificateCallback` is
handed the certificate at which chain verification *failed*, which under
`withTrustedRoots: false` is the top of the chain. With a self-signed peer the
chain is one certificate long and leaf == root, so the entire suite — every test
in `certificate_pinner_test.dart` — passed while the mechanism was wrong for
every real deployment. A private CA in front of a self-hosted server is F15's
stated common case.

Measured against a real `[leaf, CA]` chain (`test/support/certs/server_c`,
issued by `ca`), before and after, counting **bytes the peer received** rather
than exception types:

| Step | Before | After |
|---|---|---|
| unpinned — what the TOFU prompt shows | `/CN=filefin-test-ca`, `4c:b6:…` (**the CA**) | `/CN=filefin-test-c`, `a5:fb:…` (**the leaf**) |
| pinned to the value that prompt offered (the CA) | `CertificatePinMismatch` … **106 bytes reached the server**, cookie included | refused, **0 bytes** |
| pinned to the server's REAL certificate | **refused** — a correct pin rejected | 200, request goes through |
| impostor holding another certificate from the same CA | **106 bytes reached the impostor** | refused, **0 bytes**, and the message names the impostor's own leaf |

The fix is `HttpClient.connectionFactory`: `CertificatePinner.connect`
establishes the socket with `SecureSocket.startConnect`, compares
`socket.peerCertificate` — which *is* the leaf — against the pin, and
`destroy()`s before dart:io writes a request byte. `onBadCertificate` returns
true not to relax anything but to learn the OS's verdict, which is
`decidePin`'s third input. `validateCertificate` stays as the per-response
backstop for pooled connections, and `badCertificateCallback` is now left null,
which is dart:io's fail-closed default. `CertificatePinMismatch.toString()` no
longer ends "Nothing was sent." — on a pooled connection that is false, and the
variant cannot tell which case it is.

**The fixtures are the real fix.** `ca`, `server_c` and `server_d` are a private
CA and two leaves it signed; `server_d` is the impostor. A self-signed-only
fixture set cannot fail this test, which is why it did not.

**S6 does not reproduce, and it is not fixed.** The review predicted that dio's
`receiveTimeout` was time-to-headers and that a drip-fed body would hang forever
past it. Measured against dio 5.11.0 with the exact `fileFinBaseOptions` this
client uses: a stalled body aborted after **2038 ms** and a body dripping two
bytes every 100 ms aborted after **2005 ms**, both under a 2 s timeout. The
adapter's deadline covers the whole receive rather than resetting per chunk, so
`transport.dart`'s "applied to all three phases" is true. A `withTotalDeadline`
wrapper was written, measured to be redundant, and **removed** (§1); what stayed
is a regression test with a real drip-feeding server, because this is a fact
about a pinned dependency.

**S7 is closed by S5's fix rather than by its own.** With `followRedirects:
false` a request cannot reach a host other than the one asked for, so the
`decisionFor(requested)` lookup can no longer miss, and `_seen` is bounded at
one entry per pinner — one per server.

**C6 was measured and left alone.** The two production sites that can raise
`SessionExpired` *are* individually pinned, by the unit suite: deleting
`error_mapper.dart`'s `401 => SessionExpired` turns **7** tests red and deleting
`session.dart`'s no-password throw turns **3** red. What the review observed is
that the *integration* suite reaches both through one path — which is what an
end-to-end suite is for. No change.

#### Gate proof log — M2.8

Every row executed against the real script or the real suite; both exit codes
observed each time.

| Gate / test | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `it` — skip marker (G1) | `@Skip('…')` library annotation | **1** (was **0**: 19 tests → 12, "All tests passed!") | reverted | 0 |
| same | `solo: true` | **1** (was **0**) | reverted | 0 |
| same | `markTestSkipped(…)` + early return | **1** (was **0**) | reverted | 0 |
| same | `skip: true` — the shape the old marker caught | **1** | reverted | 0 |
| `it` — `dart_test.yaml` | an empty `dart_test.yaml` in the package | **1** (was **0** — invisible to any `*.dart` grep) | deleted | 0 |
| `it` — runtime `~N` (G1) | grep marker blinded to `ZZ_NO_SUCH_MARKER`, then one test skipped | **1**, `+19 ~1` refused | marker restored | 0 |
| `it` — test-count floor (G1) | one test deleted | **1**, "only 19 ran; floor is 20" | restored | 0, "20 tests, floor 20" |
| `constitution` / `secret_tostring` (G2) | `static const template = 'Bearer {';` in a secret class with no `toString()` | **1** (was **0** when the class is the last file scanned) | — | 0 |
| same | `// … we open a brace here: {` | **1** | — | 0 |
| same | a doc-comment sample containing `if (x) {` | **1** | — | 0 |
| same | `static final re = RegExp(r'^\{');` | **1** | — | 0 |
| same | a class whose braces never balance (END flush) | **1** | — | 0 |
| same | the false positives 1b fixed: named-parameter ctor + `toString()`; a braced string + `toString()` | **0** each | — | 0 |
| `constitution` / `core_purity` (G4) | `import 'package:flutter/widgets.dart';` in **`filefin_api`** | **1** (was **0** — the scan never looked there) | deleted | 0 |
| same | `import 'dart:ui';` in `filefin_api` | **1** | deleted | 0 |
| same | `flutter: {sdk: flutter}` in `filefin_api`'s pubspec | **1** | reverted | 0 |
| same | `import 'dart:io';` in `filefin_core` — the determinism half must stay core-only | **1** | deleted | 0 |
| `coverage-check` — uncovered ratchet (G3) | 1 untested line (`745/746`) | **1** | 746/746 | 0 |
| same | 6 untested lines | **1** (the 50% floor alone: **0**, reporting `99%`) | — | — |
| same | 100 untested lines | **1** (floor alone: **0**, reporting `87%`) | — | — |
| S1 — the chain fixture | the pre-fix `badCertificateCallback` pinner, against `[leaf, CA]` | **4** tests red, incl. `Expected: <0>  Actual: <146>` bytes | fixed pinner | 14 of 14 |
| S2 | `response.headers.value('retry-after')` on a duplicated header | **1** red | list form | 0 |
| same | `Headers.value(contentType)` on a duplicated header | **1** red | list form | 0 |
| S3 | `_refuseWhileRejected()` deleted from `_renew` | **1** red — 10 logins instead of 1 | restored | 0 |
| S4 | one probe message back to the un-redacted `$url` | **1** red | restored | 0 |
| S5 | `followRedirects: false` removed | **1** red — `client.me()` returned `AuthResult(user: attacker, admin: true)` from a cleartext impostor | restored | 0, impostor contacted 0 times |
| C1 | `logout`: `postUri` → `getUri` | **1** integration test red (was **0**: 772 unit + 19 integration all green) | restored | 20 of 20 |
| same, unit half | ditto | **1** red — `session_test` asserts the method | restored | 124 of 124 |
| C2 | `transcode: json['watched']` in the generated decoder | **1** integration test red (was **0** — the two were correlated in the seed) | restored | 20 of 20 |
| C3 | `_repointCache` skipped | **2** red — `files[].path` came back `/Users/…/filefin-test/run/data/…` | restored | 20 of 20 |
| C4 | `_refuseWhileBlocked` made a no-op | **1** red (the old 100 ms timing assertion could not see it: a loopback 429 is 0.31 ms) | restored | 0 |
| C5 | `ApiPaths.categories` → `/api/categories/` | `filefin_core` **1**, `filefin_api` **0** — see below | restored | 0 |

**C5's limit, stated rather than claimed away.** `StubServer.on` now takes a
required method, and that closes the method half: `logout` as a GET is red, and
so is any registration that lies about its verb. It does **not** close the path
half, and structurally cannot — the stub takes its path from
`urls.X.path`, the same expression the client evaluates, so a wrong route is
symmetric no matter what the stub does. A trailing slash on `ApiPaths.categories`
is caught by `filefin_core`'s literal `urls_test.dart` and by `just it`, and by
nothing in `filefin_api`. That division is the design; a stub cannot be evidence
about a route.

**What the harness now does that it did not.** `FixtureRun.create()` repoints
the copied SQLite cache at the copied media (`media.path`, `media_files.path`,
verified, `sqlite3` refused up front by `run-integration.sh`) and writes a
`watched` state into each copy's `meta.json` that is the **opposite** of
`transcode`. The second half is also what makes the suite reproducible: seeding
happens only when `$RUN/data` is missing, so before this, whether a machine's
library carried per-user state depended on whether fixtures had ever been
captured there. `run-integration.sh` also reaps stale `filefin-it-*` directories
and orphaned `filefin serve` processes before each run, because `addTearDown`
does not run when the isolate is killed — 5 orphans and 19 leaked directories
(~80 MB) had accumulated. There is deliberately **no** port-collision claim
attached to that: `fixture_run.dart` binds port 0, the OS does not re-hand a
LISTENing port, and `just it` was measured passing twice with five orphans alive.
`harness.dart`'s comment used to say otherwise; it now says this.

### Debt this milestone knowingly accepts

- **`FILEFIN_MUTANTS_ALLOW_ZERO=1` was used on one commit** — M2.1, `ServerId`.
  The cause is the first of the two the gate names: a declaration-only diff.
  The entire non-doc addition to `lib/` is one line, an `extension type const`
  with no operator, literal or conditional. Verified by reading the diff.
- **There is no platform `SecretStore`.** F2's "platform secure store" is a port
  plus an in-memory implementation until M7. **Nothing at M2 proves a password
  survives an app restart** — the in-memory store is the production *cache*, and
  the persistence half does not exist yet.
- **`just it` now needs `sqlite3` as well as `ffmpeg` and the binary.** The
  harness repoints the copied cache with it; the gate refuses up front rather
  than producing a library that silently reads the shared seed.
- **F15's OS-trusted-certificate-change arm is enforced but unexercised.**
  Proving the wiring needs a CA-signed certificate for `127.0.0.1`. `decidePin`
  is pure and table-tested over every combination, which confines the gap to
  wiring rather than policy — but it is a gap. `docs/risks.md` R5.
- **The `filefin` binary has no TLS listener**, so SPEC §10's "self-signed
  server" half of M2's exit criterion is met against a Dart
  `HttpServer.bindSecure` with committed certificates. A real handshake, not a
  real FileFin. R5.
- **The coverage floor is tree-wide, and the floor is not what protects a
  diff.** `check-coverage.sh` reads one concatenated lcov, so a well-covered
  package can mask a poorly covered one. A **per-package floor is proposed, not
  smuggled in**: it is a larger gate change than M2 should make on its way past.
  What M2.8 did add is the thing the percentage cannot do — an absolute ratchet
  on uncovered lines, `MAX_UNCOVERED=0` in `tool/coverage-gate.sh`. Measured
  against the M2 baseline, the 50% floor alone exited 0 on 6 untested lines
  (`99%`) and on 100 (`87%`), and only failed at 727; the ratchet fails at one.
  Raising it is an edit to that file, visible in a diff, with a reason here —
  not a fourth environment override, because CLAUDE.md's list of three is the
  complete list.
- **The mutation gate still gives zero assurance for `filefin_core`'s wire
  models and converters.** Unchanged from M1 — nothing in them is an operator,
  literal or conditional. `filefin_api`'s healthy mutant count must not be read
  as covering them.
- **Endpoints deliberately not built:** search, home rows and tags (M6), poster
  bytes (M3), playback and progress (M4/M5). Each is documented and captured
  already; §1 says the code arrives with the screen that needs it.
- **Error variants deliberately not built:** `TranscodingDisabled` (415, M5,
  where F12's wording *is* the variant) and `BadRequest` (400, M4/M6). At M2 the
  only 400 the server can produce is `bad category id`, and `CategoryId` is an
  `int`, so nothing can construct that request. 403 is never — admin only (C4).
  `dead_types` would fail each of them today.
- **Android and iOS cleartext-traffic configuration is an M3 prerequisite.**
  F15 permits plain `http://` for LAN servers; Android needs
  `cleartextTrafficPermitted` in a network security config and iOS needs
  `NSAllowsLocalNetworking` in `Info.plist`. Neither file exists — there is no
  `apps/mobile` yet — and without them every plain-http server fails on device
  for a reason that looks nothing like its cause.
- **`just it` is local-only.** CI runs `just check` and cannot run `it`, so the
  integration suite protects a developer's machine and not the pipeline. A CI
  job would need a `filefin` binary built from upstream (Go plus a Node web
  build); a job that skipped without one would report success while checking
  nothing, which is the shape this repository refuses everywhere else.
- **`filefin_api` has one `// ignore:` per gate-adjacent decision — four in
  total**, each with the reason written immediately above it:
  `avoid_catching_errors` twice (at the wire boundary, where a `TypeError` from
  a generated decoder is a fact about the payload rather than a bug of ours) and
  `avoid_redundant_argument_values` twice (`withTrustedRoots: false` and
  `ProcessSignal.sigterm`, where the argument *is* the mechanism and a reader
  must not have to look a default up).
- **CLAUDE.md §4 and `docs/architecture.md` disagree on version pinning**, and
  M2 followed the stricter reading (exact pins for every new dependency) rather
  than picking. §4 says "pre-1.0 packages are pinned exactly", which implies
  caret above 1.0; architecture.md says exact on introduction. **This wants a
  one-line reconciliation in CLAUDE.md**, which M2 has not made because
  CLAUDE.md is the constitution and editing it to match one's own code is the
  wrong direction.
- **F11 is not dropped, it is split.** The M2 brief lists it; SPEC §10 puts it
  at M7. M2 delivers the *mechanism* — one client per `ServerId`, each with its
  own cookie jar, secret namespace and certificate pin — and M7 delivers the
  switching UI.

---

## M1 — what was built

| Step | Deliverable |
|---|---|
| M1.1 | `packages/filefin_core/` — pubspec (`resolution: workspace`), analysis options including the root, the `lib/filefin_core.dart` barrel, `test/support/fixtures.dart` |
| M1.2 | `lib/src/ids.dart` — `MediaId`, `CategoryId`, `FileIndex`, `SubtitleIndex` as `extension type … implements Object` |
| M1.3 | `lib/src/json_converters.dart` — one `JsonConverter` per ID type |
| M1.4 | Nine `@freezed` wire models under `lib/src/models/`, `build_runner` + `freezed` + `json_serializable` restored with their rent, `just codegen`, `build.yaml`, and the deferred `codegen-check` proof |
| M1.5 | `lib/src/search_field.dart` — the full `db/search.go` field vocabulary as an enum |
| M1.6 | `lib/src/urls.dart` — `ApiPaths` (every route as one full literal) and `FileFinUrls` |
| M1.7 | `lib/src/resume/` — `ResumePointer`, `WatchState`, `ProgressReport`, `WatchView`, and the engine: `applyProgress`, `deriveView`, `resolveIndex`, `setWatched`, `clearWatched`, `clearProgress`, `setFavorite`, `setRating` |
| M1.8 | `lib/src/playback/decision.dart` — `NetworkType`, `PlaybackSettings`, the sealed `PlaybackDecision` hierarchy and `decide()` |
| M1.9 | The barrel's final export list, and the four deferred gate proofs below |
| M1.10 | Remediation of three adversarial reviews: a coverage-exemption race that let untested code through, a reachable URL defect, a mutation-gate blind spot inherited from the tool's own builtin exclusions, two undefended engine mutants, and four documentation claims that were false |

**Numbers as measured, not as hoped**, after M1.10: `just check` exits 0 on a
clean tree. Coverage **100% (331/331 lines)**. **174 of 174** mutants killed
across every lib source M1 added (`FILEFIN_MUTANTS_BASE=ca00dd9`, the last M0
commit), 0 timeouts. **769 tests**, of which 601 are captured resume vectors and
10 are property runs. `core_purity` 0, and the whole constitution baseline is
still 0 across all six checks.

The mutant count **rose** from the 149 reported before remediation, and the rise
is the finding rather than an improvement in the code. **+7** of it is
`engine.dart` going 62 → 69 because the gate had stopped asking about two lines
it should have been asking about (below); **+18** is new code in `urls.dart` and
`watch_state.dart`. A number going up because the instrument was fixed is worth
more than the same number holding.

**M1.1 and M1.2 could not be separate commits.** A package with no lib source
and no test cannot pass `just check`: `run-tests.sh` fails at zero test files
and the coverage gate fails on an lcov with zero `DA:` records. M1.3 joined them
for the same reason — a barrel and four extension types compile to no executable
code at all, so the lcov was empty until the converters landed. M1.5 and M1.6
are also one commit: separating them would have left `SearchField` with no
consumer but its own test, a dead branch by §5 for exactly as long as it took
to write the next commit.

### Two M0 gate scripts had to change for the first package to land

Both are recorded here rather than buried in a diff, because a gate that
changes shape mid-milestone is exactly the thing a reviewer must see.

**`run-coverage.sh` named a `package_config.json` that a workspace member does
not have.** `dart pub get` writes one `package_config.json`, at the workspace
root; members get none. The script passed `$pkg_dir/.dart_tool/…`
unconditionally, so `format_coverage` printed its usage and the run died on the
following `cat`. It now prefers the package's own and falls back to the root's,
failing loudly if neither exists.

**`run-coverage.sh`'s "every lib source must produce a coverage record" rule
required the impossible of a file with no executable code.** The rule (finding
G2) exists because `dart test --coverage` omits never-loaded libraries
entirely, so untested code is absent from the denominator rather than sitting at
0%. But the VM emits a hitmap entry per *compiled function*, and a barrel of
`export`s or a set of `extension type` declarations compiles to none. Measured:
`lib/filefin_core.dart` and `lib/src/ids.dart` are absent from the raw
`.vm.json` hitmap even with a test that imports the barrel and constructs all
four IDs.

The exemption added is **mechanical, not a list**: a missing record is excused
only when the file is verified line by line to contain nothing but `library` /
`import` / `export` directives and empty-bodied `extension type` declarations.
There is no allowlist and no marker comment, because both are things a reviewer
can be talked past — to be exempt, a file must literally have nowhere to put a
statement. Exempted files are printed on every run so the set stays visible.

Proven both ways on the real script:

| Fail input | Exit |
|---|---|
| `lib/src/never_imported.dart` — one function, nothing imports it | **1**, names the file |
| `lib/src/sneaky.dart` — a `library;` + `export` barrel with a single `int sneak() => 1;` smuggled in | **1**, names the file |
| the clean tree (barrel + `ids.dart` exempt, `json_converters.dart` covered) | 0 |

### `codegen-check` could not see a hand-edit that was staged

This is the deferred M1.4 proof, and performing it found the gate had a hole.

The plan's proof was "hand-edit one character in a committed `*.g.dart` → exit 1
→ revert → exit 0". That passed — but only because `git diff` compares the
worktree against the index, so an **unstaged** edit is caught by git alone and
build_runner never has to notice anything.

`git add` the same edit and the gate went green over it. build_runner is
incremental: it hashes its own outputs and, on unchanged inputs, reports
`30 skipped, wrote 0 outputs` without looking at what is on disk. So nothing
regenerated, `git diff` had nothing to compare, and the gate printed "generated
output is up to date" about output nobody generated. §10 is precisely the rule
that "someone edited generated output" must not survive, and the shape it does
not survive as is a commit — which is always staged.

`check-codegen.sh` now deletes `$pkg/.dart_tool/build` before building, forcing
a full rebuild (~10s per package). Only the **cache** is removed, never the
generated files: `build_runner clean` deletes them from the worktree, so a build
that then failed would leave the tree gutted.

| Input | Before | After |
|---|---|---|
| clean tree | 0 | 0 |
| one character changed in a committed `*.g.dart`, unstaged | 1 | **1** |
| the same edit, **`git add`ed** | **0**, "generated output is up to date" | **1**, prints the diff and names §10 |
| reverted | 0 | 0 |

### M1.9 — the four deferred gate proofs, on real code

Every row was executed against the real scripts on the real package.

| Gate | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `test` — zero-test guard (deferred from M0.9) | moved all nine `*_test.dart` out of `packages/filefin_core/test/` | **1**, `has no *_test.dart files` | moved back, 9 files | 0 |
| `codegen-check` (deferred from M0.9, done at M1.4) | one character changed in a committed `*.g.dart`, **staged** | **1** | reverted | 0 |
| `coverage-check` on real code | `lib/src/floor_probe.dart` — 1 covered line plus 400 imported-but-never-called ones | **1**, `Coverage: 44% (328/730 lines) … below the 50% floor` | removed | 0, `Coverage: 100% (327/327 lines)` |
| `mutants` on real code | every equal-to-threshold assertion deleted from `decide_test.dart` (the split-out boundary test and both `delta == 0` table rows), `FILEFIN_MUTANTS_BASE=HEAD~1` | **1**, 1 of 7 undetected | restored | 0, 7 of 7 killed |

The coverage probe is worth naming precisely: it is a file a test **imports**,
so it appears in the denominator. Untested code that nothing imports fails
earlier and differently (the missing-record check, proven at M1.1), and the two
are separate holes.

### `just mutants` was not asking the boundary question at all

Performing the M1.9 mutation proof found the gate weaker than the plan assumed,
and the discovery is worth more than the proof was.

The first attempt did what the plan said — delete the equal-to-threshold
assertions from `decide_test.dart` — and `just mutants` still reported **6 of 6
killed**. Checked by hand: with those assertions gone, changing
`file.size > settings.meteredWarnBytes` to `>=` passed the whole suite. The hole
was real; the gate simply never generated that mutant.

`mutation_test` 1.7.1's builtin rules mutate `<=` and `>=` (to `==` and to the
strict form) but have **no rule for a bare `<` or `>`**. A strict comparison was
never weakened to a non-strict one, so the off-by-one at a boundary — the single
most common comparison bug, and the one CLAUDE.md §3 cites mutation testing for
— was invisible everywhere in the tree. The 6 mutants it did find on `decide()`
were all condition negations.

Two rules were added to `mutation_rules.xml`. They require whitespace on **both**
sides, which is what keeps them off everything that is not a comparison:
`List<bool>` and `Map<String, int>` have no space before `>` or after `<`, `=>`
has `=` immediately before the `>`, and `<=`/`>=` have `=` immediately after.

The rules found two survivors in the resume engine, and both are **genuinely
equivalent** — verified by hand, not assumed:

- `if (x < 0) return 0;` in the rounding. `<=` differs only at `x == 0`, and
  there both branches produce 0, since `(0.0 + 0.5).toInt()` is 0.
- `targetSeconds > state.pointer!.seconds` in `applyProgress`. `>=` differs only
  when the two are equal, and then the branch writes a pointer holding exactly
  the two values it already held. `WatchState` compares by value.

Both are excluded by their **exact text** rather than by line number, so an edit
elsewhere cannot silently widen the exclusion and a change of shape simply stops
matching and brings the mutants back. Each carries its reason and retirement
condition in `mutation_rules.xml`, per §3.

| Input | Before the rule | After |
|---|---|---|
| `decide_test.dart` with every equal-to-threshold assertion removed | RC **0**, `6 of 6 killed` — over a real hole | RC **1**, 1 of 7 undetected |
| the same file restored | 0 | 0, 7 of 7 killed |
| every lib source M1 added (`FILEFIN_MUTANTS_BASE=ca00dd9`) | 151 mutants, 2 undetected (both equivalent) | **149 mutants, 0 undetected** |

### glados does not exist for Dart 3, so the property tests use kiri_check

The plan names glados for the resume engine's property tests. **Every published
glados version — 0.0.1 through 1.1.7 — declares `sdk: >=2.12.0 <3.0.0`**, so
none of them resolves on any Dart 3 SDK, let alone 3.12. This is not a
constraint that can be worked around; the package has not been updated for Dart
3 at all.

`kiri_check` 1.3.1 (`sdk: ^3.4.0`) is the maintained equivalent: generators,
`forAll`, and shrinking to a minimal counterexample. Verified before adopting —
a deliberately failing property over `integer(min: 0, max: 100)` shrank to
exactly `50` and reported the seed, twice in a row identically.

It is pinned exactly and `KiriCheck.seed` is pinned in the test file. `just
mutants` runs `dart test` once per mutant, so a generator drawing a different
sample each run would turn a surviving mutant into a coin flip and the gate into
a flaky one.

### The resume oracle is live, and it was checked

601 captured vectors replay green. That on its own says nothing — a fixture is
only worth having if a plausible wrong implementation fails it. So the
`continueSeconds = pointer?.seconds ?? 0` implementation the vectors were
re-captured to catch (finding C2) was substituted into `deriveView` and the
suite re-run: **exactly 18 vectors objected**, the same 18 the capture script
set out to produce. `resume_vectors_test.dart` also asserts that count directly,
so a future re-capture that quietly drops the stale-ref grid fails rather than
passing over a weaker oracle.

The translation from the vectors' **ref space** to the engine's **index space**
is where the care went. A captured pointer whose ref is absent from `refs` maps
to `FileIndex(refs.length)` — out of range, and deliberately not `null`.
Collapsing it to `null` would reproduce every observable value and still pass all
601, but it would erase the distinction the traps exist to test and the engine
would pass them for the wrong reason. An index past the end of the list is also
what the same situation actually looks like on a client: a file list that shrank
between sessions.

### Three mutants survived the first run of the resume engine

All three were in the arguments to `RangeError.range(rating, 0, 10, 'rating')`
— the bounds carried in the error object, which the test did not read. It
asserted `throwsA(isA<RangeError>())` and nothing more, so `end: -10`, swapped
`start`/`end`, and a swapped `invalidValue` all passed.

Not excluded. The test now asserts `invalidValue`, `start`, `end` and `name`,
because those four are what a developer reads when the error fires, and an error
naming the wrong range sends them to look in the wrong place. 56 of 56 mutants
in `engine.dart` now die.

### `Uri` does not save you from a path template

M1.6's tests caught two things worth writing down, because both look like
paranoia until they are not.

**A path parameter containing `/` escaped its segment.** `ApiPaths` builds a
route as a string and `_resolve` splits it on `/`, so `MediaId('a/b')` reached
`Uri` as two segments and addressed `…/api/media/a/b`. `Uri` percent-encodes a
segment it is *given*; it cannot know a `/` inside the template was meant to be
data. Every interpolated value now goes through `Uri.encodeComponent` in
`ApiPaths` and is decoded again in `_resolve` before `Uri` re-encodes it. This
is not hypothetical for `hlsSegment`, whose segment name comes straight out of a
server-supplied playlist.

**An empty `q` goes on the wire as a bare `q`, not `q=`.** Dart's `Uri` omits
the `=` for an empty value. Go's `url.ParseQuery` reads `q` as the key `q` with
the value `""`, so the request is the same one — the test asserts what actually
goes on the wire rather than normalising it away.

### M1.10 — remediation of three adversarial reviews

Three independent reviews (the resume engine against the Go source; the gates
changed during M1, by the agent M1 was judging; the models, URLs and
constitution). Every gate changed in response was re-proven in both directions
on the real script, and the two that are nondeterministic were proven **20 times
in each direction**, because one trial of a race proves nothing.

| Finding | What was wrong | Fail input | Before | After |
|---|---|---|---|---|
| **B1** | `has_no_executable_code` (`run-coverage.sh`) was a three-stage pipeline under `set -euo pipefail`, negated with `!`. `grep -q` exits on its first match, so `sed` and `grep -v` upstream died of **SIGPIPE (141)**, `pipefail` made 141 the pipeline's status, and `!` inverted it into "no executable code". The louder the evidence of executable code, the likelier the file was exempted from the missing-record check — the exact G2 hole that check exists to close | end-to-end on the real gate: a **600-line** `lib/src/zzz_b1_probe.dart` (inside `file-size`'s 600 hard limit) whose line 1 is `int sneak(int a, int b) => a > b ? a : b;` and whose other 599 lines are `export`s; no test imports it. 20 runs | **5 of 20 exit 0**, the file printed in the "no executable code" list | **0 of 20.** Exit 1 naming the file, every run |
| B1 — at the function | the same, on the function extracted verbatim from the script | a 2001-line file of the same shape, 20 trials | **20 of 20 wrongly EXEMPT** | **0 of 20**, and 0 of 20 at 601 and 3001 lines too |
| B1 — the other direction | the exemption must still exempt | the two real files it exists for (`lib/filefin_core.dart`, `lib/src/ids.dart`), a 2001-line pure barrel, and a bare `library;` — 20 trials each | exempt | exempt, unchanged, 20 of 20 |
| B1 — smuggling still refused | the five attempts the exemption was designed against | function in a barrel; extension type with a non-empty method body; top-level `final` with an initialiser; extension-type getter; const constructor doing work — 20 trials each | not exempt | not exempt, unchanged |
| **B5** | `library[^;]*;` had no word boundary, so a *statement* beginning with those seven letters was excused | `libraryHandle bar = compute();`, 20 trials | **EXEMPT** | **not exempt**, 20 of 20. `library;` and `library foo.bar;` still exempt |
| **B4** | the `for` exclusion was `[\s]for[\s]*\(.*?\)[\s]*{` with `dotAll`. A Dart **collection**-`for` has no `{` to stop at, so `.*?` ran to the next function's brace: **lines 128-171 of `engine.dart`, 1,959 characters**, never mutated | `engine.dart` under the gate | mutated lines ran …121, 122, then jumped to **172**. `i < pointerIndex` — which decides whether the file AT the pointer is marked watched — was never mutated. 62 mutations | **69 mutations**, lines 127 and 128 now included. 69 of 69 killed |
| B4 — the fix the review proposed was not enough | tightening our copy of the pattern changed **nothing**, because `-b` re-adds mutation_test's builtin exclusions and the loose pattern is one of them. Exclusions are additive and cannot be subtracted | `engine.dart` dry-run under (a) the committed rules, (b) the tightened rules, (c) our loop exclusions deleted outright | **62, 62, 62 — byte-identical mutant lists** | `-b` dropped, builtin rules transcribed into `mutation_rules.xml`: **69** |
| B4 — what was *not* recovered | stated so the 1,959 figure is not read as 1,959 characters of hidden risk | `engine.dart` dry-run with **zero** exclusions | 329 mutations, but none at all on `setWatched`/`clearWatched`/`clearProgress`/`setFavorite` — named arguments and boolean literals match no rule | so the recovered ground is exactly the two `perFile` lines, +7 mutants. That is where `i < pointerIndex` lives |
| **B3** | `dart_lib_sources` excludes `*.g.dart`/`*.freezed.dart` **by filename**, so a hand-written file merely *named* that way is invisible to the ignore-comment guard, the missing-record check, `analyze`, `constitution`, `dupes`, `mutants`, `file-size` and `comments` — all at once | `lib/src/fake.g.dart` = `// coverage:ignore-file` + `int neverTested(...)`, **staged** | `codegen-check` RC **0**, never mentioned | RC **1**, `no generator header on line 1` |
| B3 — header typed by hand | the header alone is forgeable, so a second fact is required | the same file carrying the real `// GENERATED CODE - DO NOT MODIFY BY HAND` line | RC 0 | RC **1**, `no …/fake.dart to be a part of` |
| B3 — orphaned real output | generated output whose source was deleted | a genuine `media_detail.g.dart` copied to `orphan.g.dart` | RC 0 | RC **1**. Clean tree: RC **0** |
| **C1** | `ApiPaths._seg` percent-encoded but did not reject `''`, `'.'`, `'..'`. `Uri` deletes dot segments unconditionally — from `%2E%2E` too — so no encoding could fix it, and `_resolve` discarded empty segments as well. `MediaId('')` is the models' **own declared default**, so any payload with a missing `id` produced it | `mediaDetail(MediaId(''))`, `mediaDetail(MediaId('..'))` | `https://h/api/media` and `https://h/api/` — different routes, both answered `200 text/html` by the SPA catch-all | `ArgumentError` naming the value. `..a`, `...`, `seg0.ts` and `index.m3u8` still build normally |
| **A2** | `report.duration > 0` mutated to `!= 0` survived the entire suite: the only input that separates them is a **negative** position over a **negative** duration, which no vector and no property draw reached | mutate `> 0` → `!= 0`, run all tests | **764 tests pass** | **fails**, named: `rule 2 — crossing / a negative duration never crosses, even at a "90%" ratio` |
| **A3** | `(x + 0.5).toInt()` mutated to `x.round()` survived, with the negative clamp left intact. Vectors use 1.4/1.5/1.6 and the generators draw tenths, so neither oracle can reach the one input that separates them | mutate to `x.round()`, run all tests | **764 tests pass** | **fails**, named: `rule 4 — … the positive side differs from .round() too, not just the clamp` (`0.49999999999999994` → 1, where `.round()` says 0) |
| **C2** | `fromDetail` copied `rating` through unchecked, so a server serving `rating: 99` built a `WatchState` that this library's own `setRating` throws on | `WatchState.fromDetail(MediaDetail(rating: 99))` then `setRating(state, rating: state.rating)` | `RangeError` | `rating` reads as **0, unrated**; `setRating` returns normally. `MediaDetail.fromJson({'rating': 99})` still decodes 99 (§8 lives at the wire boundary) |

Two mutants surfaced in the remediation's own new code and neither was excluded.
The three in `urls.dart` were **inside the `ArgumentError` message string** —
prose is mutable source and nothing else in the suite reads it — so the test now
asserts that message verbatim, the same reasoning as `setRating`'s bounds. The
one in `watch_state.dart` (`rating >= 0` → `rating > 0`) was **genuinely
equivalent**, because the fallback is also 0; rather than add a third exclusion,
the operator was removed — `rating.isNegative || rating > 10` has no boundary to
get wrong. An exclusion is a piece of code the gate stops asking about; deleting
the comparison is strictly better than silencing it.

### Coverage now honours `// coverage:ignore-file`, and hand-written source may not carry it

freezed writes `// coverage:ignore-file` on line 2 of everything it generates,
and `format_coverage --check-ignore` respects it. Without that flag the
denominator was 793 lines of which 591 were freezed's pattern-matching helpers
(`when`, `maybeMap`, `whenOrNull`) — code with no caller and no prospect of one
— and the gate reported **53%** while every line we wrote was covered. That is a
broken instrument in the opposite direction from finding G2: the noise floor
swamps a real regression, so the gate could not detect one.

With the flag the figure is **100% (202/202)**. json_serializable does *not*
write that comment, so the `.g.dart` decode bodies — the tolerant decoding §8 is
actually about — stay in the denominator.

The flag opens one hole and it is closed in the same commit: a
`// coverage:ignore` comment in **hand-written** source would be a one-line
opt-out of the §3 floor. `run-coverage.sh` now fails on any such comment in a
non-generated lib source.

| Fail input | Exit |
|---|---|
| `// coverage:ignore-file` appended to `lib/src/json_converters.dart` | **1**, names the file |
| an 8-line untested function added to `lib/src/models/server_state.dart` | figure fell 100% → **96%**, so real code still counts |
| clean tree | 0, `Coverage: 100% (202/202 lines)` |

---

## M0 — what was built

| Step | Deliverable |
|---|---|
| M0.1 | Root `pubspec.yaml` (pub workspace, empty `workspace:`), `analysis_options.yaml`, `.gitignore` |
| M0.2 | `tool/common.sh` — `fail`, `repo_root`, `dart_sources`, `dart_lib_sources`, `run` |
| M0.3 | `tool/check-file-sizes.sh` + `just file-size` |
| M0.4 | `tool/check-comment-budget.sh` + `just comments` |
| M0.5 | `tool/check-constitution.sh` + `tool/constitution-baseline.txt` + `just constitution` / `constitution-accept` |
| M0.6 | `tool/check-deps.sh` + `tool/dep-allowlist.txt` + `just deps` |
| M0.7 | `tool/run-coverage.sh`, `tool/check-coverage.sh`, `tool/coverage-gate.sh` + `just coverage` / `coverage-check` |
| M0.8 | `tool/check-mutants.sh` + `mutation_rules.xml` + `just mutants` |
| M0.9 | `just fmt-check` / `analyze` / `codegen-check` (`tool/check-codegen.sh`) / `test` (`tool/run-tests.sh`) |
| M0.10 | `justfile`, incl. `tool/check-toolchain.sh` and `tool/check-hooks-status.sh` |
| M0.11 | `tool/hooks/pre-commit`, `tool/hooks/post-commit`, `just install-hooks` |
| M0.12 | `docs/server-api.md` — every user-facing endpoint, cited to upstream `file:line`, plus the resume semantics transcribed rule by rule |
| M0.13 | `seed.sh` enriched (two-file item + rich `meta.json`), fixtures captured and committed with `PROVENANCE.md` and a SHA-256 manifest; `tool/check-fixtures.sh` + `just fixtures-verify` |
| M0.13b | `tool/fixtures/capture_state_vectors_test.go` + `tool/capture-resume-vectors.sh` + `just fixtures-vectors` → `test/fixtures/resume_vectors.json`, **601 vectors captured from the real engine** across all three `Refs` branches |
| M0.14 | `docs/architecture.md`, `docs/risks.md`, this file |
| M0.15 | `.github/workflows/ci.yml` |
| extra | `tool/check-dupes.sh` + `just dupes` — jscpd was evaluated and *works* for Dart, so the gate exists rather than a note explaining its absence |
| M0.16 | remediation of three adversarial reviews: 14 gate holes closed and re-proven both ways, `docs/server-api.md` corrected against upstream and against a live server, `resume_vectors.json` re-captured with the stale-ref case (333 → 601 vectors) |

---

## Gates: both-directions proof log

CLAUDE.md: *"A gate change is not done until you have seen it fail."* Every row
below was executed. "Fail input" is the exact thing constructed; both exit
codes were observed, not inferred.

| Gate | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `toolchain-check` | ran with `PATH=/usr/bin:/bin` so `dart` is absent | **1** | normal PATH, Dart 3.12.2 | 0 |
| `hooks-status` | before `just install-hooks` | **1** | after installing | 0 |
| `hooks-status` — a stub | `.git/hooks/pre-commit` replaced by an executable `#!/bin/sh\nexit 0` | **1** | `just install-hooks` | 0 |
| `hooks-status` — a copy | `cp tool/hooks/pre-commit .git/hooks/` — executable, byte-identical, still not a symlink | **1** | `just install-hooks` | 0 |
| `fmt-check` | a `.dart` with mangled whitespace | **1** | after `just fmt` | 0 |
| `analyze` — `--fatal-warnings` | an unused local variable | **2** | removed | 0 |
| `analyze` — `--fatal-infos` | `final x = 42;` → `prefer_const_declarations`, an **info**-severity lint only. Same file with `--fatal-warnings` alone exits **0**, with the recipe's `--fatal-infos` exits **1** | **1** | removed | 0 |
| `codegen-check` | *deferred to M1.4; done, and it found a hole — see the M1 section* | **1** | reverted | 0 |
| `file-size` | 700-line `packages/_scratch/lib/big.dart` | **1** | removed | 0 |
| `file-size` — generated exemption | the *same 700 lines* renamed `big.g.dart` | **0** (correct: exempt) | — | — |
| `comments` | 60-line file, 30 `//` lines → reported 50% | **1** | removed | 0 |
| `comments` — `///` exclusion | 60-line file of **pure `///`** doc comments | **0** (correct: `///` excluded from both numerator and denominator) | — | — |
| `constitution` / `placeholders` | `throw UnimplementedError()` in a lib file | **1** | removed | 0 |
| `constitution` / `core_purity` (imports) | `import 'dart:io';` in `packages/filefin_core/lib/` | **1** | removed | 0 |
| `constitution` / `core_purity` (pubspec) | `dio: ^5.0.0` in `packages/filefin_core/pubspec.yaml` | **1** | removed | 0 |
| `constitution` / `id_typedefs` | `typedef MediaId = String;` | **1** | removed | 0 |
| `constitution` / `dead_types` | `sealed class PlaybackDecision` with `PlayDirect` constructed elsewhere and `PlayHls` never constructed | **1** (named `PlayHls`) | constructed `PlayHls` too | 0 |
| `constitution` / `undocumented_endpoint` | `'/api/categories'` literal, doc listed only `/api/state` | **1** | added it to the doc | 0 |
| `constitution` / `secret_tostring` | `class SessionCookie` with no `toString()` override | **1** | added `String toString() => '…<redacted>'` | 0 |
| `constitution-accept` — up | accepted with 1 placeholder present → **refused**, `ERROR: placeholders rises 0 -> 1`, and `tool/constitution-baseline.txt` byte-identical afterwards | **1** | — | — |
| `constitution-accept` — up, overridden | same input with `FILEFIN_ACCEPT_NEW_DEBT=1` → baseline 0 → 1 with `WARNING: … accepting new debt, not paying it` | 0 | — | — |
| `constitution-accept` — down | removed the violation → `check` printed `NOTICE: … down from 1. Debt paid.`; `accept` rewrote the baseline to 0 | 0 | — | — |
| `deps` — rent comment | `path: ^1.9.0` with no comment above it | **1** | comment added | (still 1, see next row) |
| `deps` — unused | `path` with a rent comment but no import and no allowlist entry | **1** | added to `tool/dep-allowlist.txt` | 0 |
| `deps` — undeclared | `import 'package:collection/…'` in a package whose pubspec does not list it | **1** | declared it | 0 |
| `dupes` | two 27-line Dart classes differing only in name → `1 exact clone, 25 (46.3%) duplicated lines` | **1** | one file removed | 0 |
| `coverage-check` — below floor | hand-made lcov, 1 of 10 `DA:` hit → 10% | **1** | — | — |
| `coverage-check` — sub-target warning | hand-made lcov, 7 of 10 → 70%, printed `WARN: … below the 80% target` | **0** | — | — |
| `coverage-check` — passing | hand-made lcov, 9 of 10 → 90% | **0** | — | — |
| `coverage-check` — **no data** | lcov with **zero `DA:` records** → `ERROR: no DA: records … coverage data is missing or empty` (not 0%, not a pass) | **1** | — | — |
| `coverage-check` — missing file | lcov path that does not exist | **1** | — | — |
| `mutants` | real scratch package: `int add(a, b) => a + b;` with a test asserting only `add(0,0) == 0` → 1 mutant, 1 undetected | **1** | test strengthened to `add(2,3) == 5` → 1 of 1 caught | 0 |
| `mutants` — empty diff, local | no changed Dart lib sources vs HEAD | 0, with `no changed Dart lib sources vs HEAD — nothing to mutate` | — | — |
| `mutants` — **the CI path** | clone at a committed HEAD, clean tree, `CI=true`. Old script: `nothing to mutate`, **RC 0**. New script, same tree, same second: **RC 1**, `FILEFIN_MUTANTS_BASE resolves to HEAD and the tree is clean` | **1** | `CI=true FILEFIN_MUTANTS_BASE=HEAD^` on the same tree | 0 |
| `mutants` — zero mutants | real scratch package; the only changed lib file is a barrel `export`. `Found 0 mutations` → previously a NOTICE and RC 0; now `ERROR: … produced 0 mutants` | **1** | `FILEFIN_MUTANTS_ALLOW_ZERO=1` on the same input | 0 |
| `fixtures-verify` — manifest | `jq '.title = "Sneakily Edited"'` on a committed fixture → diff against `SHA256SUMS` | **1** | restored | 0 |
| `fixtures-verify` — structural | `jq '.tags = []'` **and** a regenerated manifest, so the checksum half passes → structural assertion caught it | **1** | restored | 0 |
| `fixtures-accept` — key loss | deleted 8 top-level + 5 per-file keys from `media_detail_directplay.json`, then `accept` — the exact attack that used to launder a gutted payload → **refused**, naming each lost path, `SHA256SUMS`/`KEYS.txt` unwritten | **1** | restored, `accept` clean | 0 |
| `fixtures-accept` — key loss, overridden | same input with `FILEFIN_ACCEPT_FIXTURE_KEY_LOSS=1` | 0 | — | — |
| `fixtures-verify` — vector grid | `jq '.vectors \|= .[0:50]'` **and** `accept` (the key set is unchanged, so the ratchet allows it) → `the vector grid did not run in full` | **1** | restored | 0 |
| `fixtures-verify` — stale-ref vectors | dropped only the 18 vectors whose output pointer ref is absent from `refs`, then `accept` → `no vector has an output pointer whose ref is absent from refs` | **1** | restored | 0 |
| `test` — zero-test guard | *deferred to M1.9; done* — all nine `*_test.dart` moved out of `packages/filefin_core/test/` | **1** | moved back | 0 |
| pre-commit hook — blocks | badly-formatted staged `.dart` | **1**, `BLOCKED by: fmt analyze` | — | — |
| pre-commit hook — bypass is audible | same tree, `git commit --no-verify` | commit **succeeded (0)** *and* post-commit printed `WARNING: commit 2c16415 landed with failing gates` with the full gate log and the amend instruction | — | — |
| pre-commit hook — clean | clean tree | 0, `all gates passed`, post-commit **silent** | — | — |

### Remediation of three adversarial reviews — proof log

Three independent reviews (constitution compliance, gate integrity, server
contract accuracy) found fourteen gate holes and eleven contract inaccuracies.
Every gate changed in response was re-proven in both directions, on the real
scripts, before and after. "Before" is the committed script at `bd34161`, run
against the same input in the same second.

| Finding | What was wrong | Fail input | Before | After |
|---|---|---|---|---|
| **F1 / G3** | `check-constitution.sh` expanded `$files` unquoted at ten sites, so one Dart path containing a space word-split into non-existent paths and `\|\| true` swallowed grep's complaint — **all six** constitutional checks silently disabled at once | `packages/filefin_core/lib/my file.dart` with `throw UnimplementedError()` | RC **0**, `constitution: no new violations`, with `grep: …/my: No such file or directory` hidden by the hook's log capture | RC **1**, names the file |
| F1 / G3 | the same, per check | one space-named fixture per check: `dart:io` import (`core_purity`), `typedef MediaId` (`id_typedefs`), an unconstructed variant (`dead_types`), `'/api/…'` (`undocumented_endpoint`), a `Session` class (`secret_tostring`) | RC 0 for every one | RC **1** for every one |
| **G1** | `just mutants` structurally could not fail in CI: base defaults to `HEAD`, CI checks out a commit, so the diff was always empty | clone at a committed HEAD, clean tree, `CI=true` | RC **0**, `nothing to mutate` | RC **1**, `FILEFIN_MUTANTS_BASE resolves to HEAD and the tree is clean`. With `FILEFIN_MUTANTS_BASE=HEAD^`: RC 0 |
| **G2** | the 50% floor could not be breached by adding untested code — `dart test --coverage` omits never-loaded libraries entirely, so they are absent from the denominator rather than 0% | `lib/tested.dart` (1 line, tested) + `lib/never_imported.dart` (11 public functions, no importer) | RC **0**, `Coverage: 100% (1/1 lines)` | RC **1**, names `never_imported.dart`. Once a test imports it: `Coverage: 16% (2/12 lines)` → floor **fails**, which is the true figure |
| G2 | `run-coverage.sh:29` dropped a whole package from the denominator when it had no `test/` | a 100%-covered package plus a 2-line package with no `test/` | RC **0**, `Coverage: 100% (1/1 lines)` | RC **1**, `packages/untested has no test/ directory` |
| **G4** | `dead_types` required the `final` keyword, so the byte-identical hierarchy written as plain `class X extends Y` was invisible | `sealed class PlaybackDecision` + `class PlayHls extends PlaybackDecision`, never constructed | RC 0 | RC **1**. Constructing `PlayHls()` elsewhere: RC 0 |
| **G5** | `secret_tostring` matched `String toString(` on any line, including prose | `class SessionCookie` whose only mention is `// We deliberately do not write String toString() here.` | RC 0 | RC **1**. A real `@override String toString()`: RC 0 |
| **G6** | `undocumented_endpoint` matched only single-quoted literals *starting* at `/api/`, missing the interpolated form `filefin_api` will actually use — **and** would have false-positived at M1.6, because the doc writes `{id}` and Dart writes `$id` | `'$b/api/undocumented/$id'` | RC 0 (invisible) | RC **1**. `"/api/definitely-not-real"` (double-quoted): RC **1**. `'$b/api/media/$id'` — documented, interpolated: RC **0**, the false positive is gone |
| **G7** | the structural assertions covered ~15 named fields, so gutting a payload and re-running `accept` passed both halves | delete 8 top-level + 5 per-file keys, then `accept` | `accept` RC 0, `verify` RC 0 on a gutted payload | `accept` RC **1**, naming each lost path, manifest unwritten |
| G7 | `PROVENANCE.md` was excluded from `hash_all`, so nothing tied the provenance record to the bytes | — | 17 files hashed, `PROVENANCE.md` and the vectors' record uncovered | 19 files hashed, `PROVENANCE.md` included |
| **G8** | the "M0 only" guards keyed on `dart_sources`, which excludes generated files — so a package whose only Dart was `*.g.dart` turned them all green again | `packages/genonly/pubspec.yaml` + `lib/model.g.dart`, nothing else | `run-tests` RC **0** "(M0 only)", `run-coverage` RC **0** "(M0 only)", `coverage-gate` RC **0** "(M0 only)" | RC **1**, **1**, **1** — `has no *_test.dart files` / `has no test/ directory` / `lcov.info not found` |
| **G9** | `constitution-accept` warned on a rise and wrote the raised baseline anyway, exit 0 | `accept` with one new placeholder | baseline 0 → 1, RC 0 | RC **1**, baseline byte-identical. With `FILEFIN_ACCEPT_NEW_DEBT=1`: RC 0 and the warning. Paying the debt and accepting the **fall**: RC 0, no override needed |
| **G10** | `check-deps.sh` accepted a bare `#` as a rent comment | `#` alone above `very_good_analysis:`; then `###` | RC 0 both | RC **1** both. Real comment restored: RC 0 |
| **G11** | `hooks-status` tested only `-e`/`-x`, so any executable passed | an executable `#!/bin/sh\nexit 0` stub; then a byte-identical *copy* of the real hook | RC 0 both | RC **1** both. `just install-hooks`: RC 0 |
| **G12** | zero mutants was treated as a pass — the comment said "Not a pass" and then did not touch `status` | real scratch package whose only changed lib file is a barrel `export` → `Found 0 mutations` | RC **0**, `mutants: all mutants … were killed` | RC **1**. With `FILEFIN_MUTANTS_ALLOW_ZERO=1`: RC 0. A real mutable change with mutants killed: RC 0 |
| **C2** | `resume_vectors.json` had **0 of 333** vectors with a pointer ref absent from `refs`, so a Dart `View` written as `continueSeconds = pointer?.seconds ?? 0` was wrong and passed everything | replayed that exact wrong `View` over both vector files | fails **0 of 333** old vectors | fails **18 of 601** new vectors |

The C2 replay is the proof that matters for the oracle: the fixture is only
worth having if a plausible wrong implementation fails it. It did not, and now
it does.

### M3.R — remediation of three adversarial reviews of M3

Three independent reviews (app architecture and constitution, the gate changes
M3 made, test genuineness) found two critical defects, a credential leak and a
test harness that could not see wrong behaviour. Every gate changed was
re-proven in both directions on the real scripts; every test changed was proven
genuine by breaking the production code it covers and watching **that** test go
red.

#### The credential leak (A1), before and after

`add_server_page.dart` stored the parsed `Uri` unmodified, so a password typed
into the **address** field was persisted in plain JSON, printed by `toString()`
and sent back as a `Basic` header. Driving the real `AddServerPage` with
`http://sam:hunter2@192.168.1.10:8099`:

```
BEFORE
ON DISK  : {"servers":[{"id":"http://192.168.1.10:8099","name":"192.168.1.10",
            "baseUrl":"http://sam:hunter2@192.168.1.10:8099","lastUser":"","wifiOnly":false}]}
toString : SavedServer(http://192.168.1.10:8099, 192.168.1.10, http://sam:hunter2@192.168.1.10:8099)

AFTER
ON DISK  : {"servers":[{"id":"http://192.168.1.10:8099","name":"192.168.1.10",
            "baseUrl":"http://192.168.1.10:8099","lastUser":""}]}
toString : SavedServer(http://192.168.1.10:8099, 192.168.1.10)
```

**Both purpose-built tests missed it, and both are fixed structurally.**
`settings_store_test.dart`'s §9 assertion searched the file text for the words
`password`, `session` and `certpin`; `sam:hunter2@` contains none of them. It
now decodes the JSON and asserts `Uri.parse(baseUrl).userInfo` is empty, over a
server built through the same normaliser the app uses. The strip itself moved
off the call site and onto the type as `SavedServer.fromTypedUrl`, and the
constructor now asserts an empty `userInfo`, so a second construction path
cannot skip it. **Asserts are off in a release build**, so what a shipped APK
relies on is the single construction path plus the test that reads the bytes on
disk — said out loud rather than implied.

#### The argument-blind fake (C1) — five shippable bugs, each now red

`FakeLibraryApi._answer` returned one field regardless of arguments, so five
bugs passed 181 unit tests **and** the 33-test `just it`. `calls` already
recorded the argument; `size` was added to the `posterBytes` record and the
tests now assert exact strings. Each bug was applied to the real source and the
whole app suite run:

| Bug | Applied at | Test that went red |
|---|---|---|
| grid requests category `999` | `category_grid_page.dart:55` | `grid_test` "the listing is fetched ONCE…" **and** `app_test` "tree to grid to detail" |
| detail requests a hard-coded media id | `media_detail_page.dart:41` | `media_detail_page_test` "the detail asked for is the item that was TAPPED" |
| tile requests another item's poster | `poster_tile.dart:58` | `grid_test` "each tile asks for ITS OWN poster, at the tile size" |
| poster `size` hint dropped | `poster_tile.dart:59` | the same test |
| detail pushed with a **fabricated** item | `app.dart:115` | `app_test` "tree to grid to detail, and back out again" |

The live suite (`just it`) carried the same blindness — backlog row 14 said the
wiring was "proven only against a fake", and it was not proven against the fake
either. Its widget tests now assert the identifiers too.

#### Gates changed, both directions

| Gate | Fail input | Exit | Clean tree | Exit |
|---|---|---|---|---|
| `constitution` / `app_no_raw_http` | a lib file using `Image.network`, `NetworkImage` and `FadeInImage.memoryNetwork` — the exact bypass the check's own rationale names, and which the old pattern (`package:dio/\|package:http/\|HttpClient(\|HttpOverrides\|IOClient`) matched **not at all** | **1**, three violations named | probe removed; `poster_image_provider.dart`'s doc comments explaining the rule are **not** false positives, because comment lines are filtered | 0 |
| `constitution` / `dead_types` | one probe file with all six declaration shapes: plain, generic, **`dart format`-wrapped across two lines**, `implements`, nested bound (`<T extends Map<String, int>>`), and with-mixin | **1**, **all six** named (before: only plain, generic and with-mixin) | probe removed | 0 |
| `constitution` / `dead_types` — no false positive | the intermediate `sealed class PlayNow extends PlaybackDecision`, which cannot be constructed at all | **0** (correct: `sealed` and `abstract` stay out of the modifier set — a permissive `[a-z]+` reported it as debt, measured) | — | — |
| `check-mutants` / `<commands>` refusal | `<commands  >` with `<command group="test">dart test</command>` — XML-legal, and `mutation_test` parses it | **1**, the refusal fires. Old grep on the same comment-stripped file: **MISSED** | rules file restored | 0 |
| `comments` | 26-line probe, 12 `//` lines → 46% | **1** | probe removed | 0 |
| `run-tests` / `declares_flutter` | `sdk: flutter  # a trailing comment` in a `packages/*` pubspec. Old anchor (`…flutter[[:space:]]*$`): **MISSED**, and the run died later with `dart test exited 65` | **1**, `packages/filefin_core … declares an 'sdk: flutter' dependency` | restored | 0 |
| `run-coverage` lcov naming | `apps/mobile` and a future `packages/mobile` both named `mobile.lcov` under `basename` | now `apps-mobile.lcov` / `packages-mobile.lcov`; coverage re-run end to end, **100% (1456/1456)**, 0 uncovered | — | — |

**The comment budget's `MIN_LINES` was lowered from 40 to 20 and the debt was
paid** — the alternative was writing the blind spot into §2. At 40 the gate
skipped three files past the 25% ERROR line (`filefin_api.dart` 32%,
`filefin_core.dart` 28%, `visible_rows.dart` 27%) and one past the warn line
(`main.dart` 18%) while printing "0 error(s), 0 warning(s)", which this file
quoted. All four were paid by moving the rationale into the `///` doc comment of
the declaration it describes, which is where it belonged and which §2 excludes
from both sides of the ratio — no reasoning was deleted. §2 now names the number
and the gate prints every file it still skips that is over a line
(`credentials.dart`, 18% of 16 lines, the only one).

#### The mutation run found four survivors in the new code, and they were not the same kind

`just mutants` over the 10 changed app sources produced **121 mutants, 4
undetected — all four in `settings.dart`**, the file this remediation changed
most. They needed opposite answers, and telling them apart was the work:

**One was a real missing assertion.** The `SavedServer` constructor's assert
message had `user-typed` rewritten to `user+typed` and the whole 194-test suite
stayed green, because the new test asserted only
`throwsA(isA<AssertionError>())`. An assertion message is mutable source that
nothing else reads — the same lesson `error_presentation_test` records about
`RateLimited`'s wording — so the message is now pinned **verbatim**. Mutant
killed; no exclusion.

**Three were `Object.hash` argument permutations**, and they are genuinely
equivalent in the sense §3 requires — the same case as `PosterKey`, decided the
same way rather than by analogy to it. `==` compares all four fields, so equal
servers hash identically under any fixed order and unequal ones differ under
any fixed order: every permutation preserves the whole of `hashCode`'s
contract. The reason no assertion can catch them was **measured**: `id` is an
extension type over String, so the (id, name) swap merely *exchanges* the
hashes of `(ServerId('a'), 'b')` and `(ServerId('b'), 'a')` and any `isNot`
assertion passes either way — which leaves a golden value, and there is none to
pin, because `Object.hash` is seeded per process. Three runs of the same
two-line program printed `'a'.hashCode` as 170824770 every time and
`Object.hash('a', 'b')` as **480010859, 191724426 and 356100938**. Excluded,
with that measurement and a retirement condition in `mutation_rules.xml`.

**The exclusion costs four mutants, not three, and B4's correction applies a
second time.** 23 without the line, 19 with it; a `--dry -v` diff names the
fourth, and it is not a permutation — it is the builtin `&&`-negation rule
matching at line 101 and running past the end of the `==` expression into the
excluded statement, producing text that does not compile. Killed by the
compiler, not by an assertion. Checked rather than assumed, precisely because
the neighbouring note on `PosterKey` had assumed it and been wrong.

After both: **117 mutants over the 10 app sources, 0 undetected.**

#### `FILEFIN_MUTANTS_ALLOW_ZERO=1` was used, and here is which of the two causes it was

`packages/filefin_api`'s only changed lib source is its **barrel** —
`lib/filefin_api.dart`, `library;` plus fifteen `export` lines — because the
comment-budget debt was paid by moving its narration into the library doc
comment. It produced `Found 0 mutations`, which `check-mutants.sh` fails on,
and its error message names two possible causes that look identical at the exit
code: pure declarations, or the `Found N mutations` scrape having silently
stopped working.

**It is the first, and the same run proves it rather than a separate argument.**
`packages/filefin_core`'s barrel changed in exactly the same way and produced
**1 mutation, detected**, and `apps/mobile` produced **121** — both scraped by
the same line of the same script in the same invocation. A scrape pinned at 0
could not have returned 1 and 121. The zero is what a file containing nothing
but `export` declarations legitimately yields.

#### A12 — confirmed as a concurrent-agent artefact, not a gate defect

Review A reported `just fmt-check` failing 3 times in ~35 invocations, always on
`category_grid_page.dart`, never reproducible, plus one ` M app.dart` with an
empty diff and an md5 matching HEAD. Confirmed rather than assumed: a sibling
agent's `mutate.py` lives in this session's shared scratchpad, its `REPO`
constant points at **this working copy**, and its backup directory contains
`apps__mobile__lib__src__browse__category_grid_page.dart` stamped 16:25 — the
same file, inside the reported window. It edits a source, runs a command, and
restores in a `finally`; anything reading the tree in that window sees a
mutated or freshly-rewritten file. Recorded in CLAUDE.md beside the existing
`mutation_test` warning.

**And then it happened again, to this remediation, with one process.** A
`just check` cancelled at a ten-minute timeout left the mutant `mutation_test`
was holding on disk: `visible_rows.dart`'s `if (isExpanded)` came back as
`if (!(isExpanded))`. The next run did not report a broken branch — it reported
`unnecessary_parenthesis`, an **info**-severity lint, and only `--fatal-infos`
turned that into a non-zero exit. Every changed lib file was then diffed line by
line against HEAD before continuing; the mutant was the only stray. Both halves
of the hazard — a concurrent writer and an interrupted run — are now in
CLAUDE.md.

#### Everything else, by finding

| Finding | What was done |
|---|---|
| **A2** | `onSignIn` was declared, documented, plumbed to `AsyncView` and never given a value, so a `SessionExpired` on the grid or the detail page rendered "Please sign in again" with no button and no retry. Wired in `app.dart`; the callback `popUntil`s the root. Proven: removing it from the grid, from the detail page, or removing the `popUntil`, each turns a named test red |
| **A3** | `AppDependencies.secrets` deleted — written by `main()`, read by nothing; its two "consumers" were `expect(deps.secrets, isNotNull)` on a non-nullable final field and a test copying it |
| **A4** | `SavedServer.wifiOnly` deleted. §1 is unconditional, and the tree already ruled this way on `PlaybackSettings.progressIntervalSecs`. M4 adding a reader is what makes re-adding it free: §13 means no migration, no lenient decoder, and the field arrives with the code that reads it. Keeping it would have meant M4 inheriting a default nobody chose |
| **A5** | Two messages named the one cause they cannot carry — "a server restart signs everyone out" is exactly what F3 renews and replays without a message. `SessionExpired` and the signed-out launch screen now name `session.dart:137`/`:223`'s real causes: no stored session, no password to renew with |
| **A6** | `SettingsStore.write` failures were unhandled async errors — the button re-enabled, no callback fired, nothing appeared, and `read()` swallowing every failure made an unwritable directory completely invisible. Both screens now catch `FileSystemException` and print the OS message. Proven on both: removing either catch turns its test red |
| **A7** | See the comment-budget paragraph above |
| **A8** | `_signInRoute`'s `pops` parameter could only ever be 1 — replaced with one `Navigator.pop()` |
| **A9** | Signing out of the second saved server offered the **first** one, with no picker to correct it. `_server` is kept across sign-out and is what the button offers |
| **A10 / A11** | `meta` pinned exactly (1.18.0) in all three pubspecs, with the reason beside it; `pubspec.lock` unchanged by the pin. The stale "deliberately not here yet" comment above the block declaring `path_provider` and both platform interfaces was corrected. `docs/architecture.md`'s "Why exact" table gained all four of M3's packages |
| **A13** | `obtainKey names the API's server, not a literal` used `ServerId('home')` in both the fake and the expectation, so the literal it rules out passed — now a distinct id. The empty-body poster test asserted only `isA<StateError>()`, which the harness's own `StateError('nothing happened')` sentinel also satisfies — now `contains('no poster')` as well. The userInfo-redaction sweep was a hand-kept list of 11 of 14 variants; it is now one table of all 15 rows shared by three sweeps |
| **B4** | The exclusion's third suppressed mutant is **not** "a third permutation already being killed" — a `--dry -v` diff shows it is the builtin `&&`-negation rule running into the excluded statement and producing text that does not compile. Corrected, along with the consequence: `other.size == size` now has no mutant at all, so field order rests on the two constructor swaps |
| **B6** | `declares_flutter` fixed (above). The depth-3 `packages/<group>/<pkg>/pubspec.yaml` blind spot is left as-is and stated: pre-existing, and backstopped by coverage's missing-record cross-check |
| **C2** | The first 401-discipline test drove a fake that **succeeds** — no 401, no retry, no interceptor. Adding `needsSignIn: statusCode == 401` to the `ServerFailure` arm left all 181 tests green. Replaced by a table over all 15 rows with an exhaustive `expectedNeedsSignIn` switch; the same edit now goes red |
| **C3** | See the NF2 section above |
| **C4** | Live test 7 was labelled "The 404 branch, end to end" while setting `posterResult = null` by hand; the real 404 is `showPoster`, fetched from the binary in `setUpAll`. Relabelled to what it proves. The live widget tests gained identifier assertions |
| **C5** | `media_detail_page_test`'s empty-id test hand-injected the error, so a silent repair — the exact G5 failure — passed. It now asserts `api.calls == ['mediaDetail()']`; a page that short-circuits an empty id goes red |
| minor | `.kotlin/` added to `.gitignore` (a transient `*.salive` surfaced as `??` mid-session) |

#### Left undone, deliberately

- **`check_secret_tostring` still selects classes by NAME**
  (`Credential|Password|Secret|Session|Token`), which is why `SavedServer`
  passed every gate while persisting a password. A second arm keyed on what a
  type *carries* was considered and not written: "any persisted type holding a
  `Uri`" is a heuristic, and the leak it would have caught is now closed
  structurally by the constructor assert plus a test that reads the bytes on
  disk. Recorded here rather than left implied.
- **The depth-3 package blind spot** in `run-tests.sh` / `run-coverage.sh`
  (`-mindepth 2 -maxdepth 2`), as above.
- **`credentials.dart` at 18% of 16 counted lines** remains under §2's size
  exemption. It is now printed on every run rather than skipped in silence.

### Gate proofs deliberately deferred

Stated here rather than left implied by silence.

- **`codegen-check`** — **done at M1.4**, and the proof found a hole in the
  gate. See "codegen-check could not see a hand-edit that was staged" above.
- **`coverage-check` on real code** — **done at M1.9.** Real figure
  100% (327/327); pushed to 44% and the floor failed. Table above.
- **`mutants` on real code** — **done at M1.9**, and it found the gate was not
  asking the boundary question at all. See the section above.
- **`test` zero-test guard** — **done at M1.9.** Moving all nine `*_test.dart`
  out of `packages/filefin_core/test/` gave exit **1**; putting them back gave
  0. `dart test` alone would not have gone vacuous (it exits 79 on an empty
  `test/` and 65 with none), but `flutter test` **does** exit 0 and joins this
  script at M3 — that is what the guard is for.

**Nothing is deferred out of M1.** Every gate in `just check` now has a
both-directions proof on real code.

---

## Debt this milestone knowingly accepts

Said out loud, per CLAUDE.md. Silence would read as "there was none".

### Ten of fourteen gates measure zero Dart today

The honest number, said plainly. `just check` runs fourteen gates. **Four of
them measure something now** — `toolchain-check` (the SDK version),
`hooks-status` (the installed hooks), `deps` (the root pubspec), and
`fixtures-verify` (19 files, 259 captured key paths, 20 structural assertions).
The other ten degenerate over an empty Dart file list: `fmt-check`, `analyze`,
`file-size`, `comments`, `constitution` and `mutants` run their real logic over
nothing, and `test`, `coverage-check`, `dupes` and `codegen-check` take an
explicit "(M0 only)" branch.

The distinction between those two groups is real and worth keeping: an explicit
branch is code that must be **deleted**, and until it is, it is a line that says
"exit 0 without checking". A gate running its real logic over zero files needs
no deletion. But both measure nothing, and reporting only the four explicit
branches would have understated it.

Each of the three M0-only branches (`test`, `coverage-check`, `dupes`) is
guarded on `no_dart_packages` — no `pubspec.yaml` under `packages/` or `apps/`.
They were previously guarded on `dart_sources` being empty, which did **not**
hold: `dart_sources` excludes `*.g.dart`, so a package whose only Dart was
generated made all three reachable again. That is finding G8, and the claim in
the previous version of this file — "the first `.dart` file makes them
unreachable" — was false as written. It is now true of the first *package*.
`codegen-check`'s fourth branch is guarded differently, by "generated files
committed but nothing can regenerate them", and retires at M1.4.

This is genuine vacuity for the duration of M0 and it is the price of M0's exit
criterion being `just check exits 0` over an empty tree. Nine of the ten retire
at M1.1; `codegen-check`'s at M1.4.

### Three environment overrides, and the limits they do not cover

Each of these refuses by default and exists because the alternative was a gate
that could not fail. They are levers, and a lever left lying around gets pulled,
so they are listed here as debt rather than as features.

| Override | Relaxes | Required alongside |
|---|---|---|
| `FILEFIN_ACCEPT_NEW_DEBT=1` | `constitution-accept` writing a raised baseline | a line in this section saying which violation and why |
| `FILEFIN_ACCEPT_FIXTURE_KEY_LOSS=1` | `fixtures-accept` recording a captured JSON key disappearing | the commit message naming the upstream change (§8: the doc and the model move with it) |
| `FILEFIN_MUTANTS_ALLOW_ZERO=1` | `mutants` failing on a diff that produced no mutants | the commit message saying which cause — a declaration-only diff, or exclusions swallowing a real change |

`FILEFIN_MUTANTS_BASE` is not in this list: it selects a diff base rather than
relaxing a threshold, and CI now sets it. Nothing else under `tool/` reads the
environment — `FILEFIN_JSCPD_VERSION` and `FILEFIN_DUPES_THRESHOLD` were
removed, since nothing set them and an env var that raises the duplication
threshold contradicts the "ratchets down, never up" policy it was sitting next
to (finding F4).

Two gate limits are known and not closed:

- **`undocumented_endpoint` does not reconstruct a path split across adjacent
  concatenated string literals** (`'/api/' 'media'`). It matches `/api/` inside
  any single- or double-quoted literal, interpolated or not, which covers every
  form `filefin_api` will actually write. M1.6's single `ApiPaths` class is the
  structural answer; a grep gate is not going to parse Dart.
- **`dead_types` deliberately ignores `sealed` and `abstract` variant
  modifiers.** Neither can be constructed, so "never constructed outside its own
  file" is their definition rather than a violation, and flagging them would
  false-positive on every intermediate node of a nested hierarchy. The review
  suggested including them; this is a considered deviation, not an omission.
  `final`, `base`, `interface` and bare `class` are all covered.

### `build_runner` was removed rather than justified — and has now returned

Finding F3: `tool/dep-allowlist.txt` claimed it was "invoked by `just codegen` /
`just codegen-check`", but `check-codegen.sh` scans `packages/*` and `apps/*`
for a `build_runner:` declaration, found none — it was declared in the *root*
pubspec — and short-circuited. `just codegen` had no builders and no caller. So
it was a dependency no milestone needed yet, which is §1.

It was gone from `pubspec.yaml`, from the allowlist, and `just codegen` with
it. All three returned at **M1.4** with the first `@freezed` models, alongside
`freezed` and `json_serializable`, each with a rent comment and an allowlist
entry naming the recipe that consumes it. `codegen-check`'s anti-vacuity guard
is unaffected and still proven: committed generated files with no declared
builder fail.

`build_runner` is the one codegen package NOT pinned exactly, against the plan's
instruction. It cannot be: freezed 3.2.5 caps `analyzer` below 11 and
build_runner 2.16 requires 13, so the resolver has to pick the newest pair that
agrees (2.15.1 today). The committed `pubspec.lock` is what makes the outcome
reproducible, and the rent comment says so.

The SDK floor moved **3.6 → 3.8** at the same time, in the root pubspec, in
`filefin_core`'s, and in `tool/check-toolchain.sh`. json_serializable 6.14
refuses to generate for a package below language version 3.8 — it *warns* and
emits older-shaped output rather than failing, which is the worst of both. The
floor is set by the strictest constraint in the tree, not the loosest.

### M1 debt, said out loud

- **`ProgressEvent` is not modelled**, against the plan's M1.7 list. `event` is
  accepted by the handler and ignored by the engine — nothing in `state.Apply`
  reads it — so a field no code reads is a dead branch (§5). It arrives at M4
  with the progress reporter that sends it, by the same reasoning that deferred
  `progressIntervalSecs` (A9). `ProgressReport` carries `file`, `position` and
  `duration` only.
- **`WatchState.fromDetail` cannot distinguish a real `(0, 0s)` pointer from no
  pointer**, because the detail payload carries the derived view rather than the
  stored pointer and the server reports both as `0`/`0`. It reads `0`/`0` as
  absent, which is the reading that agrees with `Apply` for the stale-pointer
  case. **This entry used to end "the item is `watched` by then and has left
  every `continue` row, so nothing reads the difference." That was false, and
  the code comment saying it has been replaced too.** The divergence does not
  close itself. Live v0.20.3 transcript, single-file film: after
  `{position: 95, duration: 100}` the client holds `95` and the server holds
  `0`; after a rewind to `{position: 50}` the server moves to `50` and the
  client **still holds 95**, because the pointer only ever moves forward and
  nothing has exceeded it. Once the user rewinds, the optimistic value is simply
  wrong, and `watched` does not hide it — `POST .../watched {"watched":false}`
  keeps the pointer and puts the item back in `continue` carrying the stale
  offset. **Known limitation for M4:** the progress reporter must re-read the
  detail after a report that crosses 90% of a single-file item rather than trust
  the prediction. The chosen reading is still the right one — it was settled by
  enumerating 90 inputs against the real Go engine, and the two readings differ
  on only 4 of them, all of this same shape — but it is a tie-break, not a
  derivation.
- **`WatchState.fromDetail` normalises a rating the server would refuse to
  write.** The server validates `0..10` on write (`media.go:425`) and does
  **not** clamp on read: verified live by editing `meta.json` to `rating: 99` —
  `POST .../rating {"rating":99}` answered `400` while `GET .../media/<id>`
  still served `99`. Copied through unchecked, that built a `WatchState` whose
  own `setRating(state, rating: state.rating)` threw `RangeError`. The answer
  chosen: the wire model keeps the raw value (§8 tolerance belongs at the wire
  boundary), and `fromDetail` reads anything outside `0..10` as **0, unrated** —
  upstream's own word for "no rating" (`state/state.go:29`). The invariant is
  now stateable and tested: **every `WatchState` this package constructs is one
  every mutator accepts.** The debt is that it is a normalisation, so a corrupt
  `99` is shown as unrated rather than surfaced; clamping to `10` was rejected
  because showing full marks for corrupt data is a worse lie than showing none.
- **`ApiPaths` rejects a path parameter instead of escaping it, and `MediaId('')`
  is reachable today.** `''`, `'.'` and `'..'` are not escapable — `Uri` deletes
  dot segments unconditionally, including from `%2E%2E` — so `_seg` throws
  `ArgumentError`. `MediaId('')` is the models' own declared default, which means
  a payload with a missing or null `id` now throws at URL construction where it
  previously produced a request against a **different route** that the SPA
  catch-all answered `200 text/html`. That is the intended trade: a loud failure
  naming the value beats a silent one that arrives later as a JSON decode error.
  `filefin_api` (M2) is the first caller that will have to decide what to do with
  the throw.
- **`ApiPaths` is no longer exported from the barrel.** `grep` found no consumer
  outside `urls.dart`, and the barrel's own doc sets the criterion: a symbol not
  exported there has no consumer outside the library and is dead by §5. It is
  `export 'src/urls.dart' hide ApiPaths;` now, and `urls_test.dart` imports
  `src/urls.dart` directly to pin the route literals — which also makes the §8
  `undocumented_endpoint` gate's dependency on their exact spelling visible in a
  test. Unhide it the day `filefin_api` genuinely needs a bare path.
- **A path parameter is percent-encoded by `ApiPaths` and decoded again by
  `_resolve`.** Two encodings meeting in the middle is more machinery than a
  `/`-free id needs, and it exists for `hlsSegment`, whose segment name comes
  from a server-supplied playlist. If `ApiPaths` ever returns segment lists
  instead of strings the round trip goes away — but so does
  `undocumented_endpoint`'s ability to see the routes, which is why it does not.
- **Two mutation exclusions were added.** Both are demonstrably equivalent
  mutants (above), both are excluded by exact text, and both carry a retirement
  condition. An exclusion is still a piece of code the gate has stopped asking
  about.
- **`FILEFIN_MUTANTS_ALLOW_ZERO=1` was used on two commits** — the package
  skeleton and the wire models. Both diffs are declaration-only: export
  directives, extension types, identity converters, annotations and field
  defaults, with no operator, literal or conditional for a mutant to alter.
  Verified by grep before overriding, and named in both commit messages.

  **Said out loud, because the override hides it: the mutation gate gives ZERO
  assurance for all nine wire models and for `json_converters.dart`.** At HEAD
  the per-file mutant counts are 0 for `lib/filefin_core.dart`'s siblings
  `ids.dart`, `json_converters.dart`, `search_field.dart` and every one of
  `models/*.dart` — 0 mutations each, on every run, including the 174-mutation
  run above. Nothing in them is an operator, a literal or a conditional, so
  there is nothing to mutate; §3's second instrument simply does not reach them.
  **Coverage is the only check on that code**, backed by the captured-payload
  round-trips (§8) and `model_contract.dart`'s unknown-field injection. That is
  a real gap, not a formality: it is where a decoder that silently drops a field
  would live.
- **A type change in a payload fails the whole payload, and that is within §8 as
  written.** Measured by the M1.10 review, not re-measured here: 208 mutations
  of the fixture values across all nine models, of which **124 throw
  `_TypeError`** on a type change (`bool` → `1`, `int` → `"3"`, `List` → scalar,
  `[null]`). §8 mandates unknown-field tolerance
  and "nullable with a default", and **null-tolerance is complete** — all 84 null
  substitutions decode to the documented default at every nesting level,
  including inside list elements. So this is not a §8 violation. It is recorded
  because the blast radius is worth knowing before M4 renders a list: a single
  bad element (`files: [null]` with a non-nullable element type) fails the whole
  response, and `json_converters.dart`'s comment — "a decoder that throws on an
  unexpected value turns one odd item into a blank screen" — slightly over-claims
  by invoking §8 for a tolerance the generated decoders do not provide above the
  converter layer.
- **`--delete-conflicting-outputs` was dropped from `check-codegen.sh`** in the
  same edit that added the cache deletion, and went unrecorded until a review
  noticed. Recorded now, with the reason: the flag lets the builder **delete** a
  file it did not write in order to make its own build succeed, which is an
  auto-fix inside a gate whose job is to notice a difference. Re-verified after
  the cache deletion landed — a full rebuild over the committed output writes all
  20 files with no conflict — so it bought nothing and could only have hidden
  something. Not a loosening; it was simply undocumented, which is its own
  finding.
- **The mutation gate cannot distinguish a survivor from an interrupted run.** A
  run killed by the 300s command timeout reported `1/62 undetected`, exit 1,
  while two complete runs of the same tree reported 62/62 and 149/149. Failing
  safe when interrupted is right, but a reader who takes "undetected" at face
  value goes hunting for a missing assertion that does not exist.
  `check-mutants.sh` now prints a NOTE saying so alongside the failure, and the
  tool's own `Timeouts: N` line is the thing to read. Not fixed at the source —
  that needs an upstream change.

### Deferred by decision, not oversight

| Item | Decision | Where |
|---|---|---|
| **A2** — `ServerId` | **Closed at M2.1.** `filefin_api` is the consumer: it keys the per-server cookie jar, secret namespace and certificate pin. | M2.1 |
| **A4** — `just it` | **Closed at M2.7.** Four suites, 19 tests, 4 seconds, against the real binary; `check-all: check it`, local-only. All four refusal paths proven. | M2.7 |
| **A5** — `mutants` / `coverage-check` on real code | Created and proven in M0 (synthetically for coverage, against a real scratch package for mutants); re-proven against `filefin_core` at **M1.9**. | above |
| **A9** — `progressIntervalSecs` | `PlaybackSettings` is `{wifiOnly, meteredWarnBytes}` only. The interval arrives at **M4** with the progress reporter; a settings field nobody reads is a dead branch (§5). | M4 |
| **`SavedServer.wifiOnly`** | Removed at **M3.R** on the same reasoning, after the review found it read by nothing. SPEC §7 still lists it and M4 will add a reader — together with `allowUnverifiedPlayback` — but §13 means our own format changes freely before release, so the field arrives with the code that reads it and no migration is owed. | M4 |
| **A10** — `RefuseReason` | `{offline, wifiOnlyOnMetered}` only. The 415 "transcoding disabled" message is knowable only *after* a request, so it is an M5 `filefin_api` concern, not a `decide()` branch. | M5 |
| **glados** | Replaced by **kiri_check** 1.3.1. Every published glados version declares `sdk: >=2.12.0 <3.0.0` and cannot resolve on any Dart 3 SDK. Not a workaround — the package has never been updated for Dart 3. | M1.7 |
| **A11** — `Tag` model | `GET /api/tags` is documented and captured, but **no model in M1** — no F-requirement consumes the vocabulary yet. | when a screen needs it |

### Fixture coverage gaps

Listed in full in `test/fixtures/PROVENANCE.md`. Summary: no poster bytes (the
seeded items have no poster and no model decodes an image), no HLS segment
bytes (multi-megabyte binary; R1's spike already confirmed `200 video/mp2t`),
and only one user — who **is** an admin — so neither per-user state isolation
nor a non-admin `authResult` is exercised. The `Retry-After` gap is closed:
verified live as `Retry-After: 900` on the sixth consecutive bad login,
matching `int(retry.Seconds()) + 1` at `auth.go:149`. None of these is claimed by any M1 model, so §8 is intact.
**"they land at M2/M5" was restated at M5**: the file route's `415 transcoding
disabled` landed, captured against a real server whose setting
`capture_fixtures.sh` switches off and restores; HLS segment bytes deliberately
did not, and `test/fixtures/PROVENANCE.md` says why rather than leaving a
milestone name that has gone past.

### CI does not capture fixtures

`.github/workflows/ci.yml` has **no** fixture-capture job. Capturing needs a
real `filefin` binary built from upstream (Go plus a Node web build) and a
seeded data dir. A job that skipped when the binary was absent would report
success while checking nothing. What CI *does* enforce, inside `just check`, is
`fixtures-verify`: the committed fixtures must match their SHA-256 manifest and
still satisfy every structural assertion, so a hand-edited fixture fails CI
without CI ever talking to a server.

### No negative-compilation test for the ID types

Dart has no framework for asserting that a program **fails** to compile. So
nothing will prove that passing a `CategoryId` where a `MediaId` is expected is
rejected; the guarantee rests on the language (`extension type … implements
Object`) plus the `id_typedefs` gate catching a `typedef` regression. Recorded
at M1.2 as well.

---

## Deviations from the plan, and why

- **`fixtures-verify` and `dupes` were added to `just check`.** The plan's
  `check` list named neither. `fixtures-verify` reads only committed files, so
  it costs nothing in CI and turns the fixtures from "files we hope nobody
  edits" into a gate. `dupes` exists because the jscpd evaluation CLAUDE.md
  demanded came back positive — it has a Dart tokenizer and was seen to fail —
  and CLAUDE.md is explicit that a gate either runs in `just check` or does not
  exist.
- **`pubspec.lock` was un-ignored.** It was in `.gitignore` with a note saying
  "re-evaluate at M0". Re-evaluated: `codegen-check` and `mutants` must produce
  the same bytes on every machine, and they cannot if resolved versions drift.
  Committed.
- **`docs/server-api.md` records a discrepancy the plan did not anticipate.**
  SPEC.md §3.5 says an out-of-range file index "leaves state entirely
  unchanged". That is true of the **engine** (`state/engine.go:57-59`), but the
  **HTTP handler** rejects it with `400 bad file index` (`server/media.go:531`)
  and never reaches the engine. Both readings are right at their own layer;
  `filefin_core` mirrors the engine, `filefin_api` will own the 400.
- **M0.13b needed no Go toolchain download.** The plan warned that upstream's
  `go.mod` wants Go 1.26.4 while the local toolchain is 1.23, and that
  `GOTOOLCHAIN=auto` would need network. In the event, the capture ran against
  the existing clone with the local toolchain and produced the vectors (333 at
  first capture, 601 after the stale-ref grid was added). The
  script still sets `GOTOOLCHAIN=auto` and still fails loudly rather than
  degrading, since a fabricated oracle is worse than no oracle.
- **The `meta.json` enrichment had to declare `version: 2`.** The first attempt
  used `version: 1`, which trips `upgradeMeta` (`importer.go:86`): it reads the
  legacy `tags` key as genres and nils `Tags`. That produced a fixture with an
  empty `tags` array — one that would have let a decoder silently dropping tags
  round-trip perfectly. `check-fixtures.sh` now asserts against it by name.

---

## Scout-rule notes (things seen, not fixed)

- `tool/testserver/capture_fixtures.sh` builds the fixture list twice: once in
  the capture body and once in the emptiness guard. A third fixture added to
  one and not the other would be captured but unguarded. Not worth a redesign
  now; `check-fixtures.sh` is the real backstop, and with `KEYS.txt` it is now
  genuinely exhaustive rather than merely thorough.
- `SPEC.md` §3.5 cited `docs/playback-state.md`, a file that has never existed.
  Repointed at `docs/server-api.md`'s "Resume semantics" section, which is where
  the rules actually live. Found while fixing F6; a citation to a missing file
  is the same class of defect as a citation to the wrong line.
- **`SPEC.md` §3.5's last-file rule was over-general and is now corrected.** It
  said crossing 90% of the last file "sets the permanent `watched` flag **and
  leaves the pointer index where it is** — the seconds do not advance on that
  same report", full stop. That holds only when the pointer **already resolves
  to** the last file, because the equal-index branch additionally requires
  `!crossed` (`state/engine.go:81`). When the pointer is behind or absent, the
  `targetIdx > curIdx` arm runs (`:79-80`) and writes `{last file,
  round(position)}` — index *and* seconds move. Verified live: a fresh item
  reporting 95 of 100 comes back with `seconds: 95`. The Dart reproduced both
  halves all along and `docs/server-api.md` stated it correctly; only SPEC.md
  was wrong, which is the orchestrator's own error rather than the code's.
- **`engine.dart`'s non-finite comment now says what Go actually produces.** It
  said Dart's `.toInt()` throws "where Go's `int()` does not" without naming the
  result. Measured on darwin/arm64 with go1.23: `+Inf` → `9223372036854775807`,
  `NaN` → `0`, `-Inf` → `0` through the clamp. So the client's `0` for `NaN` and
  `-Inf` agrees with Go by accident of the platform and `+Infinity` is the sole
  deliberate difference — and none of it is reachable over the wire, because
  Go's `encoding/json` refuses to marshal a non-finite float.
- **`docs/server-api.md`'s "There is no 404 and no 405 on the API surface" read
  as absolute** but meant "no *routing* 404"; the same document records real
  404s for an unknown id at four places. Reworded there and in `SPEC.md` F1,
  which carried the same sentence.
- The review reported `SPEC.md:102` citing `server.go:456` for the `authResult`
  *shape*. Both readings are half right: the struct is `server.go:447-453` and
  `:456` is `authResultOf`, which builds it. The sentence now names both, since
  a reader following the citation wants the struct.
