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
*Enforced by: `just comments`.*

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
Version constraints carry a one-line reason when they are tighter than caret
default. Pre-1.0 packages are pinned exactly.
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
  improvement in so it can never regress.
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
| Mutation | `just mutants` | `mutation_test`, diff-scoped vs `HEAD` |
| Coverage | `just coverage-check` | lcov threshold; 50% floor, 80% target |

- `just check` — everything above. **Run this before claiming work is done.**
- `just it` — integration tests against a real server (below). In `check-all`.

Duplication detection is deliberately absent: M0 evaluates `jscpd` for Dart
and either adds the gate or records in `docs/architecture.md` why not. An
unevaluated tool does not get a table row.

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

**When you add or change a gate, prove both directions.** Construct an input
that must fail, run the gate, confirm non-zero exit; then confirm the clean
tree still passes. A gate change is not done until you have seen it fail.

## Working against a real server

Unit tests never touch the network. Integration tests run against a **real
`filefin` binary** started by the harness over a seeded temp data directory
(`just it`), because the interesting failures — byte-range behaviour, the 307
to HLS, headers surviving that redirect, session loss on server restart — are
exactly what a mock papers over.

`just it` **fails** when the `filefin` binary is absent rather than skipping.
A skipped integration suite that reports success is the gate-that-cannot-fail
problem wearing a different hat.

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
