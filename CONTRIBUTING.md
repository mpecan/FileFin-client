# Contributing

This repository is stricter than most, on purpose, and the strictness is
mechanical rather than cultural: **every rule names the command that enforces
it.** A rule with no check is a rule that gets ignored, so if you find one here
that no gate holds, that is a bug in the rule.

`CLAUDE.md` is the constitution and the authority. This file is how to work
day to day.

## Setup

```sh
flutter pub get
just install-hooks     # `just check` fails without them, deliberately
just check             # must exit 0 before you start, so a failure later is yours
```

`just --list` is the index of everything you can run.

## The loop

1. **Write the failing test first.** Red, green, refactor. You are expected to
   have *seen* it fail — a test that has only ever passed proves nothing about
   what it is asserting.
2. Make it pass.
3. `just check`. The whole recipe, not the part you think is affected.
4. Commit. The pre-commit hook runs the fast gates and blocks on them.

Every bug fix adds a regression test, and it must fail against the bug.

## What the gates will tell you, before a reviewer does

**Comments explain the present.** A comment says what the code and the
signature cannot: why a non-obvious choice was made, what invariant holds, which
server quirk a workaround exists for. In the present tense, about what is there
now.

It does *not* explain history — no "used to", no "until M5.1", no record of
which milestone found what. And it carries **no references**: no `§9`, no `F13`,
no `D12`, no `media.go:227`. A reference can rot; no reference cannot. Where a
comment would have pointed, say the thing instead — not "§9 forbids it" but
"this must never be logged".

No comment block may exceed **12 lines**. A comment describing an interface is
bounded by that interface. Anything longer belongs in a document:

- **`docs/decisions/`** — a choice *we* made, and the alternative it rejected.
  Indexed by `SPEC.md` §13. Naming the rejected option is most of the value: the
  reason a decision gets relitigated is that the rejected one looks obvious to
  whoever arrives next.
- **`docs/field-notes.md`** — how the server, a dependency or the framework was
  *observed* to behave. Not our choice, so not a decision. Every entry names how
  it was measured; a fact with no measurement behind it is a belief.

**Tests are not decoration.** Coverage counts lines that ran; it cannot tell an
assertion from a tautology. So changed code must also survive mutation. If a
mutant survives, the honest reading is that no test objects to changing your
code — add the assertion. Exclude one only when it is genuinely equivalent, with
the reason and a retirement condition in `mutation_rules.xml`.

**The server contract is observed, not assumed.** Every endpoint we call is in
`docs/server-api.md` with the upstream file and line that proves its shape.
Models decode tolerantly: unknown fields ignored, anything not strictly needed
nullable with a default. A server upgrade that adds a field must not break us.
Every model round-trips a **captured real payload** — a hand-written JSON
literal that agrees with our own class proves only that we can spell our own
field names.

**Never log or persist a credential.** Passwords exist in transit and in the
platform secure store. Never in `SharedPreferences`, never in a log line, never
in a `toString()`.

**Don't build it until the milestone needs it.** No speculative classes, no
settings nobody reads, no error variants nothing constructs. Delete dead code
immediately; git remembers.

## Changing a gate

Gates are the load-bearing part of this repo, so changing one has its own rule:

**Prove both directions.** Construct an input that *must* fail, run the gate,
confirm a non-zero exit — then confirm the clean tree still passes. A gate
change is not done until you have seen it fail.

The failure modes worth knowing, because each has happened here: a `while read`
loop whose body runs in a subshell so the failure flag is discarded; piping a
count into a filter so the threshold is unreachable; a diff-scoped gate whose
base *is* the working tree, so CI measures nothing; an assertion satisfiable in
prose, where a check for `String toString(` matched the comment saying the class
deliberately has none. `CLAUDE.md` has the full list.

Debt is counted and may only ever fall. `just constitution-accept` locks in an
improvement; it refuses to write a raised baseline.

## The mutation gate

Two properties that are easy to get wrong:

- **It mutates a disposable worktree, never yours.** Interrupting it is free.
  This was not always true, and while it was untrue an interrupted run left a
  mutant behind four times — one of which `dart analyze` reported as "No issues
  found", because a negated numeric literal is perfectly good Dart.
- **It skips files whose diff is comments only**, because `mutation_test` never
  touches a comment, so those mutants would be the base's own.

For a large diff use `just mutants-parallel`. It shards across packages and
worktrees, needs a clean tree, and is safe to interrupt. It is **not** the
authority — `just mutants`, inside `just check`, is.

If a run reports undetected mutants, read the three numbers rather than the
first one: `survivors = undetected − timeouts − not covered`. A timeout means
nothing was measured, which is a different problem from a mutant nothing
objected to.

## Integration tests

`just it` runs against a **real `filefin` binary** the harness starts over a
seeded temp directory, because the interesting failures — byte-range behaviour,
the 307 to HLS, headers surviving that redirect, session loss on restart — are
exactly what a mock papers over.

It **fails** when the binary is absent rather than skipping. A skipped
integration suite that reports success is a gate that cannot fail wearing a
different hat. It is not in `just check`, because CI has no binary; it is in
`just check-all`, which is local-only.

## The application mark

The mark is drawn by `FileFinMarkPainter`, and the launcher icons are rendered
from that same painter rather than exported alongside it. If you touch the
geometry, run `just icons` and commit what it rewrites.

**Nothing enforces that.** `just check` does not re-render the icons, so a mark
changed without the recipe ships a stale home-screen icon while every test
stays green. The widget suites cover only the glyph inside the app.

## Commits

Conventional Commits: `type(scope): description`.

- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `perf`
- Scopes: `core`, `api`, `app`, `ui`, `player`, `build`

Stage explicit paths. **Never `git add -A`** — it sweeps in whatever else is in
the tree.

Commit only a green tree. `git commit --no-verify` exists for a broken hook or a
rollback that must land, not for getting past a failing gate.

Write the body for the reader who arrives in a year wondering why. If a change
fixes something subtle, say what it was and how you know.

## Anything you could not finish

Say so, out loud, in your summary and in `STATE.md`. Silence reads as "there was
none", and the whole point of the ratchet is that the number is honest.

## Licence

Contributions are made under [EUPL-1.2](LICENSE), the licence this project and
the FileFin server both use.
