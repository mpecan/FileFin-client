# Decisions

A choice we made, and what it cost. One file per decision that needs more than
a table row.

**The index is `SPEC.md` §13**, and it stays the index. Every decision has a row
there — number, one-line statement, rationale, what it touches — and that row is
what a reader scans. A decision whose argument does not fit in a row gets a file
here, and the row links to it. Nothing is recorded in both places.

## What belongs here

A decision is a choice **we** made between alternatives that were both
available. It has an alternative that was rejected, and naming that alternative
is most of the value: the reason a decision gets relitigated is that the
rejected option looks obvious to whoever arrives next.

What does **not** belong here:

- **How a dependency or the server behaves.** That is not our choice and we
  cannot reverse it. It goes in [`../field-notes.md`](../field-notes.md).
- **A rule.** `CLAUDE.md` holds the constitution; a rule with a gate behind it
  is a stipulation, not a decision.
- **What a function does.** That is the doc comment's job, and CLAUDE.md §2
  bounds it at twelve lines precisely so this directory exists.

## Why a file rather than a long comment

CLAUDE.md §2 caps a comment block at twelve lines, and `just comments` enforces
it. The cap is not a hostility to prose — the prose is the asset. It is about
where the prose can be **found**:

- a comment is found only by someone already reading that declaration, so a
  decision spanning four files is discoverable from whichever one they opened;
- a comment is not searchable by subject, only by the identifier it sits above;
- a comment has no retirement condition and no date, so nothing tells a reader
  whether it still holds;
- API documentation tools publish it, so seventy lines of archaeology becomes
  seventy lines of a caller's hover tooltip.

Measured at M8.R, before this directory existed: the tree was 37.9% comments,
of which 34.0% were `///` — and §2 reported "0 error(s), 0 warning(s)" because
it counted only `//`.

## Format

Keep it short. Four headings, and skip any that has nothing to say:

```markdown
# D12 — one-line statement of the decision

**Status:** accepted (M5) · **Touches:** `transport.dart`, F1
**Retires when:** <the condition, or "not expected to">

## Context
What forced a choice.

## Decision
What we do, in the present tense.

## Alternatives rejected
The one that looks obvious, and why it is not.

## Consequences
What this costs, and what now depends on it.
```

`Retires when` is the field most worth filling. A decision with no retirement
condition is one nobody will ever feel entitled to reverse.

## The code does not cite these

There is deliberately no `/// See D12.` anywhere. A citation is a reference, a
reference can rot, and a dangling one is worse than none — nothing checks that
`D12` still exists or still says what the comment claims. CLAUDE.md §2 is the
rule; a comment states the thing it needs to state, in the present tense, and
stops.

That makes this directory findable by reading it rather than by following a
pointer. It is small, the titles are full sentences, and `SPEC.md` §13 lists
every one. If a decision is hard to find from the code it constrains, the fix
is a clearer title here — not a pointer there.

## Adding one

1. Take the next free number from `SPEC.md` §13. Numbers are never reused.
2. Write `Dnn-short-slug.md` here.
3. Add the row to `SPEC.md` §13 linking to it.
