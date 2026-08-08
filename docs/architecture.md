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

### Why `filefin_api` has no Flutter

Decided at M2, and structural rather than stylistic. Three gates make it so:

- `tool/run-tests.sh`, `run-coverage.sh` and `check-mutants.sh` all run `dart
  test` per package. A Flutter package needs `flutter test` and a different
  coverage path, so a Flutter dependency here would force all three to grow a
  Flutter branch at M2 instead of M3.
- `flutter_secure_storage` has **no VM implementation**: under `dart test` it
  throws `MissingPluginException`. Every F3 unit test would need a Flutter
  binding and a fake platform channel — mocking exactly the layer that matters.
- §6 constrains only `filefin_core`. `dart:io` in `filefin_api` is fine and F15
  requires it. "Pure" here means **Flutter-free**, not I/O-free.

So credential storage is an injected port. `SecretStore` is an
**`abstract base class`** — `base` forces every subtype to `extend` rather than
`implement`, which is what makes its redacting `toString` *inherited* instead of
merely recommended; an interface could only ask an implementation to redact.
`InMemorySecretStore` ships with it and is **not a stub**: F3 needs the password
in memory for the process lifetime whatever the persistence story is, because a
re-auth cannot await a Keychain prompt in the middle of a 401 retry. M7's
platform store is a persistence decorator around it.

This resolves SPEC.md §5.1 vs §6 on where secure storage lives: the *port* is in
`filefin_api`, the *platform implementation* is in `apps/mobile`. **Nothing at
M2 proves a password survives an app restart**, and STATE.md says so rather than
letting the port's existence imply it.

The SPEC §7 key layout (`filefin/{serverId}/session|password|certpin`) lives in
exactly one function, `secretKeyFor`. A layout written twice is a layout that
will be written differently, and the failure mode is a credential that silently
cannot be found rather than an error anyone sees.

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

One consequence bit the first member that landed: in a workspace, `dart pub get`
writes **one** `package_config.json`, at the root. Members do not get their own,
so anything that names `<package>/.dart_tool/package_config.json` — as
`run-coverage.sh` did — silently receives an argument that means "no packages".

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
| `deps` | every `pubspec.yaml`, sources = that package's `lib bin test integration_test tool example` | a dev-dependency used only by tests is used. `integration_test` joined at M2: without it an undeclared import in an integration suite was reported by nothing, and Dart resolves one anyway through a sibling workspace member — which is exactly how an undeclared dependency survives to break a clean checkout. Proven at M2.7: the same undeclared import gave exit 0 before and 1 after. |
| `dupes` | `packages/` + `apps/`, `*.dart`, generated excluded | generated code is duplicative by construction and nobody can refactor it. |
| `coverage` | `report-on` each package's `lib/`, `--check-ignore`, cross-checked against `dart_lib_sources` | test code covering itself is not evidence. The cross-check is what puts an unimported file in the denominator: `dart test --coverage` reports only libraries the tests loaded, so without it an untested file is absent from the ratio rather than 0%. `--check-ignore` is what keeps generated freezed boilerplate out of it — see below. |
| `mutants` | changed files under a package's `lib/`, non-generated | diff-scoped; see below. Never runs over `integration_test/`. |
| `fixtures-verify` | `test/fixtures/**` | reads committed files only, so it runs in CI without a server. |

Generated files are exempt from every gate. The exemption lives in
`dart_sources`, in one place, and was proven: a 700-line file fails `file-size`
and the identical 700 lines renamed `*.g.dart` pass.

### Coverage and generated code

`dart_sources` cannot do this job for coverage, because coverage is produced by
`format_coverage --report-on=lib`, which does not consult it. Two rules fill the
gap, and they pull in opposite directions on purpose.

**`--check-ignore` honours `// coverage:ignore-file`, which freezed writes on
line 2 of everything it generates.** Without it the denominator was 793 lines of
which 591 were freezed's `when` / `maybeMap` / `whenOrNull` pattern-matching
helpers — code with no caller and no prospect of one — and the gate reported 53%
while every hand-written line was covered. A number that noisy cannot detect a
real regression. json_serializable does *not* write that comment, so the
`.g.dart` decode bodies stay counted, which is right: tolerant decoding is what
§8 is about.

**A `coverage:ignore` comment in hand-written `lib/` source is an error.** That
is the hole the flag opens — a one-line opt-out of the §3 floor — and
`run-coverage.sh` fails on it. Only generated files may carry one.

**A lib source that produces no coverage record at all fails**, unless it
contains no executable code. A barrel of `export`s and a set of `extension type`
declarations compile to no functions, so the VM emits no hitmap entry for them
however well they are exercised; requiring one would be requiring the
impossible. The exemption is mechanical rather than a list: every line of the
file must be a `library` / `import` / `export` directive or an empty-bodied
`extension type`. There is no allowlist and no marker comment, because both are
things a reviewer can be talked past.

### The no-op paths, and why they cannot survive M1

Three gates have a branch that exits 0 without measuring anything, because at
M0 the tree contains no Dart package at all: `test`, `coverage-check`, `dupes`.
Each prints "(M0 only)".

Each of those branches is guarded on `no_dart_packages` — **no `pubspec.yaml`
under `packages/` or `apps/`**. It used to be guarded on `dart_sources` being
empty, and that guard did not hold: `dart_sources` excludes `*.g.dart` and
`*.freezed.dart`, so a package whose only Dart was generated made all three
branches reachable again, long after M0 and precisely over code nobody had
written a test for. A `pubspec.yaml` cannot be excluded away.

The first package makes them unreachable, and the gates then fail rather than
skip — `run-tests.sh` fails when a package has no `*_test.dart`,
`run-coverage.sh` fails when a package has no `test/` directory **and** when any
`lib/` source produced no coverage record at all, `check-coverage.sh` fails on an
lcov with zero `DA:` records.

`codegen-check` has a fourth: it exits 0 when no package declares
`build_runner`. That one is guarded differently — it fails if generated files
are committed while nothing can regenerate them, which is the only way that
branch could hide a real problem.

These are recorded in `STATE.md` as accepted M0 debt rather than left implied.
**All of them retired at M1.1**, when `packages/filefin_core/pubspec.yaml`
landed; `codegen-check`'s fourth retired at M1.4 with the first `@freezed`
model.

---

## Duplication: the jscpd evaluation

CLAUDE.md requires M0 to evaluate `jscpd` for Dart and either add the gate or
record why not. It was evaluated, empirically:

- `jscpd@4.0.5` ships a **Dart tokenizer** (one of 224 formats).
- On a synthetic pair of near-identical 27-line Dart classes it reported
  `1 exact clone, 25 (46.3%) duplicated lines` and **exited 1**.
- On the same tree with one of the two files removed it exited 0.

So the gate exists: `just dupes`, in `just check`.

Every one of these is a literal in `tool/check-dupes.sh`. The version and the
threshold were briefly readable from `FILEFIN_JSCPD_VERSION` and
`FILEFIN_DUPES_THRESHOLD`, which nothing set and nothing documented — an
environment variable that silently raises the threshold contradicts both "pinned"
and "ratchets down, never up", and a gate-weakening lever left lying around gets
pulled. Lowering the threshold is an edit here, reviewed in the diff.

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

The policy for a package **when it is added**: pinned exactly (no caret), with
a one-line reason in the pubspec. Every row below is in the tree as of M2
except `glados`, which was replaced by `kiri_check` — see STATE.md.

**The policy conflicts with CLAUDE.md §4 as written, and the stricter reading
wins.** §4 says "pre-1.0 packages are pinned exactly", which implies caret above
1.0; this file says exact on introduction, full stop. M2 resolved it in favour
of this file and recorded why in the pubspec: a `dio` patch release that changes
interceptor ordering or `fetch` semantics silently changes F3, and both `just
mutants` and `just codegen-check` need identical resolution on every machine to
answer the same way twice. **§4's wording deserves a one-line reconciliation**
so the two documents stop disagreeing; it is flagged in STATE.md rather than
edited unilaterally, because CLAUDE.md is the constitution.

| Package | In the tree | Why exact |
|---|---|---|
| `mutation_test` | yes | a mutation result that changes with a patch release makes `just mutants` non-deterministic across machines |
| `dio` (5.11.0) | M2 | an interceptor-ordering or `fetch` change is an F3 change, and it would arrive silently |
| `dio_cookie_manager` (3.5.0), `cookie_jar` (4.0.9) | M2 | the session cookie's round trip is what F3 replays through; `cookie_jar` is named directly so the jar stays in memory, since `PersistCookieJar` writes a session cookie to a plain file and §9 forbids that |
| `crypto` (3.0.7) | M2 | a fingerprint that changed with a patch release would look to every user like their server's certificate had been replaced |
| `jscpd` (literal in `tool/check-dupes.sh`) | yes | a detector whose defaults move between patch releases turns "duplication rose" into "the tool changed its mind" |
| `freezed`, `freezed_annotation` | M1.4 | generated output must be byte-identical or `just codegen-check` fails on a machine that merely resolved differently |
| `json_serializable`, `json_annotation` | M1.4 | same |
| `kiri_check` (1.3.1) | M1 | property-test shrinking and seeding must reproduce a reported failure, and `just mutants` runs the suite once per mutant — a generator drawing a different sample each run turns a surviving mutant into a coin flip. (This row named `glados`, which does not resolve on any Dart 3 SDK.) |

`build_runner` is not in the pubspec at M0 either: nothing generates anything
yet, so it paid no rent (§1, §4). It arrives at M1.4 with the first `@freezed`
model, together with `just codegen`.

`pubspec.lock` is **committed** and is not in `.gitignore`. The two gates above
that must be reproducible are exactly the two that read resolved versions.

---

## Mutation testing: how the gate is scoped

`mutation_test` has no diff mode of its own, so `tool/check-mutants.sh` builds
the target list itself: files changed against `FILEFIN_MUTANTS_BASE` (default
`HEAD`), restricted to a package's `lib/`, non-generated, **plus untracked
files** — a brand-new file is precisely the code that has never been tested, and
`git diff` cannot see it.

**The default base is right locally and fatal in CI**, and for a while CI ran
with it. The working tree versus the last commit is what the commit about to be
made is responsible for — but CI *checks out* a commit, so the tree IS `HEAD`,
the diff is empty, and the gate printed "nothing to mutate" and exited 0 on
every PR and every push. `.github/workflows/ci.yml` now passes the pull
request's base sha, or `HEAD^` on a push, and `check-mutants.sh` refuses to
report an empty diff when `$CI` is set and the base resolves to the current
tree. The fix has two halves on purpose: dropping the variable from the
workflow again fails loudly instead of going quietly green.

**Zero mutants is a failure, not a pass.** `0 undetected out of 0` reads as
100%. It happens when every mutable construct in a changed file is excluded, and
it also happens if mutation_test's `Found N mutations` wording ever moves, since
that string is scraped. `FILEFIN_MUTANTS_ALLOW_ZERO=1` accepts it for a genuinely
declaration-only diff, and the commit message has to say which cause it was.

Two properties of the tool drove the design and were verified against the
pinned 1.7.1 rather than assumed:

1. **It rewrites source files in place** and restores them afterwards. Nothing
   else may read those files while it runs, so `mutants` is last in
   `just check` and out of the pre-commit hook entirely.
2. **It exits 255** when the threshold is missed, not 1.

The threshold is 100%. A diff-scoped gate asks about the handful of mutants
this commit adds, so anything less means "some of them may survive".

**The builtin rules do not mutate a strict comparison.** They rewrite `<=` and
`>=` (to `==` and to the strict form) but have no rule for a bare `<` or `>`, so
until M1.9 the off-by-one at a boundary — the bug §3 cites mutation testing for
— was invisible in this tree. Measured on `decide()`: with every
equal-to-threshold assertion removed, `>` could be changed to `>=` and the suite
passed, while the gate still reported 6 of 6 killed. `mutation_rules.xml` now
adds two regex rules that require whitespace on **both** sides of the operator,
which is what keeps them off `List<bool>`, `Map<String, int>`, `=>`, `<=` and
`>=`.

Every exclusion in `mutation_rules.xml` carries a reason **and a retirement
condition**, because an exclusion is a piece of code the gate has stopped
asking about. The two the new rules made necessary are excluded by their
**exact text** rather than by line number, so an edit elsewhere cannot widen the
exclusion and a change of shape simply stops matching.

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
non-zero `continueIndex`, both playback branches, and — for
`resume_vectors.json` — the full grid, all three `Refs` branches, and at least
one stale-ref vector.

Those named assertions cover about twenty fields; the payloads carry hundreds.
So there is a third half: `test/fixtures/KEYS.txt` records **every** JSON path
ever captured, and behaves like the constitution ratchet. `accept` may add keys
— §8 says a server upgrade that adds a field must not break us — and refuses to
drop one. Without it, deleting thirteen keys and re-running `accept` left a
gutted payload passing both other halves, because `accept` regenerated the only
thing that would have noticed.

`PROVENANCE.md` is inside the manifest, not exempt from it: the record of how a
fixture was produced is part of the fixture set. All three halves were proven to
fail independently.

---

## The integration harness (`just it`, M2)

**It is in `check-all`, not `check`, and that is deliberate.** CI has no
`filefin` binary, so `check` would be permanently red. `check-all: check it` is
local-only, which makes M2's definition of done "`just check` exits 0 **and**
`just it` exits 0 on a machine with the binary" — an amendment to CLAUDE.md's
DoD item 1.

`tool/run-integration.sh` **fails** on: a missing or non-executable binary, a
missing `ffmpeg`, zero `*_test.dart`, and any test marked skippable. It
auto-seeds one thing only — a missing data directory — because seeding is
recoverable and deterministic while a missing binary is neither.

Server control is Dart rather than shell because the restart happens *in the
middle of a test*.

### Three upstream facts the harness depends on

Verified in the source at v0.20.3. Get any of them wrong and it fails in a way
that looks like a client bug.

| Fact | Where | Consequence |
|---|---|---|
| **`--port` is IGNORED once a config exists** | `bootstrapServe`, `cmd/filefin/main.go:85` returns early on `config.Exists()` and only *warns* about a differing `--port` | the copied config's `port` must be rewritten; passing a flag silently collides every suite on 8099 |
| **the config is `$HOME/.filefin.json`, `dataDir` absolute** | `internal/config/config.go:201` | `HOME` points at the copy and `dataDir` is repointed at it |
| **the SQLite cache is under `os.UserCacheDir()`** | `internal/db/db.go:18` | it is *not* in the data dir; `cache.db-wal` and `-shm` must travel with `cache.db` (WAL mode — without the `-wal` the library comes back empty) |

**Seed once, copy per suite.** Seeding is three ffmpeg encodes plus a cache
rebuild; a copy of the 4.2 MB result with two rewritten fields starts in about a
second. The whole run is 4 seconds. A suite slow enough to skip is worse than
none.

**Readiness is not "any 200."** The SPA catch-all answers 200 for anything and a
half-started server can too, so the poll requires `200` **and**
`application/json` **and** a `version` field — the same three facts F1 uses — and
**throws** on a 10s deadline with the last 40 log lines.

The rate-limit suite gets its **own** server and run directory: five bad logins
lock the account for fifteen minutes and the limiter is in-memory, so sharing an
instance would 429 every later suite.

---

## Open questions

- **Q1 — state management for the app layer.** Deliberately deferred to M3, so
  it is chosen against real screens rather than in the abstract (SPEC.md §6,
  §13 "Still open"). Not a blocker before then. The decision lands here.
