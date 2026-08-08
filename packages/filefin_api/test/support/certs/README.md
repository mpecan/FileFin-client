# Two throwaway self-signed certificates

`server_a` and `server_b` exist so F15 can be tested against a **real TLS
handshake**: one Dart `HttpServer.bindSecure` serving `a`, another serving `b`,
and a pin that must accept the first and block the second.

They are needed because **the `filefin` binary has no TLS listener at all** —
no `ListenAndServeTLS`, no certificate flag anywhere in `internal/` or `cmd/`,
verified at v0.20.3. TLS is a reverse-proxy concern upstream. So SPEC.md §10's
M2 exit criterion ("a self-signed server connects only after explicit accept")
is satisfied against a Dart TLS server: a real handshake, just not a real
FileFin. `STATE.md` and `docs/risks.md` record that.

## Committing a private key here is not a §9 violation

§9 governs **user** credentials — a password, a session cookie, a certificate
pin the user accepted. These two keys guard nothing, were generated for this
repository, are never used by anything but `certificate_pinner_test.dart`, and
are as public as the rest of the tree. Deleting them does not improve security;
it deletes the only evidence that F15 blocks anything.

## How they were generated

```sh
for n in a b; do
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "server_$n.key" -out "server_$n.crt" \
    -days 36500 -subj "/CN=filefin-test-$n" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
done
```

Two flags are not optional and each costs an afternoon when missed:

- **`subjectAltName` must carry `IP:127.0.0.1` *and* `DNS:localhost`.** A
  modern TLS stack ignores `CN` for hostname verification. Without the SAN the
  handshake fails on a hostname mismatch, which arrives at
  `badCertificateCallback` looking exactly like a pin failure — so the test
  would pass for the wrong reason.
- **`-days 36500`.** A certificate that expires turns a green suite red years
  later for a reason unrelated to anything anyone changed, and the failure
  reads as a pinning bug.

## Their fingerprints

The same lowercase colon-hex `CertificateFingerprint` produces, so what a user
compares by eye is what the tests compare:

```
server_a  ca:d8:55:4b:04:42:4a:95:c0:ff:95:96:66:7e:bb:87:8d:a9:54:50:97:99:02:a1:30:9d:09:e3:4d:8b:5a:11
server_b  e7:3a:ca:51:9a:bb:91:a2:11:ad:21:5b:44:fc:32:2c:b5:7e:f7:f4:4c:08:28:fb:a9:8b:b6:ff:20:10:d5:62
```

The tests do not hard-code these. They compute the expected value from the
`.crt` on disk, so regenerating the pair is a one-command operation rather than
a hunt through assertions — and `openssl x509 -fingerprint -sha256` above is
what proves our digest agrees with the tool a user would reach for.
