#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Duplication gate.
#
# CLAUDE.md required M0 to evaluate jscpd for Dart and either add the gate or
# record why not. It was evaluated: jscpd 4 ships a Dart tokenizer (one of 224
# formats), and on a synthetic pair of near-identical Dart classes it reported
# 42.86% duplicated lines and exited 1. It works, so the gate exists.
# docs/architecture.md records the evaluation and the thresholds.
#
# jscpd is pinned to an exact version. A detector whose defaults move between
# patch releases turns "duplication rose" into "the tool changed its mind".
#
# Node is REQUIRED, not optional. A missing node fails this gate loudly rather
# than skipping it — a skipped duplication check that reports success is the
# gate-that-cannot-fail problem wearing a different hat.

JSCPD_VERSION="${FILEFIN_JSCPD_VERSION:-4.0.5}"
THRESHOLD="${FILEFIN_DUPES_THRESHOLD:-5}"
MIN_LINES=15
MIN_TOKENS=50

if [ -z "$(dart_sources)" ]; then
    echo "dupes: no Dart sources in the tree yet — nothing to compare (M0 only)"
    exit 0
fi

command -v npx >/dev/null 2>&1 || fail "npx is not on PATH — the duplication gate needs Node.
       Install Node, or state in docs/architecture.md why this gate was dropped.
       Skipping it silently is not an option."

roots=()
for root in packages apps; do
    [ -d "$root" ] && roots+=("$root")
done

npx --yes "jscpd@$JSCPD_VERSION" \
    --format dart \
    --pattern '**/*.dart' \
    --ignore '**/*.g.dart,**/*.freezed.dart,**/.dart_tool/**,**/build/**' \
    --min-lines "$MIN_LINES" \
    --min-tokens "$MIN_TOKENS" \
    --threshold "$THRESHOLD" \
    --reporters console \
    --silent \
    "${roots[@]}"

echo "dupes: below the ${THRESHOLD}% threshold (min ${MIN_LINES} lines / ${MIN_TOKENS} tokens)"
