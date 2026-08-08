# State

Where the project is, milestone by milestone, and what it knowingly owes.

| | |
|---|---|
| **Done** | **M0** — workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture, R1 retired, R4 licensing position recorded, then remediated against three adversarial reviews |
| **Next** | **M1** — `filefin_core`: models, extension-type IDs, URL building, resume engine, `decide()` |
| **Exit criterion met** | `just check` exits 0 on a clean tree; every gate has a both-directions proof below |

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
| `codegen-check` | *deferred to M1.4* — see below | — | no build_runner package, no committed generated files | 0 |
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
| `test` | *zero-test guard not yet exercisable on a real package* — see debt below | — | no Dart sources | 0 |
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

### Gate proofs deliberately deferred

Stated here rather than left implied by silence.

- **`codegen-check`** — deferred to **M1.4**. There is no `build_runner`
  package and no committed `*.g.dart`, so the "regenerate then `git diff
  --exit-code`" path has nothing to run. The proof to perform at M1.4:
  hand-edit one character in a committed `*.g.dart` → exit 1 → revert → exit 0.
  What *is* proven now is the anti-vacuity guard: the script fails if generated
  files are committed while no package declares `build_runner`.
- **`coverage-check` on real code** — deferred to **M1.9** (A5). The gate is
  proven synthetically above against hand-made lcov files with known ratios.
  M1.9 must record the real figure and then push coverage below 50 and confirm
  exit 1.
- **`mutants` on real code** — deferred to **M1.9** (A5). Proven above against
  a real (scratch) Dart package with a real weak test, which is stronger than a
  synthetic fixture, but not yet against `filefin_core`. M1.9 must delete the
  equal-to-threshold assertion in `decide_test.dart`, confirm a survivor, and
  restore.
- **`test` zero-test guard** — the guard is written and reads
  `find … -name '*_test.dart' | grep -c .`, but there is no package to point it
  at. Measured on the pinned SDK: `dart test` exits **79** ("No tests were
  found") on an empty `test/` and **65** with no `test/` at all, so `dart test`
  alone would not have gone vacuous. `flutter test` **does** exit 0, and joins
  this script at M3 — that is what the guard is for. Prove it at M1.1 by
  deleting the test file from `filefin_core` and confirming exit 1.

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

### `build_runner` was removed rather than justified

Finding F3: `tool/dep-allowlist.txt` claimed it was "invoked by `just codegen` /
`just codegen-check`", but `check-codegen.sh` scans `packages/*` and `apps/*`
for a `build_runner:` declaration, found none — it was declared in the *root*
pubspec — and short-circuited. `just codegen` had no builders and no caller. So
it was a dependency no milestone needed yet, which is §1.

It is gone from `pubspec.yaml`, from the allowlist, and `just codegen` is gone
with it; all three return at **M1.4** with the first `@freezed` model.
`codegen-check`'s anti-vacuity guard is unaffected and still proven: committed
generated files with no declared builder fail.

### Deferred by decision, not oversight

| Item | Decision | Where |
|---|---|---|
| **A2** — `ServerId` | Deferred to **M2**. CLAUDE.md §7 names it, but no consumer exists until multi-server lands, and §1 forbids building ahead of the milestone that needs it. `id_typedefs` already greps for it, so a typedef version cannot sneak in meanwhile. | M1.2 defines the other four |
| **A4** — `just it` | **Not created in M0.** There is no integration suite until M2, and a recipe over zero tests reports success. M0's exit criterion is `just check`, which does not include `it`. `check-all` is currently an alias for `check`. | M2 |
| **A5** — `mutants` / `coverage-check` on real code | Created and proven in M0 (synthetically for coverage, against a real scratch package for mutants); re-proven against `filefin_core` at **M1.9**. | above |
| **A9** — `progressIntervalSecs` | `PlaybackSettings` is `{wifiOnly, meteredWarnBytes}` only. The interval arrives at **M4** with the progress reporter; a settings field nobody reads is a dead branch (§5). | M4 |
| **A10** — `RefuseReason` | `{offline, wifiOnlyOnMetered}` only. The 415 "transcoding disabled" message is knowable only *after* a request, so it is an M5 `filefin_api` concern, not a `decide()` branch. | M5 |
| **A11** — `Tag` model | `GET /api/tags` is documented and captured, but **no model in M1** — no F-requirement consumes the vocabulary yet. | when a screen needs it |

### Fixture coverage gaps

Listed in full in `test/fixtures/PROVENANCE.md`. Summary: no poster bytes (the
seeded items have no poster and no model decodes an image), no HLS segment
bytes (multi-megabyte binary; R1's spike already confirmed `200 video/mp2t`),
and only one user — who **is** an admin — so neither per-user state isolation
nor a non-admin `authResult` is exercised. The `Retry-After` gap is closed:
verified live as `Retry-After: 900` on the sixth consecutive bad login,
matching `int(retry.Seconds()) + 1` at `auth.go:149`. None of these is claimed by any M1 model, so §8 is intact; they
land on the `just it` harness at M2/M5.

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
- The review reported `SPEC.md:102` citing `server.go:456` for the `authResult`
  *shape*. Both readings are half right: the struct is `server.go:447-453` and
  `:456` is `authResultOf`, which builds it. The sentence now names both, since
  a reader following the citation wants the struct.
