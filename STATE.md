# State

Where the project is, milestone by milestone, and what it knowingly owes.

| | |
|---|---|
| **Done** | **M0** — workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture, R1 retired, R4 licensing position recorded, then remediated against three adversarial reviews |
| **In progress** | **M1** — `filefin_core`: models, extension-type IDs, URL building, resume engine, `decide()` |
| **Exit criterion met** | `just check` exits 0 on a clean tree; every gate has a both-directions proof below |

---

## M1 — what has been built

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

**Numbers as measured, not as hoped:** `just check` exits 0. Coverage
**100% (327/327 lines)**. **149 of 149** mutants killed across every lib source
M1 added (`FILEFIN_MUTANTS_BASE=ca00dd9`, the last M0 commit). **758 tests**,
of which 601 are captured resume vectors and 10 are property runs. `core_purity` 0, and the whole
constitution baseline is still 0 across all six checks.

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
  case. The cost is one case: crossing 90% of a single-file item whose pointer
  genuinely sits at `(0, 0s)` predicts `seconds = round(position)` where the
  server keeps `0`. The item is `watched` by then and has left every `continue`
  row, so nothing reads the difference. Recorded because "nothing reads it" is
  an argument, not a proof.
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

### Deferred by decision, not oversight

| Item | Decision | Where |
|---|---|---|
| **A2** — `ServerId` | Deferred to **M2**. CLAUDE.md §7 names it, but no consumer exists until multi-server lands, and §1 forbids building ahead of the milestone that needs it. `id_typedefs` already greps for it, so a typedef version cannot sneak in meanwhile. | M1.2 defines the other four |
| **A4** — `just it` | **Not created in M0.** There is no integration suite until M2, and a recipe over zero tests reports success. M0's exit criterion is `just check`, which does not include `it`. `check-all` is currently an alias for `check`. | M2 |
| **A5** — `mutants` / `coverage-check` on real code | Created and proven in M0 (synthetically for coverage, against a real scratch package for mutants); re-proven against `filefin_core` at **M1.9**. | above |
| **A9** — `progressIntervalSecs` | `PlaybackSettings` is `{wifiOnly, meteredWarnBytes}` only. The interval arrives at **M4** with the progress reporter; a settings field nobody reads is a dead branch (§5). | M4 |
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
