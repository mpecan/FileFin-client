# FileFin Client

A mobile and television client for [FileFin](https://github.com/xuedi/FileFin),
a filesystem-first self-hosted media server. Flutter and Dart, with playback by
`media_kit` (libmpv) so that MKV and HEVC play without asking the server to
transcode them.

**Not released.** Every milestone through M8 is built and every quality gate
passes, but nothing has shipped: there are no installs, no stored state worth
preserving, and no backward-compatibility guarantees. `STATE.md` is the
milestone-by-milestone record.

---

## What it does

- **Several saved servers**, each with its own credentials, cookie jar and
  certificate pin. Switch between them; forget one completely.
- **Browse** the category tree, a virtualised poster grid, and one item's
  detail — over a library that returns everything in one response, because the
  server has no pagination.
- **Search** across eleven scopes, with the scope actually sent on the wire.
- **Play** anything the server holds, direct or over HLS, with audio and
  subtitle tracks, resume, and progress reported back so watch state stays
  consistent with the web UI.
- **Survive a server restart.** Sessions live in the server's memory and die
  with the process, so a `401` is routine: the client renews and replays once,
  without a password prompt.
- **Trust a self-signed certificate deliberately**, once, with the fingerprint
  on screen — and refuse silently changed ones for ever after.
- **Phone and television**, one codebase, with every control reachable by four
  arrow keys and a centre button.

## Requirements

| | | |
|---|---|---|
| Flutter | 3.44+ | built and tested against 3.44.9 |
| Dart | **3.8 or newer** | enforced by `just toolchain-check` |
| [`just`](https://github.com/casey/just) | any | the task runner every workflow goes through |
| Node | any | `npx` only, for the duplication gate |

For the integration suite (`just it`) you also need a real `filefin` binary on
`PATH`, plus `ffmpeg` and `sqlite3`. For `just fixtures-vectors`, Go.

## Getting started

```sh
git clone <this repo> && cd FileFin-client
flutter pub get          # a pub workspace: resolves all three packages
just install-hooks       # pre-commit gates; `just check` refuses without them
just check               # everything below must exit 0
```

Then run it against a server:

```sh
cd apps/mobile && flutter run
```

The first screen asks for a server address. It will tell you plainly if what
answers is not a FileFin server — a `200` alone proves nothing, because this
server answers unmatched paths with its web UI.

## Layout

```
packages/filefin_core   pure Dart. Types, IDs, URL building, the resume engine
                        and the playback decision. No I/O, no Flutter, no clock.
packages/filefin_api    the HTTP client. Cookie jar, the 401 retry, certificate
                        pinning. The only layer that knows what a 401 means.
apps/mobile             the Flutter app: shell, browse, search, player, servers,
                        and the television variants.
tool/                   the quality gates, as shell. Roughly half the size of
                        the product, and deliberately so.
docs/                   the contract, the decisions, the measurements, the risks.
```

The dependency direction is enforced rather than agreed: `filefin_core` is
I/O-free and Flutter-free, and a gate fails if that stops being true.

## Quality gates

`just check` is the whole recipe, and "it compiles" is not on the list.

| gate | what it holds |
|---|---|
| `fmt-check` `analyze` | `very_good_analysis`, `--fatal-infos` |
| `codegen-check` | generated code is committed and regenerates byte-identically |
| `file-size` | 400 soft / 600 hard lines |
| `comments` | a 12-line cap on any comment block; 35/45% tree-wide |
| `constitution` | a ratcheting debt baseline that may only ever fall |
| `deps` | every dependency imported somewhere and justified in a comment |
| `dupes` | `jscpd`, 5% threshold |
| `fixtures-verify` | captured payloads match a checksum manifest |
| `test` | **1,987 tests** across three packages |
| `coverage-check` | **100%**, floor 50% |
| `mutants` | every mutant in the diff killed |

Current state: all green. Coverage is 100% of 4,440 executable lines, and the
denominator is defended — a source that produced no coverage record at all
fails the gate rather than vanishing from the ratio.

Two things worth knowing about the mutation gate: it mutates a **disposable
worktree**, never yours, so interrupting it is free; and it skips files whose
diff is comments only, because a comment generates no mutants.

## Documentation

| | |
|---|---|
| `CONTRIBUTING.md` | how to work in this repo, and the rules that are enforced |
| `CLAUDE.md` | the constitution: thirteen stipulations, each naming its gate |
| `SPEC.md` | the full technical specification, and §13's decision register |
| `STATE.md` | what was built, milestone by milestone, and what it owes |
| `docs/server-api.md` | the server contract, cited to upstream source |
| `docs/decisions/` | choices we made, and what each one rejected |
| `docs/field-notes.md` | how the server, libmpv, dio and Flutter were *measured* to behave |
| `docs/architecture.md` | layering, gate scope, and what each gate really covers |
| `docs/risks.md` | risks not yet retired, with their spikes |
| `docs/verification-backlog.md` | every claim no test here can check, with the experiment that would settle it |

The server is a third party we do not control. Its HTTP contract is an external
boundary — observed, documented and versioned, never assumed — which is why
`docs/server-api.md` cites upstream line numbers and every model round-trips a
captured payload.

## Licence

[EUPL-1.2](LICENSE), the same licence as the FileFin server.

The player links prebuilt libmpv through `media_kit`, which is
LGPL-2.1-or-later — a Compatible Licence in the EUPL's own Appendix, so the
combination is fine. Distribution is direct APK and TestFlight/sideload; F-Droid
is explicitly not a commitment, because their pipeline builds everything from
source and a prebuilt `libmpv.so` cannot satisfy that. `docs/risks.md` R4 holds
the full position.
