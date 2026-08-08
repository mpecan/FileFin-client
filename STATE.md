# State

Where the project is, milestone by milestone, and what it knowingly owes.

| | |
|---|---|
| **Done** | **M0** — workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture, R1 retired, R4 licensing position recorded |
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
| M0.13b | `tool/fixtures/capture_state_vectors_test.go` + `tool/capture-resume-vectors.sh` → `test/fixtures/resume_vectors.json`, **333 vectors captured from the real engine** |
| M0.14 | `docs/architecture.md`, `docs/risks.md`, this file |
| M0.15 | `.github/workflows/ci.yml` |
| extra | `tool/check-dupes.sh` + `just dupes` — jscpd was evaluated and *works* for Dart, so the gate exists rather than a note explaining its absence |

---

## Gates: both-directions proof log

CLAUDE.md: *"A gate change is not done until you have seen it fail."* Every row
below was executed. "Fail input" is the exact thing constructed; both exit
codes were observed, not inferred.

| Gate | Fail input | Exit | Clean | Exit |
|---|---|---|---|---|
| `toolchain-check` | ran with `PATH=/usr/bin:/bin` so `dart` is absent | **1** | normal PATH, Dart 3.12.2 | 0 |
| `hooks-status` | before `just install-hooks` | **1** | after installing | 0 |
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
| `constitution-accept` — up | accepted with 1 placeholder present → baseline 0 → 1, with a loud `WARNING: … Accepting new debt, not paying it`; a subsequent `check` then passed at the raised baseline | 0 | — | — |
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
| `mutants` — empty diff | no changed Dart lib sources vs HEAD | 0, with `no changed Dart lib sources vs HEAD — nothing to mutate` | — | — |
| `fixtures-verify` — manifest | `jq '.title = "Sneakily Edited"'` on a committed fixture → diff against `SHA256SUMS` | **1** | restored | 0 |
| `fixtures-verify` — structural | `jq '.tags = []'` **and** a regenerated manifest, so the checksum half passes → structural assertion caught it | **1** | restored | 0 |
| `test` | *zero-test guard not yet exercisable on a real package* — see debt below | — | no Dart sources | 0 |
| pre-commit hook — blocks | badly-formatted staged `.dart` | **1**, `BLOCKED by: fmt analyze` | — | — |
| pre-commit hook — bypass is audible | same tree, `git commit --no-verify` | commit **succeeded (0)** *and* post-commit printed `WARNING: commit 2c16415 landed with failing gates` with the full gate log and the amend instruction | — | — |
| pre-commit hook — clean | clean tree | 0, `all gates passed`, post-commit **silent** | — | — |

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

### The three M0-only no-op gate paths

`test`, `coverage-check` and `dupes` each have one branch that exits 0 without
measuring anything, because the tree contains **no Dart at all**. Each branch
is guarded on `dart_sources` being completely empty and prints "(M0 only)".

The first `.dart` file under `packages/` or `apps/` makes all three
unreachable, and from that moment the gates fail rather than skip:
`run-tests.sh` fails when a package has no `*_test.dart`; `run-coverage.sh`
fails when no package has a `test/`; `check-coverage.sh` fails on an lcov with
zero `DA:` records. `codegen-check` has a fourth such branch, guarded instead
by "generated files committed but nothing can regenerate them".

This is genuine vacuity for the duration of M0 and it is the price of M0's exit
criterion being `just check exits 0` over an empty tree. It self-destructs at
M1.1.

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
no captured `Retry-After` value, and only one user so per-user state isolation
is untested. None of these is claimed by any M1 model, so §8 is intact; they
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
  the existing clone with the local toolchain and produced 333 vectors. The
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
  now; `check-fixtures.sh` is the real backstop, and it is exhaustive.
