# D18 — every route is one full string literal, never assembled from pieces

**Status:** accepted (M1) · **Touches:** `urls.dart`, `check-constitution.sh`, §8
**Retires when:** `undocumented_endpoint` learns to resolve interpolation.
Nothing plans to teach it.

## Context

`undocumented_endpoint` (`tool/check-constitution.sh`, §8) greps string literals
containing `/api/` and checks each against `docs/server-api.md`. It cannot
reconstruct a path assembled from parts.

## Decision

`ApiPaths` writes every route out in full, one literal each, even where that
repeats a prefix.

## Alternatives rejected

**Composing from a shared prefix** — `'$_media/hls/index.m3u8'`. It reads
better and it is invisible to the gate: correct on the day it is written, and
unchecked forever after.

## Consequences

The repetition in `ApiPaths` is what keeps every route answerable to the
document that cites its upstream line. It is a structural decision, not a
stylistic one, and tidying it away silently disables §8's enforcement.
