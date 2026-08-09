# FileFin Client

A mobile client for [FileFin](https://github.com/xuedi/FileFin), a
filesystem-first self-hosted media server. Flutter + Dart, playback by
`media_kit` (libmpv) on Android and iOS.

The server is a third-party project we do not control. Its HTTP contract is an
external boundary — observed, documented, and versioned, never assumed.

- Full technical specification → `SPEC.md`
- Current state, milestone by milestone → `STATE.md`
- Server API contract, cited to upstream source → `docs/server-api.md`
- Architecture, layout, design decisions → `docs/architecture.md`
- Risks not yet retired, with their spikes → `docs/risks.md`

## Constitutional stipulations

Mandatory. Violating any of them is a review finding. Each names the command
that enforces it — **a rule with no check is a rule that gets ignored**.

**§1 — You Aren't Gonna Need It.** Do not build anything until the milestone
that needs it. No speculative classes, no stub files, no unused dependencies,
no settings nobody reads. Every line must be reachable from a test or a
running path. Delete dead code immediately — git remembers.
*Enforced by: `just constitution` (placeholders), `just analyze`.*

**§2 — Comment budget.** Explanatory `//` comments below 15% of source lines;
above 25% is an error. Numerator is `//` only — not `///` doc comments.
Denominator is non-blank lines, excluding generated files (`*.g.dart`,
`*.freezed.dart`). Comments that pay rent: why a non-obvious choice was made,
what invariant holds, which server quirk a workaround exists for. Comments
that don't: what the code already says.

**One size exemption, and it is named here because an exemption a rule does
not mention is a blind spot rather than a decision.** A file under **20**
counted lines is not measured: below twenty, one comment moves the ratio by
five points or more, so 15% and 25% cannot be stated to the precision they are
written at. The number was 40 through M3 and was in the script only; at 40 it
hid three files past the ERROR line — `filefin_api.dart` 32%, `filefin_core.dart`
28%, `visible_rows.dart` 27% — while `just comments` printed "0 error(s), 0
warning(s)" and STATE.md quoted that. All three were paid at M3.R by moving the
rationale into the `///` doc comment of the declaration it describes. Every
file still exempt **and over a line** is printed by the gate on every run, so
the exemption is visible rather than inferred.

**This budget governs Dart, and `just comments` measures Dart only.** The shell
under `tool/` is deliberately exempt, and the exemption is a decision rather
than an oversight: by §2's own arithmetic 12 of the 21 M0 shell scripts are past
the 25% error line and all 21 are past the warn line. Every one of those
comments is the kind §2 calls rent-paying — *why* process substitution instead
of a pipe, *why* each constitutional check ends in `|| true`, *why* the seed's
`meta.json` must be `version: 2`, *why* a guard keys on `pubspec.yaml` rather
than on the source list. A gate script is read once a year, by someone deciding
whether it can be weakened; the prose explaining why it cannot is the most
valuable text in the file. Do not apply §2 literally to `tool/` and delete it.
*Enforced by: `just comments` (Dart under `packages/*/lib`, `apps/*/lib`).*

**§3 — Tests first.** TDD: red → green → refactor. Coverage floor 50%, target
80%. Every bug fix adds a regression test. `filefin_core` tests are
deterministic and take injected time — no `DateTime.now()` in the core.

Coverage counts lines that ran; it cannot tell a real assertion from a
tautology. So changed code must also survive mutation: `mutation_test` runs
diff-scoped, and a surviving mutant blocks the commit. Exclude one only when
it is genuinely equivalent, with the reason and its retirement condition in
`mutation_rules.xml`.
*Enforced by: `just test`, `just coverage-check`, `just mutants`.*

**§4 — Every dependency pays rent.** A package in `pubspec.yaml` has at least
one `import` referencing it, and a one-line comment naming what needs it.

**Every dependency is pinned exactly on introduction, with its reason beside
it** — not only pre-1.0 ones. Two gates require it: `just mutants` runs the
whole suite once per mutant, and `just codegen-check` compares generated output
byte-for-byte, so both are non-deterministic across machines the moment a
constraint can resolve two ways. A caret range is also how a patch release
silently changes behaviour the tests were written against — dio's interceptor
ordering and `fetch` semantics are the live example. Loosen a pin only when
something concrete needs it, and record what.

Tooling packages are consumed by configuration or by a gate recipe and are
never imported by anything (`very_good_analysis`, `mutation_test`, `coverage`
today; `build_runner`, `freezed`, `json_serializable` from M1.4). For those the
import requirement is satisfied instead by an entry in `tool/dep-allowlist.txt`
naming what consumes it. The rent comment is required either way — the allowlist
waives the import, never the justification.

"Consumed by a gate recipe" means *today*, not eventually. A tooling package
whose consumer does not exist yet is a §1 violation wearing §4's clothes, and an
allowlist entry naming a consumer that has not been written is not a reason, it
is a promise. That is why `build_runner` is not in the pubspec at M0: its
allowlist entry claimed `just codegen-check` invoked it, and `codegen-check`
short-circuited before ever reaching it.
*Enforced by: `just deps` (unused/undeclared scan), review of the pubspec diff.*

**§5 — No dead branches.** Error variants must be constructed somewhere.
Settings fields must be read somewhere. Public members need a consumer outside
their own library. A `sealed class` variant nobody constructs is dead.
*Enforced by: `just constitution` (dead_types), `just analyze`.*

**§6 — Core purity.** `filefin_core` is I/O-free, Flutter-free, and
deterministic. No `package:flutter`, no `dart:io`, no `dart:ui`, no HTTP, no
clock, no ambient randomness. It holds types, URL construction, the
resume/progress rules, and the playback decision. Time arrives as an argument.
Anything that touches the network lives in `filefin_api`; anything that draws
lives in `apps/mobile`.
*Enforced by: `just constitution` (core_purity) — scans imports and pubspec.*

**§7 — Extension types for IDs.** `MediaId`, `CategoryId`, `FileIndex`,
`SubtitleIndex`, `ServerId` are Dart `extension type`s over their primitive,
never `typedef`s. They wrap **different** primitives — `MediaId` is a 12-char
hex string (`import.go:354`), `CategoryId` is an `int64`
(`library.go:29`) — so the compiler cannot catch a mix-up for you once either
decays to its representation, and the server answers a wrong one with a 404
rather than an explanation.

Declare them `implements Object`, never `implements String`/`int`: the latter
forwards assignability to the primitive and defeats the entire rule.
*Enforced by: `just constitution` (id_typedefs).*

**§8 — The server contract is observed, not assumed.** Every endpoint we call
is documented in `docs/server-api.md` with the upstream file and line that
proves its shape, pinned to the FileFin version we verified against. Models
decode **tolerantly**: unknown JSON fields are ignored, every field we do not
strictly need is nullable with a default. A server upgrade that adds a field
must not break us. When upstream changes, the fixture and the doc change
together.

Every model round-trips a **captured real payload** committed under
`test/fixtures/`. A hand-written JSON literal that agrees with our own class
proves only that we can spell our own field names.
*Enforced by: `just constitution` (undocumented_endpoint), `just test`.*

**§9 — Never log or persist a credential.** Passwords exist only in transit
and in the platform secure store (Keychain / Android Keystore via
`flutter_secure_storage`). Never in `SharedPreferences`, never in a settings
file, never in a log line, never in a `toString()`. Secret-bearing types
override `toString()` to print `<redacted>` and are never `@freezed` with a
default `toString`.
*Enforced by: `just constitution` (secret_tostring), review.*

**§10 — Generated code is committed and verified fresh.** `*.g.dart` and
`*.freezed.dart` are committed so a clean checkout builds without codegen. A
build that produces a diff means someone edited generated output or forgot to
regenerate.
*Enforced by: `just codegen-check` (runs build_runner, then fails on any diff).*

**§11 — Scout's rule.** Leave every file you touch better than you found it.

Bounded, so it stays compatible with §1: improve files you already have open
for the task. The requested scope remains the deliverable — this is not a
licence to refactor the tree. A scout fix is small and obviously safe (a
clearer name, a missing test, deleting dead code, tightening a type). Anything
needing its own design discussion is not a scout fix; record it in `STATE.md`.

Keep scout fixes in their own commit when they are more than trivial, so the
feature diff stays readable, and never let one change behaviour silently.

**§12 — Commit only a green tree.** Run `just check` before committing and
commit only when it exits 0. A commit is the unit later work builds on; a red
one makes every subsequent bisect and review start from a broken baseline.

`git commit --no-verify` is not a normal tool. It exists for genuine
emergencies — a hook that is itself broken, or a commit that must land to
unblock a rollback. Reaching for it to get past a failing gate is "do not
weaken a gate to make it pass" wearing a different hat.
*Enforced by: the pre-commit hook (blocks) and the post-commit hook (warns
loudly on a bypassed commit, naming the SHA). Install with `just install-hooks`.*

**§13 — No backward compatibility before release.** Nothing has shipped, so
there are no old installs and no stored state worth preserving. When **our
own** format changes — settings, cache schema, secure-store key layout —
change it: no migration, no lenient decoder, no fallback branch reading what
an earlier build wrote.

This governs our formats only. §8 governs the server's, and there we are the
ones who must be tolerant. Retire this rule at the first release.
*Enforced by: review.*

**The ratchet is what makes this real.** Debt is counted, and the counts may
only ever fall:

- `just constitution` holds a per-rule violation baseline in
  `tool/constitution-baseline.txt`. A count above baseline is an error. A
  count below prints a notice — run `just constitution-accept` to lock the
  improvement in so it can never regress. `constitution-accept` **refuses** to
  write a raised baseline: a ratchet with a one-command release valve is not a
  ratchet.
- Three environment overrides exist, and they are the complete list. Each
  refuses by default, names itself in its own error message, and requires the
  reason to be written down where a reviewer sees it —
  `FILEFIN_ACCEPT_NEW_DEBT` (raise a constitution baseline; say so in
  STATE.md), `FILEFIN_ACCEPT_FIXTURE_KEY_LOSS` (record a captured JSON key
  disappearing; say so in the commit), `FILEFIN_MUTANTS_ALLOW_ZERO` (accept a
  diff that produced no mutants; say which of the two causes it was). Nothing
  else in `tool/` reads the environment except `FILEFIN_MUTANTS_BASE`, which
  chooses a diff base rather than relaxing a threshold. An undocumented lever
  that quietly lowers a bar is a gate you have already lost.
- Gate warnings (`just file-size`, `just comments`) may fall or hold, never rise.
- Coverage may fall or hold, never drop below the floor.

Debt you chose not to pay gets said out loud in your summary. Silence reads as
"there was none".

## Quality gates

Created in M0. A gate is not "planned" — either it runs in `just check` or it
does not exist.

| Gate | Recipe | Notes |
|---|---|---|
| Format | `just fmt-check` | `dart format --set-exit-if-changed` |
| Analyze | `just analyze` | `very_good_analysis`, `--fatal-infos --fatal-warnings` |
| Codegen | `just codegen-check` | build_runner then `git diff --exit-code` (§10) |
| Test | `just test` | `dart test` for pure packages, `flutter test` for the app |
| File size | `just file-size` | 400 soft / 600 hard lines; generated files exempt |
| Comment budget | `just comments` | 15% warn / 25% error, `//` only (§2) |
| Constitution | `just constitution` | ratcheting debt baseline (§1, §5–§9) |
| Dependencies | `just deps` | unused-in-pubspec / imported-but-undeclared (§4) |
| Mutation | `just mutants` | `mutation_test`, diff-scoped vs `FILEFIN_MUTANTS_BASE` (default `HEAD`; CI passes a real base) |
| Coverage | `just coverage-check` | lcov threshold; 50% floor, 80% target |
| Duplication | `just dupes` | `jscpd` (Dart tokenizer), 5% threshold, 15 lines / 50 tokens |
| Toolchain | `just toolchain-check` | fails when `dart` is absent or below 3.6 |
| Hooks | `just hooks-status` | fails when the git hooks are not installed |
| Fixtures | `just fixtures-verify` | SHA-256 manifest + captured-key ratchet + structural assertions (§8) |

- `just check` — everything above. **Run this before claiming work is done.**
- `just it` — integration tests against a real server (below). Arrived at M2.
  It is in **`check-all`, and `check-all` is local-only**: CI has no `filefin`
  binary, so putting `it` in `check` would make CI permanently red. From M2 on,
  done means "`just check` exits 0 **and** `just it` exits 0 on a machine with
  the binary" — DoD item 1 below covers only the first half.

`jscpd` was evaluated in M0 rather than assumed: it ships a Dart tokenizer and
was seen to fail on duplicated Dart (42.9% on a synthetic pair). The evaluation
and the thresholds are in `docs/architecture.md`.

### Gates must be able to fail

A gate that cannot fail is worse than no gate: it reports success and
suppresses scrutiny. Classic ways a shell gate silently always-passes:

- `find … | while read; do failed=1; done` — the body runs in a subshell, so
  the assignment is discarded and the script always exits 0. Use
  `done < <(find …)`.
- piping a *count* into a filter (`grep -c … | grep -v … | wc -l`) — the
  result is always 1 and the threshold is unreachable.
- `grep -rql` — `-q` suppresses the file list `-l` asks for.
- `flutter test` on a package with no test files exits 0.
- an **unquoted** file list (`grep … $files`) — it word-splits on IFS, so one
  path containing a space becomes two paths that do not exist, and a trailing
  `|| true` swallows the complaint. Read into an array, expand as
  `"${files[@]}"`.
- a diff-scoped gate whose base **is** the working tree. CI checks out a
  commit, so `git diff HEAD` is empty there and the gate measures nothing while
  reporting success.
- a denominator that omits what should sink it. `dart test --coverage` reports
  only libraries the tests loaded, so an unimported file is absent from the
  ratio rather than sitting at 0%.
- a guard keyed on something the gate itself excludes. The M0-only branches
  keyed on "no non-generated Dart", and generated Dart is excluded from every
  gate — so a tree of `*.g.dart` turned them all green again.
- an assertion satisfiable in prose. A check for `String toString(` matched the
  comment saying the class deliberately has none.

**When you add or change a gate, prove both directions.** Construct an input
that must fail, run the gate, confirm non-zero exit; then confirm the clean
tree still passes. A gate change is not done until you have seen it fail.

### Anything that rewrites lib sources in place runs alone

`mutation_test` edits the real source files and restores them, which is why
`just check` runs `mutants` last and why `just` runs its dependencies
sequentially. **The same hazard applies to any harness you write**, and at M3
it bit: a review agent's `mutate.py` was editing files in the main working copy
while a second agent ran the gates over them. The symptoms did not look like a
concurrency problem at all —

- `just fmt-check` failed 3 times in ~35 invocations, always naming one file,
  never reproducible on demand;
- `git status` once reported ` M apps/mobile/lib/src/app.dart` with an **empty
  diff** and an md5 identical to HEAD.

Both were the other process's window. Before you believe any gate failure,
check `git status --untracked-files=all` **and** check that nothing else is
mid-mutation; and run a mutation harness against a `git worktree` or a copy,
never against the tree someone else is measuring.

**A killed `just check` is the same hazard with one process.** `mutation_test`
restores each source after testing it, so interrupting the run — a timeout, a
Ctrl-C, a SIGTERM — leaves the mutant it was holding **on disk**. Demonstrated
at M3.R: a `just check` cancelled at ten minutes left
`if (isExpanded)` rewritten to `if (!(isExpanded))` in `visible_rows.dart`, and
the next run reported it as an `unnecessary_parenthesis` **info** from
`analyze` — a lint complaint about a silently inverted branch. Run `mutants` to
completion or not at all, and after any interrupted run diff the lib sources
before doing anything else.

## Working against a real server

Unit tests never touch the network. Integration tests run against a **real
`filefin` binary** started by the harness over a seeded temp data directory
(`just it`), because the interesting failures — byte-range behaviour, the 307
to HLS, headers surviving that redirect, session loss on server restart — are
exactly what a mock papers over.

`just it` **will fail** when the `filefin` binary is absent rather than
skipping. A skipped integration suite that reports success is the
gate-that-cannot-fail problem wearing a different hat.

`tool/run-integration.sh` refuses on a missing binary, a missing `ffmpeg`, a
missing `sqlite3`, zero test files, a `dart_test.yaml` (which can exclude tests
invisibly), **any test marked skippable**, **any test the runner reports as
skipped at runtime**, and a **test count below the committed floor**. A suite
that can excuse itself is the gate-that-cannot-fail wearing another hat.

The runtime skip check is the load-bearing one. A grep for skip syntax can only
catch the forms someone thought of: the first version matched `skip:` and was
defeated by `@Skip()`, `solo:` and `markTestSkipped`, any of which silently drop
a whole suite while the gate prints "All tests passed!". Asserting on the
runner's own `~N` skipped count catches every mechanism, including ones that do
not exist yet. The count floor catches the remaining case — a test quietly
deleted rather than skipped.

Every refusal has been proven in both directions, and so has the thing that
must fail underneath them: breaking F3's retry turns the restart test red. The
one precondition the script repairs rather than refuses is a missing seeded data
directory, because seeding is recoverable and a missing binary is not.

## Playback truths that keep biting

Kept here because every one of them was discovered by reading upstream source,
and each will look like a client bug when it happens:

- A non-browser-native file (HEVC, H.264-in-MKV) **cannot** be fetched as raw
  bytes. `GET .../file/{n}` 307s to HLS with no override.
- The reverse also holds: `.../hls/` returns **415** for a file that does *not*
  need transcoding. There is no quality or bitrate parameter anywhere.
- Server sessions are **in-memory and die on restart**. A `401` on any call is
  normal, not exceptional — re-auth and retry once (see `filefin_api`).
- No endpoint paginates. A large library returns everything in one array;
  lists must be virtualised.
- **"Browser-native" is decided by the PROBED container and codecs — but only
  once the probe agent has reached the row.** `fileNeedsTranscode`
  (`internal/server/playback.go:78`, v0.20.3) reads
  `if f.Container != "" && f.VideoCodec != ""` and otherwise falls back to
  `transcode.NeedsTranscode(f.Ext)`, whose whole vocabulary is
  `{.mp4, .webm, .m4v}`. **`tool/testserver/seed.sh` never probes** — it
  rebuilds the cache and stops, so `media_files.container` is `''` for every
  seeded row and `probe_tasks` is empty — which means *every verdict measured
  against the seeded library is the extension fallback*. M4's first pass read
  that fallback as the rule and amended SPEC §3.4; it was wrong, and the
  correction cost a whole exit criterion. **Both arms are in
  `tool/spikes/e5_mkv_direct_play.sh`:** one VP9/Opus `.mkv`, unprobed →
  `transcode:true` and **307**; after `POST /api/admin/probe/scan` the row
  carries `matroska,webm` / `vp9` / `opus` → `transcode:false` and **200 with
  `Accept-Ranges`**. So an `.mkv` *does* direct-play. Before concluding
  anything about this endpoint, look at the three format columns first.
- **libmpv verifies NO certificate by default.** Measured with mpv 0.41.0
  against this repo's own `server_a.crt`: default → the server logged
  `"GET … 200"`; `--tls-verify=yes` → `error:0A000086 certificate verify failed`
  and the server logged nothing. F15's pin lives in `filefin_api`'s socket;
  libmpv opens its own from native code. D10 is the answer.
- **The progress interval is MEDIA time, never wall clock.** Upstream compares
  `Math.abs(el.currentTime - lastMark) >= 30`. A wall-clock timer keeps
  re-reporting a paused position, and it makes F9 need a fake clock to test.
- **`Media`'s `httpHeaders` are cached GLOBALLY by URI** (`media_native.dart`:
  `httpHeaders ?? cache[uri]?.httpHeaders`). A second `Media` for the same URL
  with no headers inherits the first one's — so a negative control that shares a
  process with its positive is **vacuous**. Measured: an open with no cookie
  "succeeded" in-process and failed correctly in a fresh one.
  **It is not reachable through this app's code, and saying so is the point of
  keeping the entry** (M4.R/T6): the cache is consulted *only* when
  `httpHeaders` is null, `MediaKitPlaybackHost.open` always passes
  `request.headers`, and `PlaybackRequest.headers` is non-nullable — so the null
  branch cannot be taken from here. The separate control file and its
  distinguished URI stay as defence in depth against a future caller that stops
  passing them; treat this as a trap in the library, not as a live defect.
- **`VideoController` constructs fine under `flutter test`, and the thing that
  hangs is DISPOSE.** The original entry said the constructor "does not
  construct… it awaits a platform channel `flutter_tester` does not host", and
  `tool/coverage-gate.sh` raised the coverage ratchet on that sentence.
  Re-measured at M4.R in a plain `test()` body with a binding up:
  `VideoController(player)` returns, `Video(controller: …)` returns, and
  `player.dispose()` **never** returns. The constructor body is a fire-and-forget
  `() async { … }()` whose first statement awaits `addPostFrameCallback`
  (`video_controller.dart:71`), so it parks a closure rather than the caller —
  but it also sets `isVideoControllerAttached`, and `Player.dispose()` then
  awaits a completer only that parked closure completes. **Pumping** a `Video`
  is the other non-terminating case and is the one M4.0 actually measured.
  `real_mpv_player_test.dart` covers `buildSurface` by giving that test its own
  `Player` and never disposing it.

## Commit conventions

- Conventional Commits: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `perf`
- Scopes: `core`, `api`, `app`, `ui`, `player`, `build`
- Stage explicit paths. Never `git add -A` — it sweeps in whatever else is in
  the tree, including another agent's in-flight work.

## Definition of done

Work is done when all of these hold. "It compiles" is not on the list.

1. `just check` exits 0. Not "the part I ran" — the whole recipe.
2. Tests you wrote ran and passed, and you saw them fail first (§3).
3. No new code is unreachable from a test or a running path (§1, §5).
4. Every new dependency has an import and a one-line rent comment (§4).
5. Every new endpoint is in `docs/server-api.md` with its upstream citation
   and a captured fixture (§8).
6. The constitution ratchet did not rise.
7. Anything you could not finish is stated plainly in your summary, not left
   implied by silence.
