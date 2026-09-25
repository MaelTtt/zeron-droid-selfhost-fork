# mael fork of Zeron

A maintained local fork of [zeronsh/zeron](https://github.com/zeronsh/zeron) (MIT)that layers
two upstream PRs which haven't merged yet, plus a fork identity layer, on top of official
releases.

## What's in the fork (commits on `mael/main`, rebased onto the official release)

| commit | what | origin |
| --- | --- | --- |
| 9c1673d6 | **Factory Droid as a first-class ACP harness** — `droid exec --output-format acp`, live model discovery, autonomy wiring | upstream PR #372 (rebased) |
| 30df737d | Droid permission level persistence in the model picker | upstream PR #372 |
| 8014e64d | **Self-host the edge with `AUTH_MODE=none`** — Docker edge relay (`docker-compose.selfhost.yml`, `edge/Dockerfile`, `edge/wrangler.selfhost.jsonc`, `docs/SELFHOST.md`); the engine accepts your own `ZERON_EDGE_URL` with no WorkOS/Zeron account | upstream PR #317 |
| ba470911 | **Fork identity** — version `0.2.86-mael.1`; `zeron update` refuses to overwrite the fork while `ZERON_FORK` is set (points at `zeron-fork-update`); background auto-update disabled; `zeron status` shows the fork line | mael |
| 0502fe67 | 0.2.86 surface adaptation of the droid harness (install methods, skills dirs, spec fields, registry descriptor, auth test API) | mael |

Skipped on purpose: the PR's "Permission trait to every harness" commit (`ae4d39d1`) —
upstream gained its own `crates/harness/src/permission.rs` in 0.2.86 that supersedes it.
When upstream #372 merges, the rebase will naturally drop what upstream already ships.

## Versioning

- Fork version = `<upstream version>-mael.<n>` (currently `0.2.86-mael.1`), tag
  `mael/v<version>` on `mael/main`.
- The `-mael.1` suffix is stripped before the numeric compare in `version_newer`,
  so `zeron update --check` correctly reports a newer official release as
  available — and, with `ZERON_FORK` set, points at `zeron-fork-update` instead
  of overwriting the fork. Equal numeric cores never count as newer, so a fork
  already at the same base is never nagged into "updating" to stock.
- `zeron status` prints `Fork: mael (<version> + droid + selfhost)` when `ZERON_FORK` is set
  (set in `~/.zeron/env`, which the systemd unit loads).

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

- The fork's engine *code* is upstream 0.2.86 + the patches; the version string is only a
  display identity. Wire-protocol sync with official devices is unchanged (same 0.2.86 code).
- Never run stock `zeron update` while the fork is installed: the fork's own guard refuses the
  self-overwrite, but if an official binary ever got swapped in externally, `zeron-fork-update`
  restores the fork cleanly.
- A full release build needs roughly 8 GB free in `~/.build/zeron/target/`.
- Clean-build tip: `rm -rf ~/.build/zeron/target/debug` after working with `cargo check` —
  dev-profile artifacts can leak large intermediate files.
