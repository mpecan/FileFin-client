#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# `just release-apk`: a signed release build whose key lives only in 1Password.
#
# THE KEYSTORE IS THE ONE THING THAT MUST TOUCH DISK. Android's signing config
# takes a `File`; there is no stream API and no way to hand it bytes. So the
# .jks is fetched into a 0700 temp directory, used, and removed — and the
# passwords never land at all, because `op run` injects them into the
# environment of exactly one command.
#
# WHY A TRAP AND NOT A TRAILING `rm`. A trailing `rm` runs when the build
# succeeds. A build that fails, is Ctrl-C'd, or is killed by a timeout is
# precisely when a key gets left behind, and that is the shape CLAUDE.md
# already records for mutation runs leaving mutants on disk. EXIT covers the
# ordinary and failing paths; INT and TERM cover the rest.
#
# WHAT THIS CANNOT DO. `rm` on APFS unlinks, it does not erase. The window is
# the length of one build and the directory is unreadable by other users, which
# is the honest bound — if that is not enough, point TMPDIR at a RAM disk.

OP_TITLE="${FILEFIN_OP_TITLE:-FileFin Android signing}"
OP_VAULT="${FILEFIN_OP_VAULT:-Private}"
ROOT="$(pwd)"
ENV_FILE="$ROOT/tool/signing.env"
# `flutter build` is run from the APP, not from the workspace root: the root
# pubspec is the workspace and has no `lib/main.dart`, so a build launched
# there fails with "Target file not found" long after the key has been fetched.
APP_DIR="$ROOT/apps/mobile"

fail() { printf '\033[31mrelease-apk: %s\033[0m\n' "$*" >&2; exit 1; }
say()  { printf '\033[36mrelease-apk:\033[0m %s\n' "$*" >&2; }

command -v op >/dev/null 2>&1 ||
    fail "the 1Password CLI (op) is not installed — see docs/release-signing.md"
command -v jq >/dev/null 2>&1 ||
    fail "jq is not installed; it is how the keystore's vault reference is read"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE is missing; it names the vault entries"

# THE REFERENCE IS ASKED FOR, NOT CONSTRUCTED.
#
# `op`'s assignment syntax reads a dot as a section separator, so uploading
# `filefin-release.jks[file]=…` produces a SECTION called `filefin-release`
# holding a field called `jks` — the file is stored perfectly and the obvious
# `…/filefin-release.jks` reference resolves to nothing. That is measured, not
# hypothetical: it is what the first real run of `just new-signing-key` did,
# after four stubbed tests agreed with a guess about the CLI instead of asking
# it. Reading the location out of the item works whichever way it was stored,
# and keeps working if the file is ever re-uploaded under another name.
#
# FILEFIN_OP_ITEM still overrides, for a key kept somewhere else entirely.
resolve_reference() {
    local json section name
    json="$(op item get "$OP_TITLE" --vault "$OP_VAULT" --format json)" ||
        fail "no 1Password item '$OP_VAULT/$OP_TITLE' — run \`just new-signing-key\` first"
    [ "$(printf '%s' "$json" | jq '.files | length')" -eq 1 ] ||
        fail "'$OP_TITLE' holds $(printf '%s' "$json" | jq '.files | length') files; it must hold exactly the keystore"
    section="$(printf '%s' "$json" | jq -r '.files[0].section.label // ""')"
    name="$(printf '%s' "$json" | jq -r '.files[0].name')"
    if [ -n "$section" ]; then
        printf 'op://%s/%s/%s/%s' "$OP_VAULT" "$OP_TITLE" "$section" "$name"
    else
        printf 'op://%s/%s/%s' "$OP_VAULT" "$OP_TITLE" "$name"
    fi
}

OP_ITEM="${FILEFIN_OP_ITEM:-$(resolve_reference)}"

# A 0700 directory under TMPDIR, created by mktemp so the name is unguessable.
work="$(mktemp -d)"
chmod 700 "$work"
cleanup() {
    local status=$?
    rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT INT TERM

export FILEFIN_STORE_FILE="$work/filefin-release.jks"

say "fetching the keystore from $OP_ITEM"
# `op read` prompts for whatever the account requires — biometric, or a session
# — and writes the file itself, so the bytes never pass through a shell
# variable or a here-doc.
op read "$OP_ITEM" --out-file "$FILEFIN_STORE_FILE" >/dev/null ||
    fail "could not read $OP_ITEM — check the item name and that you are signed in"
[ -s "$FILEFIN_STORE_FILE" ] || fail "1Password returned an empty keystore"

say "building, with the passwords injected for this command only"
(cd "$APP_DIR" && op run --env-file="$ENV_FILE" --no-masking -- \
    flutter build apk --release "$@") ||
    fail "the build failed — the keystore has been removed either way"

apk="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$apk" ] ||
    apk="$(find "$APP_DIR/build/app/outputs/flutter-apk" -name '*-release.apk' | sort | head -1)"
[ -f "$apk" ] || fail "the build reported success but produced no release APK"

# THE SIGNATURE IS ASSERTED, NOT ASSUMED. The whole reason this script exists
# is that a debug-signed artefact installs and runs and says nothing, so a
# release build that reports success without naming the certificate it used
# would leave exactly the hole it was written to close.
signer="$(find "${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools" \
    -name apksigner -maxdepth 2 2>/dev/null | sort | tail -1)"
[ -n "$signer" ] || fail "apksigner not found — cannot verify what signed the APK"

certs="$("$signer" verify --print-certs "$apk")" ||
    fail "apksigner refused $apk — it is not validly signed"
printf '%s\n' "$certs" | grep -q 'CN=Android Debug' &&
    fail "the APK is DEBUG-signed — the environment did not reach gradle"

say "$(printf '%s' "$certs" | grep -m1 'certificate DN')"
say "signed: $apk"
