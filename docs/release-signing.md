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

`keytool` prompts for passwords, so run it yourself:

```sh
mkdir -p ~/keys && keytool -genkeypair -v \
  -keystore ~/keys/filefin-release.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias filefin
```

- **`-validity 10000`** is about 27 years. Play refuses a key expiring before
  22 October 2033, and an expired key strands every install signed with it.
- **PKCS12**, because JKS is the obsolete format and `keytool` warns on every
  use of it.

Then put it in 1Password and delete the local copy:

```sh
op item create --category "Secure Note" --title "FileFin Android signing" \
  --vault Private \
  "store password[password]=…" \
  "key password[password]=…" \
  "key alias[text]=filefin" \
  filefin-release.jks=@$HOME/keys/filefin-release.jks

rm ~/keys/filefin-release.jks
```

The field names are the ones `tool/signing.env` references; change one and
change both. If the item lives in another vault or under another name, set
`FILEFIN_OP_ITEM` to its full `op://` path rather than editing the script.

`tool/signing.env` is **committed on purpose** — every value in it is an
`op://` reference, not a secret, and committing the references is what stops
the next person guessing which item the key is in.

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
