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
| ba470911 | **Fork identity** — version `0.2.102-mael.6` (upstream base v0.2.102); `zeron update` refuses to overwrite the fork with *stock* while `ZERON_FORK` is set (points at `zeron-fork-update`), but one-click applies `-mael.N` releases from the fork feed (fork-aware staging into `fork-<version>/`); background auto-update disabled; `zeron status` shows the fork line | mael |
| — | **Rewind** — rewind button in the hover strip under each sent message in the main transcript (click twice to confirm; side chats don't offer it) plus a double-Escape prompt list from the main composer. For Droid and OpenCode chats it truncates the transcript from that message and drops the agent's session (`RewindChat` RPC); the next run starts a fresh session bootstrapped with the remaining transcript. Files are not reverted. Other harnesses only get the prompt text back | upstream PR #384 + mael |
| — | **Compact + open-in-terminal titlebar buttons** (OpenCode/Droid chats only) — compact opens the chat input's own model picker to choose the summarizer, then `CompactChat` (the pick never rewrites the chat's active model; a "Compacting this chat…" caption shows under the composer, failures surface as its error chip): OpenCode compacts through its own API (2.x: picked model applied to the session first, since compaction uses the session's model; 1.x: `/summarize` with the model in the body) and the engine keeps its spawned `opencode serve` alive until the session is idle again, Droid queues a `/compress` turn with the chat's sandbox. Also reachable from the context-window popup. The terminal button runs the native resume command (`opencode --session '<id>'` / `droid --resume '<id>'`) in a fresh embedded terminal tab, in the session's own cwd | mael |
| 0502fe67 | 0.2.86 surface adaptation of the droid harness (install methods, skills dirs, spec fields, registry descriptor, auth test API) | mael |
| 1f691a9c | **Fork updates in the native update UI + droid fallback chip** — upstream's own update strip and "Check for updates" dialog (`app_update.rs`), made fork-aware: on a fork build the account menu gets a **Fork** section with **Update Zeron fork** (checks the fork's `-mael.N` releases, downloads + verifies right away, then "Restart to update") and **Rebase onto upstream…** (opens a new session on the local fork clone — any local project with a `FORK.md` — with the full rebase + release runbook prefilled, not sent). Stock releases are never offered. ACP `config_option_update` model changes surface as an amber "Model switched" transcript chip (Droid's quota fallback onto its core models) | mael |

Skipped on purpose: the PR's "Permission trait to every harness" commit (`ae4d39d1`) —
upstream has its own permission control. Only Droid's `autonomy_level` surfaces as a
"Permission" trait; other ACP harnesses keep upstream's hidden no-prompts mode. Like every
ACP harness, Droid tool-permission requests are still auto-approved, so the levels below
Auto (High) only change what Droid itself attempts.
When upstream #372 merges, the rebase will naturally drop what upstream already ships.

## Versioning

- Fork version = `<upstream version>-mael.<n>` (currently `0.2.102-mael.6`), tag
  `v<version>` on `main` (no slash — slashes break release downloads).
- `version_newer` compares numeric cores first; on equal cores a higher
  `-mael.N` counts as newer **only when the installed build is itself a
  `-mael.*`** — so `mael.2` > `mael.1` is discovered, while a fork at the
  same base is never nagged toward stock (and stock never toward a fork).
  Equal cores with no fork suffix on either side never count as newer.
- `zeron status` prints `Fork: mael (<version> + droid + selfhost)` when `ZERON_FORK` is set
  (set in `~/.zeron/env`, which the systemd unit loads).

## Cutting a one-click fork release

Bump the version and push `main`: CI (`.github/workflows/fork-release.yml`)
sees a `-mael.N` version with no `v<version>` tag yet, builds the x86_64 +
aarch64 Linux tarballs, then tags that commit and publishes the GitHub
release with the tarballs + `manifest.json`. Pushing the tag yourself works
too (it must match `Cargo.toml`). Public repo, so the CI minutes are free.

```bash
# 1. Bump [workspace.package] version in Cargo.toml:
#    numeric core and/or -mael.N must grow (mael.3 > mael.2 counts, but
#    0.2.102-mael.2 does NOT supersede 0.2.102 — see version_newer above).
# 2. Commit and push; CI tags + publishes:
git push origin main
#    (or explicitly, tag has NO slash: git tag v0.2.102-mael.6 && git push origin main v0.2.102-mael.6)
```

What **Update Zeron fork** does on the other devices: discovers the newest
`-mael.N` release newer than the installed version via the GitHub releases
API (the homelab edge `{edge}/releases/` feed is still checked too, newest
wins), downloads the tarball, verifies sha256 against the release's
`manifest.json`, stages it into `~/.zeron/app/fork-<ver>/` with the
`.mael-fork` marker, and on "Restart to update" repoints `current` and
relaunches; the `zeron.service` engine restarts itself once superseded.
Stock releases are never offered, so the fork can't be clobbered; unmanaged
source builds link to the fork's releases page instead (`ZERON_FORK_REPO`
overrides the repo when renamed). A fresh device installs the newest fork
release with `scripts/install-desktop.sh` (prebuilt by default,
`FROM_SOURCE=1` to build).

Legacy path (LAN-only, no GitHub): `scripts/publish-fork-release.sh`
builds + stages the same metadata locally, and `--upload` pushes it to the
homelab edge bucket (`zeron-selfhost-releases`) the engines poll as a
fallback at `{edge}/releases/`. Multi-arch: run step 3 once per arch (or
gather the tarballs into `target/package/`) — the manifest merges every
`zeron-<VERSION>-*.tar.gz` found. Remote R2 needs `CLOUDFLARE_API_TOKEN`;
against the homelab's local persist dir set `EDGE_PERSIST_DIR=/data` (run
from the edge host). Upload order still matters: artifacts, then
manifest.json, then latest.txt.

## Runbook for future AI agents: shipping fork changes

When the user asks for fork changes AND wants them live on all devices,
always finish with a release — code on `main` alone never reaches the
other machines. Follow this checklist every time:

1. Implement + verify: `cargo check` / `cargo test -p <crate>` for what
   changed. Local builds need mold at `~/.local/bin/mold` PLUS a
   `~/.local/bin/ld.mold` symlink to it (`.cargo/config.toml` passes
   `-fuse-ld=mold`, and gcc looks for `ld.mold` — without the symlink
   linking fails with a confusing `cannot find 'ld'`). Run tests with
   `env -u ZERON_FORK`: the ambient `ZERON_FORK=mael` on the home PC
   breaks stock-assuming update tests.
2. Bump `[workspace.package] version` in `Cargo.toml` (`-mael.N` + 1, or
   the new upstream core + `-mael.1`) and update the two version refs in
   this file (identity row + Versioning section). Run `cargo check` once
   so `Cargo.lock` follows the bump, and commit the lock too.
3. Commit on `main`. If you tag by hand, tag **slashless**:
   `git tag v<version>` (e.g. `v0.2.102-mael.6`). NEVER `mael/v<version>`
   — slashes break GitHub release-download URLs. `release.yml` ignores
   `v*-mael.*` tags, so only `fork-release.yml` fires.
4. `git push origin main` (plus the tag if you made one) — CI builds
   x86_64 + aarch64, tags, and publishes the GitHub release. Watch the
   `fork-release` run; every other device then gets it from the account
   menu's **Update Zeron fork** (or the sidebar strip, or `zeron update`).
5. Update THIS pc from the new release the same way, or rebuild +
   reinstall locally via `FROM_SOURCE=1 scripts/install-desktop.sh`.

## Taking an official release (low-friction path)

Official releases land on upstream (`https://github.com/zeronsh/zeron`). The easiest path:
account menu → **Fork** → **Rebase onto upstream…** opens a session on the fork clone with
the runbook prefilled (backup branch, `git rebase --onto` the newest stable upstream tag,
conflict rules, bump to `X.Y.Z-mael.1`, check + test, tag, `--force-with-lease` push, watch
CI). Review the prompt and send it.

The scripted path, on the home PC:

```bash
zeron-fork-update
```

The script (`~/.local/bin/zeron-fork-update`; works in the enclosing fork clone, else
`~/.build/zeron`) backs up the chat stores, fetches the `upstream` remote's tags, rebases the
fork commits onto the newest upstream tag (or the one you pass), bumps to
`<upstream>-mael.1`, rebuilds in release mode, installs into `~/.zeron/app/fork-<version>/`,
repoints `~/.zeron/app/current`, commits the bump, tags `v<version>`, and restarts the
`zeron.service` engine. It does not push: run the printed
`git push --force-with-lease origin main v<version>` so CI publishes the release for the
other devices.

If the rebase conflicts, it aborts safely and prints the exact `git rebase --onto` command to
redo by hand; resolve the markers, `git rebase --continue`, then rerun `zeron-fork-update <tag>`.

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
- `~/.local/bin/zeron` → `~/.zeron/zeron-launch`, a wrapper that loads `~/.zeron/env`
  (`ZERON_FORK`, `ZERON_EDGE_URL`) and runs `~/.zeron/app/current/zeron`; the desktop entry
  launches the same wrapper, so `zeron` on PATH and the app icon are both the fork.
- `~/.local/bin/zeron-fork-update` — the helper that takes official releases
  (installed by `scripts/install-desktop.sh`).
- The official release dir (e.g. `~/.zeron/app/0.2.86/`) stays untouched if one
  was installed before the fork; running stock `zeron update` afterwards takes
  you back to official releases.

## Gotchas

- The fork's engine *code* is upstream 0.2.102 + the patches; the version string is only a
  display identity. Wire-protocol sync with official devices is unchanged (same 0.2.102 code).
- Never run stock `zeron update` while the fork is installed: the fork's own guard refuses the
  self-overwrite, but if an official binary ever got swapped in externally, `zeron-fork-update`
  restores the fork cleanly.
- A full release build needs roughly 8 GB free in `~/.build/zeron/target/`.
- Clean-build tip: `rm -rf ~/.build/zeron/target/debug` after working with `cargo check` —
  dev-profile artifacts can leak large intermediate files.
- Fast builds (fork-only, not upstream): `.cargo/config.toml` points the
  linker at mold (`~/.local/bin/mold`, static build — 3-10x faster links
  on the multi-GB test/binary links), and `[profile.dev]` keeps line
  tables only (`debug = 1`). Restore full symbols per-build with
  `CARGO_PROFILE_DEV_DEBUG=true` (env overrides the file; a plain
  `RUSTFLAGS=` export would silently drop mold). For iteration prefer
  `cargo check` (no codegen/link) and `cargo test -p <crate>` over
  workspace-wide builds.
