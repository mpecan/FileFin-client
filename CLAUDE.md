# FileFin Client

A mobile client for [FileFin](https://github.com/xuedi/FileFin), a
filesystem-first self-hosted media server. Flutter + Dart, playback by
`media_kit` (libmpv) on Android and iOS.

The server is a third-party project we do not control. Its HTTP contract is an
external boundary — observed, documented, and versioned, never assumed.

- Full technical specification → `SPEC.md`
- Current state, milestone by milestone → `STATE.md`
- Server API contract, cited to upstream source → `docs/server-api.md`
- Architecture, layout, gate scope → `docs/architecture.md`
- Decisions we made, and what each rejected → `docs/decisions/` (indexed by
  `SPEC.md` §13)
- How the server, libmpv, dio and Flutter were **measured** to behave →
  `docs/field-notes.md`
- Risks not yet retired, with their spikes → `docs/risks.md`

## Constitutional stipulations

Mandatory. Violating any of them is a review finding. Each names the command
that enforces it — **a rule with no check is a rule that gets ignored**.

**§1 — You Aren't Gonna Need It.** Do not build anything until the milestone
that needs it. No speculative classes, no stub files, no unused dependencies,
no settings nobody reads. Every line must be reachable from a test or a
running path. Delete dead code immediately — git remembers.
*Enforced by: `just constitution` (placeholders), `just analyze`.*

**§2 — Comments describe interfaces. Everything longer lives in a document.**

A comment says what a reader of the declaration needs and cannot get from the
code: why a non-obvious choice was made, what invariant holds, which server
quirk a workaround exists for. It does not say what the code already says, and
it does not carry the argument for a decision or the record of a measurement.
Those have homes:

- **`docs/decisions/`** — a choice *we* made, with the alternative that was
  rejected. Indexed by `SPEC.md` §13, which keeps the D-numbering.
- **`docs/field-notes.md`** — how the server, a dependency or the framework was
  *observed* to behave. Not our choice, so not a decision.

The comment then cites it: `/// See D12.` The prose is the asset; its location
was the bug.

**Two checks, and the first one is the rule.** No single comment block may
exceed **12 lines** — a comment describing an interface is bounded by that
interface, and twelve lines is four sentences. Separately, comment lines stay
below **35%** of non-blank lines **tree-wide**, error at 45%, counting `//` and
`///` together.

**The ratio is tree-wide rather than per file, and that is on evidence.** Per
file it punishes the shape this rule exists to produce: `ids.dart` scores 81%
for being five one-line `extension type` declarations each with a sentence on
them, and nothing about that file is wrong. Per file, the number correlates
with declaration density rather than with verbosity. There is no size exemption
any more, because a tree-wide ratio has no small-file sensitivity and a block
is a count rather than a percentage.

**The numerator changed at M8.R and the old thresholds do not carry over.** §2
counted `//` and excluded `///` from both sides, on the reasoning that the
budget was about narration. The outcome: the tree measured 3.8% `//` and 34.0%
`///` — 37.9% overall — while `just comments` printed "0 error(s), 0
warning(s)". Worse, the documented remediation exploited it: three files that
breached §2 at M3.R were paid "by moving the rationale into the `///` doc
comment", and were still 44–59% comments five milestones later. The fix was a
change of comment syntax. Do not compare 15/25 with 35/45; they measure
different things.

**This budget governs Dart, and `just comments` measures Dart only.** The shell
under `tool/` is deliberately exempt, and the exemption is a decision rather
than an oversight: nearly every script there would breach both the block cap and
the ratio, several of them many times over. Every one of those comments is the
kind §2 calls rent-paying — *why* process substitution instead
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
- **Three environment variables can relax a bound, and they are the complete
  list.** Each refuses by default, names itself in its own error message, and
  requires the reason to be written down where a reviewer sees it —
  `FILEFIN_ACCEPT_NEW_DEBT` (raise a constitution baseline; say so in
  STATE.md), `FILEFIN_ACCEPT_FIXTURE_KEY_LOSS` (record a captured JSON key
  disappearing; say so in the commit), `FILEFIN_MUTANTS_ALLOW_ZERO` (accept a
  diff that produced no mutants; say which of the two causes it was). An
  undocumented lever that quietly lowers a bar is a gate you have already lost.

  **The claim is about levers, not about reading the environment**, and this
  sentence used to say "nothing else in `tool/` reads the environment except
  `FILEFIN_MUTANTS_BASE`", which was simply false: `tool/` also reads `CI`,
  `TMPDIR`, `HOME`, `FILEFIN_BIN`, `FILEFIN_RUN`, `FILEFIN_USER`,
  `FILEFIN_PASS`, `FILEFIN_PORT`, `FILEFIN_UPSTREAM_CLONE`,
  `FILEFIN_TRANSCODE_CATEGORY`, `FILEFIN_E5_RUN`, `FILEFIN_E5_PORT` and
  `LIBMPV_LIBRARY_PATH`. Every one of those names *where something is* or *what
  is being run against*; none of them moves a threshold, and stating the rule as
  "reads the environment" made a true and useful claim look like a false one.
  `FILEFIN_MUTANTS_BASE` is in that group too: it chooses a diff base.

  A fourth lever did exist and is gone. `FILEFIN_MUTANTS_TIMEOUT` arrived at
  M5.R, named itself nowhere in the output, had no bound in either direction —
  a large enough value silently disables hang detection — and bypassed both the
  12x derivation and the floor. It was removed at M6.R rather than documented:
  the tooling gives, the constitution does not take back, and an override there
  re-opens exactly what the derivation closed.
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
| Comment budget | `just comments` | 12-line block cap; 35/45% tree-wide, `//` and `///` (§2) |
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
- **a gate that HANGS rather than fails.** `mutation_test` runs the whole suite
  once per mutant under a 300 s command timeout and counts a timed-out run as
  *undetected*, so one mutant that loops forever costs five minutes and then
  reports as a survivor no per-file listing names. The shape that does it is a
  bound written **only as a condition** in front of a recursive call: rewrite
  its `||` to `&&` and the recursion is unbounded. Measured at M5.R on
  `PlayerController._open`'s one retry — three runs out of three, always
  `Undetected: 1, Timeouts: 1` with `0 not detected` in every file. Bound such
  a thing **structurally** — a parameter the second call passes — so no rewrite
  of the condition can loop. `mutation_rules.xml` already excludes every loop
  rule for exactly this reason; the same hazard reaches ordinary recursion.
  To find one: sample `git diff` of the mutated sources every ten seconds
  through a run and look for the mutant that sits on disk for 300 s.

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

**Moved to [`docs/field-notes.md`](docs/field-notes.md) at M8.R.** Every one of
them was discovered by reading upstream source or by measuring against a real
binary, and each will look like a client bug when it happens — but they are
facts about things we do not control rather than rules, and a rules document
was the wrong place to keep them. The file also carries what was scattered
across doc comments: the dio, Flutter and `audio_service` observations, and the
server behaviours the endpoint documentation does not imply.

Read it before concluding anything about libmpv, the 307 to HLS, the transcode
verdict, or why a test file crashes its own runner.

## D-pad reachability is a gate, not a review note

Every control on a television has to be reachable with four arrow keys and a
centre button, and "it has a `Focus`" does not establish that. `TvShell`'s rail
was focusable, correct, and a **trap**: `FocusScope` is a traversal boundary —
`inDirection` stops at its edge — so focus entered the navigation and `right`
never left it again. Nothing in `analyze`, `constitution` or the widget suites
saw it, because every one of them can only ask whether a widget exists.

`test/support/dpad.dart` is the answer and the shape of it is load-bearing:

- **A walk of the directional focus graph, breadth-first, pressing only arrow
  keys.** It returns the set of labels it reached, and a TV suite asserts its
  controls are in that set.
- **It returns to each node before trying the next direction from it.** Two
  simpler walks were written first and both reported live controls as
  unreachable — the one answer this check must never invent. Cycling the four
  directions one press at a time walks a column as A → B → A → B for ever,
  because `up` undoes every `down`; running each direction to exhaustion escapes
  the column but then presses `up` from wherever it landed.
- **A control whose focused subtree has no `Text`, `Tooltip` or labelled `Icon`
  is reported as `?`**, and that is a finding rather than a limitation: a remote
  user and a screen reader have nothing to go on either. The scrubber was `?`
  until it got a `Tooltip` — placed INSIDE the `DpadFocusable`, because a name
  on an ancestor is not the focused node's name.

The walk found the rail's trap and a server row that was not focusable at all.
The coverage ratchet found the third — a `TvShell.onSignOut` no widget invoked,
which is the same class of defect seen through a different instrument.

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
