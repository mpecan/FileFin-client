# Release signing

Every Android install is bound to the certificate that signed it. Android will
not replace an installed app with a build signed by a different key — it
refuses the upgrade, and the only way through is to uninstall, which takes the
saved servers and everything in the Keystore with it.

So the key is not a build detail. It is the identity of the app, it is chosen
once, and losing it costs every installation that exists.

## Where the key lives

**In 1Password, and nowhere else at rest.** `just release-apk` is the only way
to produce a signed build:

1. `op read` fetches the keystore into a `mktemp -d` directory at mode 0700;
2. `op run --env-file=tool/signing.env` injects the two passwords and the alias
   into the environment of exactly one `flutter build`;
3. a trap on `EXIT INT TERM` removes the directory — on success, on failure,
   and on Ctrl-C;
4. `apksigner` is run against the artefact and the script **fails** if the
   certificate says `CN=Android Debug`.

There is no `key.properties`. `apps/mobile/android/app/build.gradle.kts` reads
`FILEFIN_STORE_FILE`, `FILEFIN_STORE_PASSWORD`, `FILEFIN_KEY_ALIAS` and
`FILEFIN_KEY_PASSWORD` from the environment, and a release build with any of
them unset **fails naming the ones that are missing**. It does not fall back to
the debug key — that fallback is the defect this replaces.

**The honest bound.** The keystore itself has to be a file for the length of
the build: Android's signing config takes a `File` and there is no stream API.
`rm` on APFS unlinks rather than erases, so the guarantee is "not at rest, in a
directory no other user can read, for one build" — not "never written". Point
`TMPDIR` at a RAM disk if that is not enough.

## Creating it, once

```
just new-signing-key
```

That is the whole of it. The script generates a 4096-bit RSA key valid for
10 000 days, generates both passwords, stores key and passwords in 1Password as
**FileFin Android signing** in the **Private** vault, reads the stored keystore
back and compares it byte-for-byte with what it generated, and only then
deletes the local copy. It prints the certificate fingerprint and nothing else
— no password is ever displayed, logged, or written to a file.

`--title`, `--vault`, `--alias` and `--days` override the defaults. If you move
the item, set `FILEFIN_OP_ITEM` to its full `op://` path so `just release-apk`
can still find it.

Three properties are worth knowing about, because each is a decision rather
than an implementation detail:

- **It refuses to run twice.** An existing item is a hard stop. A second
  signing key is not a mistake anyone notices — builds keep succeeding, and
  every install made with the first key can never be upgraded again.
- **Passwords reach `keytool` through `-storepass:env`**, never as an argument.
  An argument is visible in `ps` to anyone on the machine for as long as the
  process lives.
- **The local keystore is deleted only after the round trip.** Trusting a zero
  exit code from `op item create` trusts that the upload contained the bytes; a
  hash comparison proves it. If the comparison fails the local copy is kept and
  the path is printed, so a bad upload costs a retry rather than the key.

Why `-validity 10000` (~27 years): Play refuses a key expiring before
22 October 2033, and an expired key strands every install signed with it.
PKCS12 rather than JKS because JKS is the obsolete format and `keytool` warns
on every use of it.

## Backing it up

1Password is the backup, provided the account itself is recoverable: keep the
Emergency Kit somewhere offline. There is no other recovery path. A lost key
means a new application id and every user reinstalling from scratch.

## Verifying any APK

```sh
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs app-release.apk
```

`CN=Android Debug` means the key never reached gradle. That was the state this
document was written to end: the artefact installed, ran, and carried the debug
identity, and nothing in the build output said so. `just release-apk` now makes
that assertion itself, so the check is run whether or not anyone remembers to.

## Guards, and how each was proven

| Guard | Proven by |
|---|---|
| release build with no signing env fails | run; names all four variables |
| release build with a *partial* env fails | run with only `FILEFIN_KEY_ALIAS`; names the other three |
| debug build needs none of it | run; `app-debug.apk` built |
| a debug-signed APK is caught | run against the last debug artefact; detected |
| a staged keystore or `key.properties` fails `just constitution` | run; `tracked_secrets` reported both, and passed once unstaged |
| `just new-signing-key` refuses when the item exists | run against a stubbed `op`; refused |
| it keeps the local key when the round trip disagrees | run with a stub returning wrong bytes; kept, path printed |
| it deletes the local key when the round trip agrees | run against a stub; temp directory gone |
| it refuses when `op` is absent | run with a stripped PATH; refused |

The four `new-signing-key` rows were proven against a **stubbed** `op`, not
against the real vault: proving a script works is not a reason to write test
items into somebody's password manager.

## If this ever goes to Play

**Yes, this is the key you would use — but only if you say so at enrolment,
and the moment to decide is before anyone installs a sideloaded build.**

Play splits the identity in two:

- the **app signing key**, which signs what devices actually verify;
- the **upload key**, which you sign uploads with. Google checks it, strips it,
  and re-signs with the app signing key.

New apps are enrolled in Play App Signing and upload an AAB rather than an APK.
At enrolment there is a choice, and it is the one that matters here:

- **Let Google generate the app signing key.** Anyone holding a sideloaded APK
  signed with this key then cannot be upgraded by Play — different certificate,
  refused install. They uninstall and start over, losing their data.
- **Upload this key as the app signing key.** Sideloaded and Play builds carry
  one identity and upgrade cleanly.

Google keeps the key either way and will not export it back, so the second
option is a one-way door — worth taking anyway if sideloaded installs exist,
because the alternative is asking every one of those users to wipe the app.

The upload key can be this same keystore or a separate one; unlike the app
signing key, an upload key can be rotated by asking Play support.

**Practical consequence today:** everything built before this was signed with
the debug key, so the first release-signed build will not install over it.
Uninstall the app on any device carrying one — including the phone and the
television this repository has been pushed to — before installing the new
artefact.
