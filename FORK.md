# mael fork of Zeron

A maintained local fork of [zeronsh/zeron](https://github.com/zeronsh/zeron) (MIT)that layers
two upstream PRs which haven't merged yet, plus a fork identity layer, on top of official
releases.

## What's in the fork (commits on `main`, rebased onto the official release)

| commit | what | origin |
| --- | --- | --- |
| 9c1673d6 | **Factory Droid as a first-class ACP harness** — `droid exec --output-format acp`, live model discovery, autonomy wiring | upstream PR #372 (rebased) |
| 30df737d | Droid permission level persistence in the model picker | upstream PR #372 |
| 8014e64d | **Self-host the edge with `AUTH_MODE=none`** — Docker edge relay (`docker-compose.selfhost.yml`, `edge/Dockerfile`, `edge/wrangler.selfhost.jsonc`, `docs/SELFHOST.md`); the engine accepts your own `ZERON_EDGE_URL` with no WorkOS/Zeron account | upstream PR #317 |
| ba470911 | **Fork identity** — version `0.2.96-mael.2`; `zeron update` refuses to overwrite the fork with *stock* while `ZERON_FORK` is set (points at `zeron-fork-update`), but one-click applies `-mael.N` releases from the fork feed (fork-aware staging into `fork-<version>/`); background auto-update disabled; `zeron status` shows the fork line | mael |
| — | **Rewind** — rewind button in the hover strip under each sent message (click twice to confirm) plus double-Escape prompt list. For Droid and OpenCode chats it truncates the transcript from that message and drops the agent's session (`RewindChat` RPC); the next run starts a fresh session bootstrapped with the remaining transcript. Files are not reverted. Other harnesses only get the prompt text back | upstream PR #384 + mael |
| 0502fe67 | 0.2.86 surface adaptation of the droid harness (install methods, skills dirs, spec fields, registry descriptor, auth test API) | mael |
| 1f691a9c | **One-click update strip + droid fallback chip** — managed installs apply headless releases from the sidebar strip (`ApplyUpdate`: stage + swap + service restart, with updating/failed states); a fork build applies `-mael.N` releases from the fork feed the same way (fork-aware staging) and opens a fresh session with the rebase runbook prefilled for *stock* releases (which would clobber the fork); ACP `config_option_update` model changes surface as an amber "Model switched" transcript chip (Droid's quota fallback onto its core models) | mael |

Skipped on purpose: the PR's "Permission trait to every harness" commit (`ae4d39d1`) —
upstream gained its own `crates/harness/src/permission.rs` in 0.2.86 that supersedes it.
When upstream #372 merges, the rebase will naturally drop what upstream already ships.

## Versioning

- Fork version = `<upstream version>-mael.<n>` (currently `0.2.96-mael.2`), tag
  `mael/v<version>` on `main`.
- `version_newer` compares numeric cores first; on equal cores a higher
  `-mael.N` counts as newer **only when the installed build is itself a
  `-mael.*`** — so `mael.2` > `mael.1` is discovered, while a fork at the
  same base is never nagged toward stock (and stock never toward a fork).
  Equal cores with no fork suffix on either side never count as newer.
- `zeron status` prints `Fork: mael (<version> + droid + selfhost)` when `ZERON_FORK` is set
  (set in `~/.zeron/env`, which the systemd unit loads).

## Cutting a one-click fork release

`zeron-fork-update` (rebase + rebuild on each machine) still works, but fork
releases can now also be applied one-click from the sidebar strip or
`zeron update` — provided they are published to the feed the engines poll
(`{edge}/releases/`, i.e. the `zeron-selfhost-releases` bucket on the
homelab edge):

```bash
# 1. Bump [workspace.package] version in Cargo.toml:
#    numeric core and/or -mael.N must grow (mael.2 > mael.1 counts, but
#    0.2.96-mael.1 does NOT supersede 0.2.96 — see version_newer above).
# 2. Commit, tag mael/v<version>, push main.
# 3. Build + stage the release metadata:
scripts/publish-fork-release.sh            # or --skip-build to reuse tarballs
# 4. Upload (artifacts, then manifest.json, then latest.txt — order matters):
scripts/publish-fork-release.sh --upload
```

Multi-arch: run step 3 once per arch (or gather the tarballs into
`target/package/`) — the manifest merges every `zeron-<VERSION>-*.tar.gz`
found. Remote R2 needs `CLOUDFLARE_API_TOKEN`; against the homelab's local
persist dir set `EDGE_PERSIST_DIR=/data` (run from the edge host).

What the client does on click (`ApplyUpdate` RPC): downloads the tarball,
verifies sha256 against the manifest, unpacks into `~/.zeron/app/fork-<ver>/`
with the `.mael-fork` marker, atomically repoints `current`, prunes older
fork dirs (keeps the newest spare), and restarts `zeron.service`. A fork
install offered a *stock* version opens a fresh session with the rebase
runbook prefilled in the composer (not sent) — the user's own agent does
the rebase + rebuild + install per the runbook below. The `-mael.N` suffix
is the proof of fork origin, and stock never publishes one.

## Taking an official release (low-friction path)

Official releases land on upstream `origin/main`. To adopt a new one while keeping the fork
patches:

```bash
zeron-fork-update
```

The script (`~/.local/bin/zeron-fork-update`) fetches upstream, rebases the fork commits onto
the new `origin/main`, rebuilds in release mode, swaps the binary into
`~/.zeron/app/local-mael`, bumps the `mael/v*` tag, repoints `~/.zeron/app/current`, and
restarts the `zeron.service` engine.

If the rebase conflicts, it aborts safely. Resolve markers, then:

```bash
cd ~/.build/zeron && git rebase --continue && zeron-fork-update
```

Known conflict spots (from the two upstream refactors we've navigated): README harness lists,
`apps/ios/Zeron/Theme/BrandMarks.swift` (iOS icon list), `crates/harness/src/acp/mod.rs`
(harness doc header + new `AcpAgentSpec` fields), and `crates/ui/src/settings/harnesses.rs`
(upstream redesigned the Agents page — keep upstream's structure, re-add only what still
compiles).

## Install layout

- Fork binary: `~/.zeron/app/fork-<version>/zeron` (one dir per build), with a
  `.mael-fork` marker file. Older fork dirs are pruned (newest 2 kept).
- `~/.zeron/app/current` → the active `fork-<version>` dir — the systemd
  `zeron.service` runs from `current`, so the engine daemon and the desktop UI
  share the fork.
- `~/.local/bin/zeron` → `~/.zeron/app/current/zeron`, so `zeron` on PATH is the fork.
- `~/.local/bin/zeron-fork-update` — the helper that takes official releases
  (installed by `scripts/install-desktop.sh`).
- The official release dir (e.g. `~/.zeron/app/0.2.86/`) stays untouched if one
  was installed before the fork; running stock `zeron update` afterwards takes
  you back to official releases.

## Gotchas

- The fork's engine *code* is upstream 0.2.96 + the patches; the version string is only a
  display identity. Wire-protocol sync with official devices is unchanged (same 0.2.96 code).
- Never run stock `zeron update` while the fork is installed: the fork's own guard refuses the
  self-overwrite, but if an official binary ever got swapped in externally, `zeron-fork-update`
  restores the fork cleanly.
- A full release build needs roughly 8 GB free in `~/.build/zeron/target/`.
- Clean-build tip: `rm -rf ~/.build/zeron/target/debug` after working with `cargo check` —
  dev-profile artifacts can leak large intermediate files.
