# State

Where the project is, milestone by milestone, and what it knowingly owes.

| | |
|---|---|
| **Done** | **M0** — workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture, R1 retired, R4 licensing position recorded, then remediated against three adversarial reviews |
| **Done** | **M1** — `filefin_core`: wire models, extension-type IDs, URL building, the resume engine, `decide()`, then remediated against three adversarial reviews |
| **Done** | **M2** — `filefin_api`: the HTTP client, the cookie jar, F3's 401-retry, F15's certificate pinning, and `just it` against a real `filefin` |
| **Next** | **M3** — app shell and browsing UI |
| **Exit criterion met** | `just check` exits 0 **and** `just it` exits 0 on a clean tree, on a machine with the binary |

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

**Numbers as measured, not as hoped.** `just check` exits 0 on a clean tree
with **zero gate warnings**. `just it` exits 0: **19 integration tests in 4
seconds** against the real `filefin` v0.20.3 binary. Coverage **100%
(726/726)**; per package, `filefin_api` **100% (395/395)** and `filefin_core`
**100% (331/331)** — stated separately because `check-coverage.sh` reads one
concatenated lcov and its floor is a **tree-wide** ratio, so `filefin_core` at
100% over 331 lines would have masked a substantially untested `filefin_api`.
Across the whole milestone
(`FILEFIN_MUTANTS_BASE=7412862`, the last M1 commit): **138 of 138 mutants
killed** over `filefin_api`'s 17 changed lib sources, 0 timeouts, 6m05s.
`filefin_core`'s single M2 change — `ServerId` — produces **0 mutants** on the
same run, which is the declaration-only case the one use of
`FILEFIN_MUTANTS_ALLOW_ZERO=1` covers and which the gate correctly refuses to
call a pass. **884 tests** in all (112 in `filefin_api`, 772 in
`filefin_core`), plus the 19 integration tests, which `dart test` counts
separately because they are a separate suite. The constitution baseline is
still **0 across all six checks**.

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

### Debt this milestone knowingly accepts

- **`FILEFIN_MUTANTS_ALLOW_ZERO=1` was used on one commit** — M2.1, `ServerId`.
  The cause is the first of the two the gate names: a declaration-only diff.
  The entire non-doc addition to `lib/` is one line, an `extension type const`
  with no operator, literal or conditional. Verified by reading the diff.
- **There is no platform `SecretStore`.** F2's "platform secure store" is a port
  plus an in-memory implementation until M7. **Nothing at M2 proves a password
  survives an app restart** — the in-memory store is the production *cache*, and
  the persistence half does not exist yet.
- **F15's OS-trusted-certificate-change arm is enforced but unexercised.**
  Proving the wiring needs a CA-signed certificate for `127.0.0.1`. `decidePin`
  is pure and table-tested over every combination, which confines the gap to
  wiring rather than policy — but it is a gap. `docs/risks.md` R5.
- **The `filefin` binary has no TLS listener**, so SPEC §10's "self-signed
  server" half of M2's exit criterion is met against a Dart
  `HttpServer.bindSecure` with committed certificates. A real handshake, not a
  real FileFin. R5.
- **The coverage floor is tree-wide.** `check-coverage.sh` reads one
  concatenated lcov, so a well-covered package can mask a poorly covered one.
  Both figures are stated above and both are 100%. A **per-package floor is
  proposed, not smuggled in**: it is a larger gate change than M2 should make
  on its way past.
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
- **`filefin_api` has one `// ignore:` per gate-adjacent decision — three in
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
