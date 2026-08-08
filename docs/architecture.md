# Architecture

Companion to `SPEC.md` §5. This file records decisions whose *rationale* would
otherwise live only in a commit message, and — importantly — the exact scope of
every gate. An undocumented gate exclusion is how a check quietly stops
covering half the tree.

---

## Layers

```
┌─────────────────────────────────────────────┐
│ apps/mobile                                 │  Flutter UI, media_kit player,
│                                             │  secure storage, connectivity
├─────────────────────────────────────────────┤
│ filefin_api      (dio + cookie jar)         │  auth, 401-retry (F3),
│                                             │  typed endpoints, poster cache
├─────────────────────────────────────────────┤
│ filefin_core     (pure Dart, no I/O)        │  models, extension-type IDs,
│                                             │  URL building, resume rules,
│                                             │  playback decision
└─────────────────────────────────────────────┘
```

Dependencies point one way. `filefin_core` is pure (CLAUDE.md §6) because it is
where the server's own progress semantics are re-implemented: an optimistic UI
update is a *prediction* of what the server will do, and a prediction is only
worth making if it can be property-tested against the real rules. Anything that
needs a clock, a socket, or a screen cannot be.

`filefin_api` owns the cookie jar and is the **only** place a `401` is
interpreted, so F3's re-auth-and-retry exists once rather than at every call
site.

---

## Repository layout

```
packages/
  filefin_core/       pure Dart: models, rules, URLs            (M1)
  filefin_api/        HTTP client                               (M2)
apps/
  mobile/             Flutter app                               (M3)
docs/
  server-api.md       endpoint contract, cited + version-pinned (§8)
  architecture.md     this file
  risks.md            open risks and their spikes
test/fixtures/        captured real server payloads + PROVENANCE.md
tool/                 gate scripts, git hooks, the test-server harness
mutation_rules.xml    mutation exclusions, each with a retirement condition
justfile              every gate; if it is not a recipe here it does not exist
```

A pub **workspace** (root `pubspec.yaml`'s `workspace:`), not melos. Pub does
this natively from Dart 3.6: one lockfile, one `.dart_tool`, one `dart pub get`
for the whole tree. Melos would be a dependency earning no rent (§4).

The root `workspace:` list starts empty and gains a member when that member is
created. Listing a directory that does not exist yet fails `dart pub get`
outright, so the list cannot run ahead of the tree.

---

## Gate scope — what each gate actually measures

This is the section to read before assuming a gate covers something.

Source discovery lives in exactly two functions in `tool/common.sh`, so two
gates can never disagree about which files count:

- **`dart_sources`** — every `*.dart` under `packages/` and `apps/`, excluding
  `*.g.dart`, `*.freezed.dart`, `.dart_tool/` and `build/`. Tests included.
- **`dart_lib_sources`** — the subset under a package's `lib/`. Tests excluded.

| Gate | Scope | Why that scope |
|---|---|---|
| `file-size` | `dart_sources` — **tests included** | a 900-line test file is as hard to review as a 900-line library. 400 soft / 600 hard. |
| `comments` | `dart_lib_sources` — **tests excluded** | test narration is a feature, not debt. A test that says *why* this case exists is doing its job; the 15/25% budget would punish it. |
| `constitution` / `placeholders` | `dart_lib_sources` | a `TODO` in a test is a note about the test; a `TODO` in shipping code is an unfinished feature. |
| `constitution` / `core_purity` | `packages/filefin_core/lib/**` + that package's pubspec | `test/` may use `dart:io` — `loadFixture` has to read a file. §6 governs what ships. |
| `constitution` / `id_typedefs` | `dart_sources` — tests included | a typedef in a test would launder the rule into the codebase. |
| `constitution` / `dead_types` | `dart_sources` | a variant constructed only by a test still has a consumer; §5 asks for *a* consumer, and a test is one. |
| `constitution` / `undocumented_endpoint` | `dart_lib_sources` | a path literal in a test fixture helper is not a call we make. |
| `constitution` / `secret_tostring` | `dart_lib_sources` | §9 is about what ships and what logs. |
| `deps` | every `pubspec.yaml`, sources = that package's `lib bin test tool example` | a dev-dependency used only by tests is used. |
| `dupes` | `packages/` + `apps/`, `*.dart`, generated excluded | generated code is duplicative by construction and nobody can refactor it. |
| `coverage` | `report-on` each package's `lib/` | test code covering itself is not evidence. |
| `mutants` | changed files under a package's `lib/`, non-generated | diff-scoped; see below. |
| `fixtures-verify` | `test/fixtures/**` | reads committed files only, so it runs in CI without a server. |

Generated files are exempt from every gate. The exemption lives in
`dart_sources`, in one place, and was proven: a 700-line file fails `file-size`
and the identical 700 lines renamed `*.g.dart` pass.

### The no-op paths, and why they cannot survive M1

Three gates have a branch that exits 0 without measuring anything, because at
M0 the tree contains no Dart at all: `test`, `coverage-check`, `dupes`. Each of
those branches is guarded on `dart_sources` being **completely empty**, and each
prints "(M0 only)". The first Dart file that lands anywhere under `packages/`
or `apps/` makes them unreachable, and the gates then fail rather than skip —
`run-tests.sh` fails when a package has no `*_test.dart`, `run-coverage.sh`
fails when no package has a `test/` directory, `check-coverage.sh` fails on an
lcov with zero `DA:` records.

`codegen-check` has a fourth: it exits 0 when no package declares
`build_runner`. That one is guarded differently — it fails if generated files
are committed while nothing can regenerate them, which is the only way that
branch could hide a real problem.

These are recorded in `STATE.md` as accepted M0 debt rather than left implied.

---

## Duplication: the jscpd evaluation

CLAUDE.md requires M0 to evaluate `jscpd` for Dart and either add the gate or
record why not. It was evaluated, empirically:

- `jscpd@4.0.5` ships a **Dart tokenizer** (one of 224 formats).
- On a synthetic pair of near-identical 27-line Dart classes it reported
  `1 exact clone, 25 (46.3%) duplicated lines` and **exited 1**.
- On the same tree with one of the two files removed it exited 0.

So the gate exists: `just dupes`, in `just check`.

| Setting | Value | Reason |
|---|---|---|
| version | pinned `4.0.5` | a detector whose defaults move between patch releases turns "duplication rose" into "the tool changed its mind" |
| threshold | 5% | a starting number over an empty tree; it ratchets down, never up |
| min-lines | 15 | below that, Dart's `@freezed` and `switch` shapes are legitimately repetitive |
| min-tokens | 50 | pairs with min-lines; a 15-line block of declarations is not a clone worth naming |

Cost accepted: the gate needs Node. A missing `npx` **fails** the gate rather
than skipping it — a silently skipped duplication check is the
gate-that-cannot-fail problem wearing a different hat.

---

## Version pinning policy

Pinned **exactly** (no caret), each with a one-line reason in the pubspec:

| Package | Why exact |
|---|---|
| `mutation_test` | a mutation result that changes with a patch release makes `just mutants` non-deterministic across machines |
| `freezed`, `freezed_annotation` | generated output must be byte-identical or `just codegen-check` fails on a machine that merely resolved differently (M1) |
| `json_serializable`, `json_annotation` | same (M1) |
| `glados` | property-test shrinking and seeding must reproduce a reported failure (M1) |
| `jscpd` (via `tool/check-dupes.sh`) | see above |

`pubspec.lock` is **committed** and is not in `.gitignore`. The two gates above
that must be reproducible are exactly the two that read resolved versions.

---

## Mutation testing: how the gate is scoped

`mutation_test` has no diff mode of its own, so `tool/check-mutants.sh` builds
the target list itself: files changed against `FILEFIN_MUTANTS_BASE` (default
`HEAD`), restricted to a package's `lib/`, non-generated, **plus untracked
files** — a brand-new file is precisely the code that has never been tested, and
`git diff` cannot see it.

Two properties of the tool drove the design and were verified against the
pinned 1.7.1 rather than assumed:

1. **It rewrites source files in place** and restores them afterwards. Nothing
   else may read those files while it runs, so `mutants` is last in
   `just check` and out of the pre-commit hook entirely.
2. **It exits 255** when the threshold is missed, not 1.

The threshold is 100%. A diff-scoped gate asks about the handful of mutants
this commit adds, so anything less means "some of them may survive".

Every exclusion in `mutation_rules.xml` carries a reason **and a retirement
condition**, because an exclusion is a piece of code the gate has stopped
asking about.

---

## Fixtures: why a checksum manifest

`test/fixtures/SHA256SUMS` is checked by `just fixtures-verify`, which is in
`just check`.

The failure mode it guards is specific: editing a captured payload so a failing
test passes. That converts "captured real payload" back into "a JSON literal
that agrees with our own class", which is the exact thing CLAUDE.md §8 exists
to prevent. A legitimate re-capture regenerates the manifest, so the change
surfaces in review as a manifest diff next to a stated upstream version.

A checksum cannot tell a rich payload from a degenerate one, so the same script
also asserts the set still exercises the shapes the models need: populated
`metadata`/`ratings`/`technical`/`actors`/`genres`/`tags`, a two-file item, a
non-zero `continueIndex`, and both playback branches. Both halves were proven
to fail independently.

---

## Open questions

- **Q1 — state management for the app layer.** Deliberately deferred to M3, so
  it is chosen against real screens rather than in the abstract (SPEC.md §6,
  §13 "Still open"). Not a blocker before then. The decision lands here.
