# Throwaway certificates for F15

Two self-signed pairs and one private-CA chain. They exist so F15 can be tested
against a **real TLS handshake**: a Dart `SecureServerSocket` serving one of
them, and a pin that must accept the right certificate and block every other.

They are needed because **the `filefin` binary has no TLS listener at all** —
no `ListenAndServeTLS`, no certificate flag anywhere in `internal/` or `cmd/`,
verified at v0.20.3. TLS is a reverse-proxy concern upstream. So SPEC.md §10's
M2 exit criterion ("a self-signed server connects only after explicit accept")
is satisfied against a Dart TLS server: a real handshake, just not a real
FileFin. `STATE.md` and `docs/risks.md` record that.

| File | What it is | Chain length |
|---|---|---|
| `server_a` | self-signed `filefin-test-a` | 1 |
| `server_b` | self-signed `filefin-test-b` | 1 |
| `ca` | the private CA `filefin-test-ca` | — |
| `server_c` | leaf `filefin-test-c`, issued by `ca`, full chain | 2 |
| `server_d` | leaf `filefin-test-impostor`, issued by the **same** `ca` | 2 |

## Why a two-certificate chain had to be added

**A self-signed-only fixture set is what hid an exploitable defect for a whole
milestone.** With one certificate the leaf *is* the root, so a client that
compares its pin against the wrong end of the chain passes every test.
`badCertificateCallback` is handed the certificate at which verification
failed, which on a real chain is the CA — so the M2 client showed the CA's
fingerprint in the trust-on-first-use prompt, stored a CA pin that admitted any
certificate that CA had ever issued, refused the server's own correct
fingerprint, and sent 106 bytes of request (session cookie included) to an
impostor before objecting. `server_c` and `server_d` are that chain, and
`server_d` is the impostor: same CA, different key.

A private CA is not an exotic case. It is what a reverse proxy in front of a
self-hosted server usually presents, which SPEC F15 names as the common
deployment.

## Committing private keys here is not a §9 violation

§9 governs **user** credentials — a password, a session cookie, a certificate
pin the user accepted. These keys guard nothing, were generated for this
repository, are never used by anything but `certificate_pinner_test.dart`, and
are as public as the rest of the tree. Deleting them does not improve security;
it deletes the only evidence that F15 blocks anything.

## How they were generated

```sh
# the two self-signed pairs
for n in a b; do
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "server_$n.key" -out "server_$n.crt" \
    -days 36500 -subj "/CN=filefin-test-$n" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
done

# the private CA
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
  -days 36500 -subj "/CN=filefin-test-ca" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# two leaves it signs; server_$n.crt is the FULL CHAIN, leaf first
for n in c d; do
  case $n in c) cn=filefin-test-c ;; d) cn=filefin-test-impostor ;; esac
  openssl req -newkey rsa:2048 -nodes -keyout "leaf_$n.key" \
    -out "leaf_$n.csr" -subj "/CN=$cn"
  openssl x509 -req -in "leaf_$n.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out "leaf_$n.crt" -days 36500 -copy_extensions copy \
    -extfile <(printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nbasicConstraints=critical,CA:FALSE\n')
  cat "leaf_$n.crt" ca.crt > "server_$n.crt"
  mv "leaf_$n.key" "server_$n.key"
  rm -f "leaf_$n.csr" "leaf_$n.crt"
done
rm -f ca.srl
```

Three flags are not optional and each costs an afternoon when missed:

- **`subjectAltName` must carry `IP:127.0.0.1` *and* `DNS:localhost`.** A
  modern TLS stack ignores `CN` for hostname verification. Without the SAN the
  handshake fails on a hostname mismatch, which arrives looking exactly like a
  pin failure — so the test would pass for the wrong reason.
- **`-days 36500`.** A certificate that expires turns a green suite red years
  later for a reason unrelated to anything anyone changed, and the failure
  reads as a pinning bug.
- **the leaf PEM must be concatenated *before* the CA.** `useCertificateChain`
  takes the file in wire order, and a chain served CA-first is not the chain a
  server sends. It would also make the fixture prove nothing, because the leaf
  would be where the old code already looked.

## Their fingerprints

The same lowercase colon-hex `CertificateFingerprint` produces, so what a user
compares by eye is what the tests compare. For `server_c` and `server_d` this
is the **leaf**, which is the first block in the file.

```
server_a  ca:d8:55:4b:04:42:4a:95:c0:ff:95:96:66:7e:bb:87:8d:a9:54:50:97:99:02:a1:30:9d:09:e3:4d:8b:5a:11
server_b  e7:3a:ca:51:9a:bb:91:a2:11:ad:21:5b:44:fc:32:2c:b5:7e:f7:f4:4c:08:28:fb:a9:8b:b6:ff:20:10:d5:62
ca        4c:b6:4e:b7:05:17:00:b3:f7:e1:72:ea:10:41:b7:f2:9d:52:b1:70:f6:0c:2b:d1:3a:eb:04:c9:d0:50:af:75
server_c  a5:fb:de:46:8a:2b:3e:23:58:35:8a:0d:2e:66:09:5e:1b:c7:97:af:d8:7f:9d:45:54:f8:ca:5d:7c:07:0f:36
server_d  b3:95:9e:27:60:39:ee:4e:f6:bb:f9:e2:2e:bc:09:83:ad:83:76:ed:f5:ba:5c:6d:7b:37:e1:41:56:0b:7b:80
```

The tests do not hard-code these. They compute the expected value from the
`.crt` on disk, so regenerating a pair is a one-command operation rather than a
hunt through assertions — and `openssl x509 -fingerprint -sha256` above is what
proves our digest agrees with the tool a user would reach for.
