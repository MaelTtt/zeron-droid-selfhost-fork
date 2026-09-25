# Installing the Zeron desktop app from this fork

The **desktop app** (UI + engine) from `mael/main` on another Linux PC, in
~5 minutes of terminal time + one coffee for the build.

What you get: `zeron` CLI, the gpui desktop app (in your launcher with an
icon), the headless engine daemon, and — if you want — sessions synced to
mael's homelab edge with **no Zeron account** (self-hosted, `AUTH_MODE=none`).

## Prerequisites

- Linux with `pacman`, `apt`, or `dnf`
- `sudo` rights
- Git + SSH access to `git@github.com:MaelTtt/zeron-droid-selfhost-fork` (your GitHub key), or an HTTPS clone instead
- ~8 GB free disk for the build; `rustup` gets installed if missing
- To **see the homelab device later**: WireGuard to the homelab (`wg0`), since the edge is only reachable on the LAN/WG interface

## Easiest: one-shot script

```bash
curl -fsSL https://raw.githubusercontent.com/MaelTtt/zeron-droid-selfhost-fork/mael/main/scripts/install-desktop.sh | bash
```

or, if you prefer to read before running:

```bash
git clone -b mael/main git@github.com:MaelTtt/zeron-droid-selfhost-fork.git ~/.build/zeron
cd ~/.build/zeron
./scripts/install-desktop.sh
```

It does, in this order:

1. **Deps** — distro-aware (`pacman` / `apt-get` / `dnf`): toolchain, clang, X/wayland libs, WebKitGTK 4.1 (needed to link the Linux browser helper — gpui links these even for headless; upstream install-script bug `zeronsh/zeron#197` describes the same thing).
2. **Rust** — installs stable via rustup if `cargo` isn't on PATH.
3. **Clone/pull** the fork to `~/.build/zeron` (branch `mael/main`).
4. **Build** — `cargo build --release -p zeron` (10–20 min).
5. **Install** the binary at `~/.zeron/app/fork-<version>/zeron` with a `.mael-fork` marker; `~/.zeron/app/current` → that dir; `~/.local/bin/zeron` symlink for PATH; `~/.local/bin/zeron-fork-update` helper for taking future official releases.
6. **Desktop entry + icon** — `~/.local/share/applications/zeron.desktop` with **absolute** `Exec` (krunner has no `~/.local/bin` in PATH — this is why "type `zeron` in the launcher" failed before), `StartupWMClass=zeron`, icon in hicolor, caches refreshed (update-desktop-database + kbuildsycoca6 + gtk-update-icon-cache).
7. **Env** — `~/.zeron/env` gets:
   ```
   ZERON_EDGE_URL=http://10.66.0.1:8787   # homelab edge over WireGuard (override with ZERON_EDGE_URL=... http)
   ZERON_WORKOS_CLIENT_ID=                # empty → fork engine adopts the open-edge identity local@local
   ZERON_FORK=mael                        # enables the fork status line + update guard
   ```
8. **Engine daemon** — `zeron daemon install` (systemd `--user` service; skip with `SKIP_DAEMON=1`).
9. Prints `zeron status` — should show:
   ```
   Fork:     mael (0.2.86-mael.1 + droid + selfhost)
   Edge:     http://10.66.0.1:8787
   Mode:     development
   Auth:     dev mode (bearer = user id)
   ```

## Theme (BlackViolet)

The bundle lives in the repo at [`themes/black-violet/`](../themes/black-violet) (dark + light
variants + `package.json`, mapped from mael's Noctalia palette). The install script copies it
to `~/.config/zeron-themes/black-violet/`.

One-time per machine, import it in the UI:

1. Zeron -> **Settings -> Appearance -> Themes -> Add theme**
2. Choose **Link to source** -> `~/.config/zeron-themes/black-violet/package.json`
3. In the mapping review, tick **Dark** and **Light** -> **Import**
4. Appearance -> set **Dark theme: Black Violet Dark**, **Light theme: Black Violet Light**

It's a *linked* theme: because it points at the copied repo bundle, a future
`git pull` + re-import/reload picks up any color tweaks without redoing the flow.

## First launch

- Open your launcher (rofi/krunner/GNOME menu) and type **Zeron**. The sidebar lists every device in the shared `local@local` workspace (desktop, silverhand, any other machine running the fork against the same edge).
- Create a session and pick the device/space you want to host it.
- Harnesses are **per-device**: this machine needs its own `claude` / `opencode` / `droid` installed and signed in (`opencode auth login`, `droid` once) for those agents to appear in the composer — auth files are not copied across devices.
- `zeron status` anytime to see the engine + mode.

## Updating later

- On the fork's home PC: `zeron-fork-update` rebases the fork onto the next official release and rebuilds.
- On other machines, re-run `./scripts/install-desktop.sh` (it pulls `mael/main`, rebuilds only if the build changed, and swaps the binary).
- Never run stock `zeron update` while the fork is installed — the fork's guard refuses with a pointer to `zeron-fork-update` (see FORK.md).

## Troubleshooting

| symptom | fix |
| --- | --- |
| Launcher search shows nothing | `kbuildsycoca6 --noincremental` (KDE/Hyprland), or `update-desktop-database ~/.local/share/applications` (GNOME) |
| App opens but instantly closes / `libxkbcommon.so.0 not found` | deps missing — rerun the distro block in `scripts/install-desktop.sh` |
| `error while loading shared libraries: libwebkit2gtk...` | WebKitGTK 4.1 dev package missing (Debian: `libwebkit2gtk-4.1-dev`; Arch: `webkit2gtk-4.1`) |
| `Edge: https://edge.zeron.sh` instead of `http://10.66.0.1:8787` | `~/.zeron/env` missing `ZERON_EDGE_URL` — check `cat ~/.zeron/env`, then `systemctl --user restart zeron` |
| `Mode: local only` | env not loaded into the engine, or WG down — `ping 10.66.0.1` must work |
| Engine crash loops | `journalctl --user -u zeron -n 40`, and check the shared-library list above |
