#!/usr/bin/env nu

# Create the Android release signing key and put it in 1Password, once.
#
# WHAT MAKES THIS WORTH AUTOMATING is not the keystroke count, it is the order.
# Done by hand the sequence is: generate a key, invent two passwords, remember
# them long enough to type them into 1Password, attach the file, delete the
# local copy. Every step in the middle is a chance to leave a password in shell
# history or to delete the only copy of a key that never reached the vault.
# Here the passwords are generated, used, stored, and never printed, and the
# local keystore is deleted ONLY after a byte-for-byte round trip out of
# 1Password has proved the stored copy is real.
#
# THIS REFUSES TO RUN TWICE. A second signing key is not a mistake you notice:
# builds keep succeeding, and every install made with the first key can never
# be upgraded again. An existing item is a hard stop, not a prompt.
#
# Passwords are handed to keytool through `-storepass:env`, never as an
# argument — an argument is visible in `ps` for as long as the process lives.

def main [
    --title: string = "FileFin Android signing"  # 1Password item title
    --vault: string = "Private"                  # vault to create it in
    --alias: string = "filefin"                  # key alias inside the keystore
    --days: int = 10000                          # validity; Play needs past 2033-10-22
] {
    let file = "filefin-release.jks"

    for tool in [op keytool] {
        if (which $tool | is-empty) {
            error make {msg: $"($tool) is not installed — see docs/release-signing.md"}
        }
    }

    # THE GUARD THAT MATTERS. `op item get` exits non-zero when nothing
    # matches, which is the only reliable "does this exist" this CLI offers.
    if (^op item get $title --vault $vault | complete).exit_code == 0 {
        error make {msg: $"'($title)' already exists in ($vault). A second signing key would strand every install made with the first — delete the item deliberately if you really mean to replace it."}
    }

    # Generated here and never displayed. 40 alphanumerics is ~206 bits, which
    # is past the point where the keystore's own KDF is the weaker half.
    let store_pw = (random chars --length 40)
    let key_pw = (random chars --length 40)

    let work = (mktemp --directory --tmpdir)
    chmod 700 $work
    let jks = $"($work)/($file)"

    print $"creating the keystore at ($jks)"
    # An argument LIST rather than a multi-line invocation, because nushell
    # ends an external command at the newline and would read the second line as
    # a fresh expression.
    let gen_args = [
        "-genkeypair"
        "-keystore" $jks
        "-storetype" "PKCS12"
        "-keyalg" "RSA" "-keysize" "4096"
        "-validity" ($days | into string)
        "-alias" $alias
        "-dname" "CN=FileFin, OU=FileFin client, O=FileFin"
        # `:env`, never a bare `-storepass <value>`: an argument is visible in
        # `ps` to anyone on the machine for as long as the process lives.
        "-storepass:env" "FF_STORE_PW"
        "-keypass:env" "FF_KEY_PW"
    ]
    let gen = (
        with-env {FF_STORE_PW: $store_pw, FF_KEY_PW: $key_pw} {
            ^keytool ...$gen_args | complete
        }
    )
    if $gen.exit_code != 0 {
        rm -rf $work
        error make {msg: $"keytool failed: ($gen.stderr)"}
    }

    let local_hash = (open --raw $jks | hash sha256)

    print $"storing it in 1Password as '($title)'"
    # The file and both passwords go up in ONE call: an item created first and
    # attached to second is an item that can exist without its key.
    let create_args = [
        "item" "create"
        "--category" "Secure Note"
        "--title" $title
        "--vault" $vault
        $"store password[password]=($store_pw)"
        $"key password[password]=($key_pw)"
        $"key alias[text]=($alias)"
        $"($file)[file]=($jks)"
    ]
    let created = (^op ...$create_args | complete)
    if $created.exit_code != 0 {
        rm -rf $work
        error make {msg: $"op item create failed, and the keystore was discarded rather than left on disk without its passwords: ($created.stderr)"}
    }

    # THE ROUND TRIP IS THE POINT. Deleting the local copy on the strength of a
    # zero exit code trusts that the upload contained the bytes; this proves it,
    # and a mismatch keeps the local keystore so nothing is lost.
    print "verifying the stored copy before deleting the local one"
    let back = $"($work)/roundtrip.jks"
    let read = (^op read $"op://($vault)/($title)/($file)" --out-file $back | complete)
    if $read.exit_code != 0 {
        error make {msg: $"could not read the key back. The local copy is KEPT at ($jks): ($read.stderr)"}
    }
    if (open --raw $back | hash sha256) != $local_hash {
        error make {msg: $"the stored key does not match what was generated. The local copy is KEPT at ($jks)."}
    }

    # The fingerprint is public — it is in every APK this key signs — so it is
    # the one thing here that is safe to print, and it is worth recording.
    let list_args = [
        "-list" "-v" "-keystore" $jks "-alias" $alias
        "-storepass:env" "FF_STORE_PW"
    ]
    let fingerprint = (
        with-env {FF_STORE_PW: $store_pw} { ^keytool ...$list_args }
        | lines
        | where {|l| $l =~ "SHA256:"}
        | first
        | str trim
    )

    rm -rf $work

    print ""
    print $"stored in 1Password: ($vault) / ($title)"
    print $"  alias       ($alias)"
    print $"  ($fingerprint)"
    print "  the local keystore has been deleted; 1Password holds the only copy"
    print ""
    print "next: `just release-apk`"
    print "Play App Signing: upload THIS key at enrolment, or sideloaded installs"
    print "can never be upgraded through the store (docs/release-signing.md)."
}
