#!/usr/bin/env bash
# Install the mael fork of Zeron (desktop app + engine) on a Linux machine.
# Fork of zeronsh/zeron with:
#   - Factory Droid as a first-class ACP harness
#   - self-hosted edge support (AUTH_MODE=none, no account needed)
#   - fork identity + update guard (see FORK.md)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MaelTtt/zeron-droid-selfhost-fork/mael/main/scripts/install-desktop.sh | bash
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

say "clone fork into $CLONE_DIR"
mkdir -p "$(dirname "$CLONE_DIR")"
if [ ! -d "$CLONE_DIR/.git" ]; then
    git clone -b mael/main "$REPO" "$CLONE_DIR"
else
    git -C "$CLONE_DIR" pull --ff-only origin mael/main
fi
cd "$CLONE_DIR"

say "build (release; grab a coffee, ~10-20 min)"
cargo build --release -p zeron

say "install binary as the fork app"
mkdir -p "$HOME/.zeron/app/local-mael"
cp target/release/zeron "$HOME/.zeron/app/local-mael/zeron"
echo "mael fork — rebuild via zeron-fork-update or re-clone" \
    > "$HOME/.zeron/app/local-mael/.mael-fork"
ln -sfn "$HOME/.zeron/app/local-mael" "$HOME/.zeron/app/current"
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.zeron/app/current/zeron" "$HOME/.local/bin/zeron"

say "desktop entry + icon (so it shows in your launcher)"
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/512x512/apps"
cat > "$HOME/.local/share/applications/zeron.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Zeron
GenericName=Coding Agent Controller
Comment=mael fork — droid + selfhost
Exec=$HOME/.zeron/app/current/zeron %u
TryExec=$HOME/.zeron/app/current/zeron
Icon=zeron
Terminal=false
Categories=Development;
Keywords=agent;droid;claude;codex;ai;coding;
StartupWMClass=zeron
MimeType=x-scheme-handler/zeron;
DESKTOP
if [ -f "$CLONE_DIR/apps/landing/public/assets/zeron.png" ]; then
    cp "$CLONE_DIR/apps/landing/public/assets/zeron.png" \
       "$HOME/.local/share/icons/hicolor/512x512/apps/zeron.png"
fi
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications/"
# KDE/Hyprland launcher caches
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

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

say "done"
"$HOME/.local/bin/zeron" status
echo
echo "Looking for 'Zeron' in your launcher (rofi/krunner/GNOME menu)."
echo "If you use Hyprland/KDE and it doesn't appear, run: kbuildsycoca6 --noincremental"
