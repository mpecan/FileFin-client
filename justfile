# === default ===
default:
    @just --list

# === quality gates ===
# The whole gate set, in the order a failure is cheapest to understand:
# toolchain first (a missing SDK must fail, never skip), then the hooks are
# actually installed, then the fast greps, then the things that run code.
#
# `mutants` is last on purpose: mutation_test rewrites sources in place while
# it runs, so it must never overlap another gate reading the same files. just
# runs dependencies sequentially, which is what keeps that true.
check: toolchain-check hooks-status fmt-check analyze codegen-check file-size comments constitution dupes deps fixtures-verify test coverage-check mutants

# `just it` (integration tests against a real server) joins here at M2. It does
# not exist yet: there is no integration suite, and a recipe over zero tests
# reports success — the gate-that-cannot-fail problem (CLAUDE.md).
check-all: check

# === toolchain ===
toolchain-check:
    @bash tool/check-toolchain.sh

# === formatting ===
fmt:
    dart format .

fmt-check:
    dart format --output=none --set-exit-if-changed .

# === analysis ===
# --fatal-infos is load-bearing: very_good_analysis reports most of its rules
# at info severity, so without it `analyze` would pass on nearly every lint.
analyze:
    dart analyze --fatal-infos --fatal-warnings .

# === codegen (CLAUDE.md §10) ===
codegen-check:
    @bash tool/check-codegen.sh

# Regenerate *.g.dart / *.freezed.dart in place. `codegen-check` runs the same
# builders and then fails on any diff (§10), so this is the recipe you run after
# changing a model and before committing.
codegen:
    @bash tool/run-codegen.sh

# === tests ===
test:
    @bash tool/run-tests.sh

# === file size ===
file-size:
    @bash tool/check-file-sizes.sh

# === comment budget (CLAUDE.md §2) ===
comments:
    @bash tool/check-comment-budget.sh

# === duplication ===
# Evaluated in M0 rather than assumed: jscpd 4 has a Dart tokenizer and was
# seen to fail on duplicated Dart. docs/architecture.md records the evaluation.
dupes:
    @bash tool/check-dupes.sh

# === constitutional debt ratchet ===
constitution:
    @bash tool/check-constitution.sh

# Lock in a reduction so it can never regress. Only writes counts that were
# actually measured; run it after paying debt, never to silence a new error.
constitution-accept:
    @bash tool/check-constitution.sh accept

# === dependencies (CLAUDE.md §4) ===
deps:
    @bash tool/check-deps.sh

# === coverage (CLAUDE.md §3) ===
coverage:
    @bash tool/run-coverage.sh

coverage-check: coverage
    @bash tool/coverage-gate.sh

# === mutation testing (CLAUDE.md §3) ===
# Diff-scoped against FILEFIN_MUTANTS_BASE (default HEAD): the working tree vs
# the last commit is what this commit is about to add. `FILEFIN_MUTANTS_BASE=HEAD~1
# just mutants` re-checks a commit that already landed.
mutants:
    @bash tool/check-mutants.sh

# === git hooks (CLAUDE.md §12) ===
install-hooks:
    @mkdir -p .git/hooks
    @for hook in pre-commit post-commit; do \
      ln -sf ../../tool/hooks/$hook .git/hooks/$hook && \
      test -x .git/hooks/$hook && echo "$hook hook installed and executable"; \
    done

# Fails rather than warns: an uninstalled hook gates nothing and stays silent
# about it, which is exactly the failure mode `check` exists to catch.
hooks-status:
    @bash tool/check-hooks-status.sh

# === fixtures (CLAUDE.md §8) ===
# `fixtures-seed` and `fixtures-capture` need the real filefin binary and are
# not part of `check`, which must run in CI where no server exists.
# `fixtures-verify` reads only committed files, so it IS in `check`: it checks
# the fixtures against a committed SHA-256 manifest and asserts they still
# exercise the shapes the models depend on. A fixture edited to make a failing
# test pass is a hand-written literal wearing a captured payload's name.
fixtures-seed:
    @bash tool/testserver/seed.sh

fixtures-capture:
    @bash tool/testserver/capture_fixtures.sh

# The resume oracle. NOT part of `fixtures-capture`: these vectors do not come
# from HTTP at all — tool/fixtures/capture_state_vectors_test.go is copied into
# a clone of upstream at v0.20.3 and runs internal/state.Apply/.View directly.
# Needs Go and (unless FILEFIN_UPSTREAM_CLONE points at one) network.
fixtures-vectors:
    @bash tool/capture-resume-vectors.sh

fixtures-verify:
    @bash tool/check-fixtures.sh

# Regenerate the manifest after a real re-capture. Never to silence a diff.
fixtures-accept:
    @bash tool/check-fixtures.sh accept
