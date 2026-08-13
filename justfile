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

# `check` plus the integration suite. LOCAL ONLY, and deliberately so: `it`
# needs a real `filefin` binary and CI has none, so putting it in `check` would
# make CI permanently red. CI keeps running `just check`; M2's definition of
# done is "`just check` exits 0 AND `just it` exits 0 on a machine with the
# binary". STATE.md records the split.
check-all: check it

# === integration tests against a real server ===
# FAILS when the binary is absent rather than skipping — a skipped integration
# suite that reports success is the gate-that-cannot-fail problem wearing a
# different hat (CLAUDE.md). It also fails on zero test files and on any
# skippable test, and auto-seeds only the one precondition that is recoverable.
it:
    @bash tool/run-integration.sh

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

# Sharded across git worktrees, for a diff big enough that the serial gate
# stops being run at all. NOT in `check` and NOT the authority: `mutants` above
# is both. It exists because the same 859-mutant sweep is four hours serially
# and about one in parallel — and because it never writes to the working tree,
# where an interrupted serial run leaves a mutant behind.
mutants-parallel:
    @bash tool/run-mutants-parallel.sh

# === release ===
# Generates the key, stores it with both passwords in 1Password, verifies the
# stored copy byte-for-byte, then deletes the local one. Refuses if the item
# already exists — a second signing key strands every install made with the
# first. Run once, ever.
# Create the Android release signing key and put it in 1Password.
new-signing-key *ARGS:
    @nu tool/new-signing-key.nu {{ARGS}}

# The keystore is fetched from 1Password into a 0700 temp dir and removed on
# exit; the passwords are injected by `op run` for the length of one build.
# Refuses rather than falling back to the debug key, and asserts the
# certificate on the way out.
# Signed release APK, with the signing key never at rest on disk.
release-apk *ARGS:
    @bash tool/release-apk.sh {{ARGS}}

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
    @hooks=$(git rev-parse --git-path hooks); mkdir -p "$hooks"; \
    tree=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd -P); \
    for hook in pre-commit post-commit; do \
      ln -sf "$tree/tool/hooks/$hook" "$hooks/$hook" && \
      test -x "$hooks/$hook" && echo "$hook hook installed and executable"; \
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
