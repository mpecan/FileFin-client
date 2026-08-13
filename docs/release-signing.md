# Release signing

Every Android install is bound to the certificate that signed it. Android will
not replace an installed app with a build signed by a different key — it
refuses the upgrade, and the only way through is to uninstall, which takes the
saved servers and everything in the Keystore with it.

So the key is not a build detail. It is the identity of the app, it is chosen
once, and losing it costs every installation that exists.

## Creating it

`keytool` prompts for a password, so run it yourself:

```sh
keytool -genkeypair -v \
  -keystore ~/keys/filefin-release.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias filefin
```

- **Not inside the repository.** `~/keys/` or anywhere else outside the tree.
  It is gitignored twice over and `just constitution`'s `tracked_secrets` rule
  fails on a staged one, but the file that cannot be committed by accident is
  the one that is not there.
- **`-validity 10000`** is about 27 years. Play requires a key valid past
  22 October 2033 and refuses anything shorter, and a key that expires is a key
  that strands every install signed with it.
- **PKCS12**, because JKS is the obsolete format and `keytool` warns about it
  on every use.

Then `android/key.properties`, which is gitignored:

```properties
storeFile=/Users/you/keys/filefin-release.jks
storePassword=…
keyAlias=filefin
keyPassword=…
```

`storeFile` is resolved from `apps/mobile/android/app`, so an absolute path is
the one that behaves.

## Backing it up

Back up the `.jks` and both passwords somewhere that survives this laptop — a
password manager holds both halves and is the least ceremonious option that
works. There is no recovery path. A lost key means a new application id and
every user reinstalling from scratch.

## Verifying a build

```sh
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs app-release.apk
```

`CN=Android Debug` means the keystore was not picked up. That was the state
this document was written to end: the artefact installed, ran, and carried the
debug identity, and nothing in the build output said so.

A release build with no `key.properties` now fails rather than falling back —
see the guard at the bottom of `apps/mobile/android/app/build.gradle.kts`.
Debug builds and `flutter run` do not need the file.

## If this ever goes to Play

**Yes, this is the key you would use — but only if you say so at enrolment,
and the moment to decide is before anyone installs a sideloaded build.**

Play separates two keys:

- the **app signing key**, which signs what users' devices actually receive and
  verify;
- the **upload key**, which is what you sign uploads with. Google checks it,
  strips it, and re-signs with the app signing key.

New apps are enrolled in Play App Signing and upload an AAB rather than an APK.
At enrolment there is a choice, and it is the one that matters here:

- **Let Google generate the app signing key.** Then anyone holding a sideloaded
  APK signed with this key cannot be upgraded by Play — different certificate,
  refused install. They uninstall and start over, losing their data.
- **Upload this key as the app signing key.** Then the sideloaded builds and
  the Play builds carry the same identity and upgrade cleanly in both
  directions.

Google keeps the key either way and will not export it back to you, so the
second option is a one-way door — worth taking anyway if sideloaded installs
exist, because the alternative is asking every one of those users to wipe their
app.

The upload key can be this same keystore too, or a separate one rotated later;
unlike the app signing key, an upload key can be replaced by asking Play
support.

**Practical consequence today:** builds before this document were signed with
the debug key, so the first release-signed build will not install over them.
Uninstall the existing app on any device carrying one — including the phone and
the television this repository has been pushed to — before installing the new
artefact.
