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

OP_ITEM="${FILEFIN_OP_ITEM:-op://Private/FileFin Android signing/filefin-release.jks}"
ENV_FILE="tool/signing.env"

fail() { printf '\033[31mrelease-apk: %s\033[0m\n' "$*" >&2; exit 1; }
say()  { printf '\033[36mrelease-apk:\033[0m %s\n' "$*" >&2; }

command -v op >/dev/null 2>&1 ||
    fail "the 1Password CLI (op) is not installed — see docs/release-signing.md"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE is missing; it names the vault entries"

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

say "fetching the keystore from 1Password"
# `op read` prompts for whatever the account requires — biometric, or a session
# — and writes the file itself, so the bytes never pass through a shell
# variable or a here-doc.
op read "$OP_ITEM" --out-file "$FILEFIN_STORE_FILE" >/dev/null ||
    fail "could not read $OP_ITEM — check the item name and that you are signed in"
[ -s "$FILEFIN_STORE_FILE" ] || fail "1Password returned an empty keystore"

say "building, with the passwords injected for this command only"
op run --env-file="$ENV_FILE" --no-masking -- \
    flutter build apk --release "$@" ||
    fail "the build failed — the keystore has been removed either way"

apk="apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$apk" ] || apk="$(find apps/mobile/build/app/outputs/flutter-apk -name '*-release.apk' | head -1)"

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
