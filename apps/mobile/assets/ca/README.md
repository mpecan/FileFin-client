# The shipped CA roots

`cacert.pem` is Mozilla's set of trusted root certificates, as extracted and
distributed by the curl project. It is here because the libmpv we ship links
mbedTLS on both platforms and has no system trust store of its own — see
[`D24`](../../../../docs/decisions/D24-player-trust-store.md).

| | |
|---|---|
| Source | <https://curl.se/ca/cacert.pem> |
| Upstream data | Mozilla's `certdata.txt`, via `mk-ca-bundle.pl` |
| Licence | **MPL-2.0** — [`MPL-2.0.txt`](MPL-2.0.txt), also at <https://mozilla.org/MPL/2.0/> |

MPL-2.0 is a Compatible Licence in the EUPL's own Appendix, which is what lets
this sit inside an EUPL-1.2 application.

## Refreshing it

```sh
curl -O https://curl.se/ca/cacert.pem
curl -s https://curl.se/ca/cacert.pem.sha256   # compare before committing
```

The bundle goes stale: a root added after the last refresh is not trusted by
the player until someone updates this file. Check the digest — the file is a
trust store, and fetching one over a connection you have not verified is the
problem it exists to solve.
