#!/usr/bin/env bash
# Install the mael fork of Zeron (desktop app + engine) on a Linux machine.
# Fork of zeronsh/zeron with:
#   - Factory Droid as a first-class ACP harness
#   - self-hosted edge support (AUTH_MODE=none, no account needed)
#   - fork identity + update guard (see FORK.md)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MaelTtt/zeron-droid-selfhost-fork/main/scripts/install-desktop.sh | bash
# ...or clone first and run ./scripts/install-desktop.sh
#
# Optional env:
#   ZERON_EDGE_URL   (default: http://10.66.0.1:8787 — mael's homelab edge over WireGuard)
#   SKIP_DAEMON=1    (don't install the systemd engine service)
set -euo pipefail

REPO="${REPO:-git@github.com:MaelTtt/zeron-droid-selfhost-fork.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/.build/zeron}"
EDGE_URL="${ZERON_EDGE_URL:-http://10.66.0.1:8787}"

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# --- distro ---------------------------------------------------------------
if command -v pacman >/dev/null; then DISTRO=arch
elif command -v apt-get;  then DISTRO=debian
elif command -v dnf;      then DISTRO=fedora
else echo "Unsupported distro (need pacman/apt/dnf)."; exit 1; fi

say "[$DISTRO] development dependencies"
case "$DISTRO" in
  arch)   sudo pacman -S --needed --noconfirm base-devel clang pkgconf git \
              libxkbcommon libxkbcommon-x11 wayland libxcb fontconfig \
              webkit2gtk-4.1 ;;
  debian) sudo apt-get update -qq && sudo apt-get install -y -qq \
              build-essential clang libclang-dev pkg-config git curl \
              libssl-dev libwayland-dev libxkbcommon-dev libxkbcommon-x11-0 \
              libxcb1-dev libfontconfig1-dev libfreetype-dev \
              libwebkit2gtk-4.1-dev libjson-glib-dev ;;
  fedora) sudo dnf install -y clang clang-devel pkgconf-pkg-config git \
              openssl-devel wayland-devel libxkbcommon-devel libxkbcommon-x11-devel \
              libxcb-devel fontconfig-devel freetype-devel \
              webkit2gtk4.1-devel json-glib-devel ;;
esac

say "rust toolchain"
if ! command -v cargo >/dev/null; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
    export PATH="$HOME/.cargo/bin:$PATH"
fi
rustc --version

say "clone/pull fork into $CLONE_DIR"
mkdir -p "$(dirname "$CLONE_DIR")"
if [ ! -d "$CLONE_DIR/.git" ]; then
    git clone -b main "$REPO" "$CLONE_DIR"
else
    cd "$CLONE_DIR"
    git fetch origin main -q
    git reset --hard origin/main -q   # install dir: remote is source of truth
    git clean -fdq target 2>/dev/null || true
fi
cd "$CLONE_DIR"

say "build (release; grab a coffee, ~10-20 min)"
cargo build --release -p zeron

BUILT="$CLONE_DIR/target/release/zeron"
NEWVER="$($BUILT --version | awk '{print \$2}')"

say "install / update fork binary (versioned, no ETXTBSY)"
# Layout: one dir per build under ~/.zeron/app/, 'current' symlink selects.
# Never overwrite a binary a process may be running: new version -> new dir,
# then repoint current + restart. Identical build -> nothing to do.
mkdir -p "$HOME/.zeron/app"
CURRENT="$HOME/.zeron/app/current"
TARGET_DIR="$HOME/.zeron/app/fork-$NEWVER"
RUNNING=""

if [ -x "$HOME/.zeron/app/current/zeron" ]; then
    CURVER="$("$HOME/.zeron/app/current/zeron" --version 2>/dev/null | awk '{print \$2}')"
    CURSHA="$(sha256sum "$HOME/.zeron/app/current/zeron" 2>/dev/null | cut -d' ' -f1)"
    NEWSHA="$(sha256sum "$BUILT" | cut -d' ' -f1)"
    RUNNING="$(pgrep -x zeron | head -1 || true)"
    if [ "$CURSHA" = "$NEWSHA" ]; then
        say "already running $CURVER — same build, skipping swap"
    else
        echo "updating: $CURVER -> $NEWVER"
        rm -rf "$TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        cp "$BUILT" "$TARGET_DIR/zeron"          # fresh dir: cannot be Text-busy
        echo 'mael fork — see docs/INSTALL-DESKTOP.md' > "$TARGET_DIR/.mael-fork"
        ln -sfn "$TARGET_DIR" "$HOME/.zeron/app/current"
        # bounce only if an engine is actually running
        if [ -n "$RUNNING" ]; then
            say "restarting engine (was running pid $RUNNING)"
            if systemctl --user list-unit-files 2>/dev/null | grep -q '^zeron.service'; then
                systemctl --user restart zeron.service
            else
                pkill -x zeron || true
                sleep 1
            fi
        fi
    fi
else
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    cp "$BUILT" "$TARGET_DIR/zeron"
    echo 'mael fork — see docs/INSTALL-DESKTOP.md' > "$TARGET_DIR/.mael-fork"
    ln -sfn "$TARGET_DIR" "$HOME/.zeron/app/current"
fi

# prune old fork installs, keep the newest 2
ls -1d "$HOME/.zeron/app/fork-"[0-9]* 2>/dev/null \
  | grep -v "$(readlink "$HOME/.zeron/app/current" 2>/dev/null)" \
  | sort -V | head -n -2 | xargs -r rm -rf

export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.zeron/app/current/zeron" "$HOME/.local/bin/zeron"
# fork update helper (rebase onto official releases + rebuild)
cp "$CLONE_DIR/scripts/zeron-fork-update.sh" "$HOME/.local/bin/zeron-fork-update"
chmod +x "$HOME/.local/bin/zeron-fork-update"

say "desktop entry + icon"
mkdir -p "$HOME/.local/share/applications" \
    "$HOME/.local/share/icons/hicolor/1024x1024/apps" \
    "$HOME/.local/share/icons/hicolor/scalable/apps"
# Absolute Exec: krunner has no ~/.local/bin on PATH, so a bare `zeron`
# never resolves from the launcher.
cat > "$HOME/.local/share/applications/zeron.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Zeron
GenericName=Coding Agent Controller
Comment=mael fork — droid + selfhost
Exec=$HOME/.zeron/app/current/zeron %u
TryExec=$HOME/.zeron/app/current/zeron
# Absolute Icon: Qt/Vicinae ignores hicolor dirs with no index.theme, so a
# themed Icon=zeron is unreliable — point straight at the file instead.
Icon=$HOME/.local/share/icons/hicolor/512x512/apps/zeron.png
Terminal=false
Categories=Development;
Keywords=agent;droid;claude;codex;ai;coding;
StartupWMClass=zeron
MimeType=x-scheme-handler/zeron;
ENTRY
# NOTE: no index.theme lists 1024x1024/apps, so a 1024-only install is
# invisible to Gtk/Vicinae icon lookups — install the same png at every
# standard size (Gtk scales on load, exact pixels don't matter here).
for size in 1024 512 256 128 64 48 32; do
    install -Dm644 "$CLONE_DIR/dist/zeron.png" \
        "$HOME/.local/share/icons/hicolor/${size}x${size}/apps/zeron.png"
done
# Qt (Vicinae) skips icon dirs with no index.theme — the stock hicolor one
# covers all sizes installed above.
[ -f "$HOME/.local/share/icons/hicolor/index.theme" ] || install -Dm644 \
    /usr/share/icons/hicolor/index.theme \
    "$HOME/.local/share/icons/hicolor/index.theme"
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$HOME/.local/share/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
command -v kbuildsycoca6 >/dev/null 2>&1 \
    && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

say "theme bundle (BlackViolet, from Noctalia palette)"
THEME_DIR="$HOME/.config/zeron-themes"
mkdir -p "$THEME_DIR"
cp -r "$CLONE_DIR/themes/black-violet" "$THEME_DIR/"
cat <<'''THEME'''
Theme files copied to ~/.config/zeron-themes/black-violet.
One-time UI import (per machine):
  Zeron -> Settings -> Appearance -> Themes -> Add theme -> "Link to source"
  -> select ~/.config/zeron-themes/black-violet/package.json
  -> tick the Dark and Light variants -> Import.
  Then Appearance -> Dark theme: Black Violet Dark; Light theme: Black Violet Light.
(Linked stays fresh: future fork pulls auto-update the theme on reload.)
THEME

say "point this device at the homelab edge"
mkdir -p "$HOME/.zeron"
# note: DROID/OPENCODE auth files are per-machine; installing those CLIs is up to you
cat > "$HOME/.zeron/env" <<ENV
ZERON_EDGE_URL=$EDGE_URL
ZERON_WORKOS_CLIENT_ID=
ZERON_FORK=mael
ENV

if [ "${SKIP_DAEMON:-0}" != "1" ]; then
    say "engine daemon (systemd --user)"
    "$HOME/.local/bin/zeron" daemon install
fi

say "restarting engine"
systemctl --user restart zeron.service 2>/dev/null || true

say "done"
"$HOME/.local/bin/zeron" status
echo
echo "Looking for 'Zeron' in your launcher (rofi/krunner/GNOME menu)."
echo "If you use Hyprland/KDE and it doesn't appear, run: kbuildsycoca6 --noincremental"
