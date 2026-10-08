#!/usr/bin/env bash
# Take an official Zeron release while keeping the mael fork patches.
#
# Rebase the fork commits (everything on main past the upstream cut
# point) onto a newer upstream release, bump the workspace version to
# <upstream>-mael.<n>, rebuild in release mode, and swap the binary into the
# versioned install layout (~/.zeron/app/fork-<ver> + `current` symlink).
#
# Usage:
#   zeron-fork-update [vX.Y.Z]     # explicit upstream tag (default: newest v* tag)
#
# Optional env:
#   CLONE_DIR   (default: the fork clone you run this from, else $HOME/.build/zeron)
#   UPSTREAM    (default: https://github.com/zeronsh/zeron.git)
#   SKIP_DAEMON=1 (don't touch the systemd engine service)
#
# On rebase conflicts the rebase is aborted safely and you get the manual
# recovery command (see FORK.md).
set -euo pipefail

if [ -z "${CLONE_DIR:-}" ]; then
    here="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$here" ] && [ -f "$here/FORK.md" ]; then
        CLONE_DIR="$here"
    else
        CLONE_DIR="$HOME/.build/zeron"
    fi
fi
UPSTREAM_URL="${UPSTREAM:-https://github.com/zeronsh/zeron.git}"

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$CLONE_DIR/.git" ] || die "no git clone at $CLONE_DIR (set CLONE_DIR=...)."
cd "$CLONE_DIR"

git update-index -q --refresh 2>/dev/null || true
git diff-index --quiet HEAD -- 2>/dev/null \
    || die "working tree is dirty — commit or stash first."

BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "main" ] || die "expected branch main, on $BRANCH."

if ! git remote get-url upstream >/dev/null 2>&1; then
    say "adding upstream remote ($UPSTREAM_URL)"
    git remote add upstream "$UPSTREAM_URL"
fi
say "backing up chat stores"
# Chats live in per-identity stores (orgs/<org>/<user>, profiles/local). A restart
# that resolves a different identity looks like lost sessions; keep a snapshot.
ZDATA="$HOME/.zeron"
BK="$ZDATA/backups/pre-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
for store in "$ZDATA"/orgs/*/* "$ZDATA"/profiles/*; do
    [ -f "$store/docs.sqlite3" ] || continue
    dest="$BK/${store#"$ZDATA"/}"
    mkdir -p "$dest"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$store/docs.sqlite3" ".backup '$dest/docs.sqlite3'" || cp -a "$store/docs.sqlite3"* "$dest/"
    else
        cp -a "$store/docs.sqlite3"* "$dest/"
    fi
    [ -d "$store/journals" ] && cp -a "$store/journals" "$dest/"
    [ -f "$store/previews.json" ] && cp -a "$store/previews.json" "$dest/"
done
ls -1d "$ZDATA"/backups/pre-update-* 2>/dev/null | sort | head -n -5 | xargs -r rm -rf

say "fetching upstream tags"
git fetch upstream --tags -q

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    TARGET="$(git ls-remote --tags --sort=version:refname upstream 'v[0-9]*' \
        | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' | tail -n 1)"
    [ -n "$TARGET" ] || die "could not determine the latest upstream tag."
fi
git rev-parse -q --verify "refs/tags/$TARGET" >/dev/null \
    || git rev-parse -q --verify "$TARGET^{commit}" >/dev/null \
    || die "unknown upstream target: $TARGET"
say "target: $TARGET"

BASE="$(git merge-base HEAD upstream/main)"
[ -n "$BASE" ] || die "no merge base with upstream/main — is upstream fetched?"
if [ "$(git rev-parse "$TARGET^{commit}")" = "$(git rev-parse "$BASE")" ]; then
    say "fork is already based on $TARGET — rebuild only"
elif git merge-base --is-ancestor "$BASE" "$TARGET^{commit}"; then
    say "rebasing fork commits ($BASE → HEAD) onto $TARGET"
    if ! git rebase --onto "$TARGET" "$BASE"; then
        git rebase --abort || true
        die "rebase conflicts — aborted safely. Resolve manually, then rerun:
  cd $CLONE_DIR && git rebase --onto $TARGET $BASE && zeron-fork-update $TARGET
Known spots: workspace version in Cargo.toml (-> <upstream>-mael.1),
crates/harness/src/acp/mod.rs, crates/ui/src/settings/harnesses.rs (see FORK.md)."
    fi
else
    die "target $TARGET does not contain the fork base $BASE — refusing."
fi

UPSTREAM_VER="$(echo "$TARGET" | sed 's/^v//')"
CUR_VER="$(grep -m1 '^version = ' Cargo.toml | sed 's/.*"\(.*\)"/\1/')"
case "$CUR_VER" in
    "$UPSTREAM_VER-mael."*) NEWVER="$CUR_VER" ;;
    *) NEWVER="$UPSTREAM_VER-mael.1" ;;
esac
if [ "$CUR_VER" != "$NEWVER" ]; then
    say "version: $CUR_VER -> $NEWVER"
    sed -i "0,/^version = \".*\"/s//version = \"$NEWVER\"/" Cargo.toml
else
    say "version stays $CUR_VER"
fi

say "build (release; grab a coffee, ~10-20 min)"
cargo build --release -p zeron

BUILT="$CLONE_DIR/target/release/zeron"
NEWVER="$($BUILT --version | awk '{print $2}')"
[ -n "$NEWVER" ] || die "built binary reports no version."

say "install / update fork binary (versioned, no ETXTBSY)"
mkdir -p "$HOME/.zeron/app"
TARGET_DIR="$HOME/.zeron/app/fork-$NEWVER"

if [ -x "$HOME/.zeron/app/current/zeron" ]; then
    CURVER="$("$HOME/.zeron/app/current/zeron" --version 2>/dev/null | awk '{print $2}')"
    CURSHA="$(sha256sum "$HOME/.zeron/app/current/zeron" 2>/dev/null | cut -d' ' -f1)"
    NEWSHA="$(sha256sum "$BUILT" | cut -d' ' -f1)"
    if [ "$CURSHA" = "$NEWSHA" ]; then
        say "already running $CURVER — same build, nothing to do"
    else
        echo "updating: $CURVER -> $NEWVER"
        rm -rf "$TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        cp "$BUILT" "$TARGET_DIR/zeron"
        echo 'mael fork — see docs/INSTALL-DESKTOP.md' > "$TARGET_DIR/.mael-fork"
        ln -sfn "$TARGET_DIR" "$HOME/.zeron/app/current"
    fi
else
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    cp "$BUILT" "$TARGET_DIR/zeron"
    echo 'mael fork — see docs/INSTALL-DESKTOP.md' > "$TARGET_DIR/.mael-fork"
    ln -sfn "$TARGET_DIR" "$HOME/.zeron/app/current"
fi

ls -1d "$HOME/.zeron/app/fork-"[0-9]* 2>/dev/null \
  | grep -v "$(readlink "$HOME/.zeron/app/current" 2>/dev/null)" \
  | sort -V | head -n -2 | xargs -r rm -rf

mkdir -p "$HOME/.local/bin"
# Every launch path must load ~/.zeron/env like the systemd unit does, or the
# app resolves a different identity and opens a different chat store.
cat > "$HOME/.zeron/zeron-launch" <<'LAUNCH'
#!/bin/sh
# Every launch path must share the engine identity from ~/.zeron/env, or Zeron opens a different chat store.
set -a
[ -f "$HOME/.zeron/env" ] && . "$HOME/.zeron/env"
set +a
exec "$HOME/.zeron/app/current/zeron" "$@"
LAUNCH
chmod +x "$HOME/.zeron/zeron-launch"
ln -sfn "$HOME/.zeron/zeron-launch" "$HOME/.local/bin/zeron"
cp "$CLONE_DIR/scripts/zeron-fork-update.sh" "$HOME/.local/bin/zeron-fork-update"
chmod +x "$HOME/.local/bin/zeron-fork-update"

# The tag must carry the bumped version: fork-release CI rejects a tag that
# doesn't match Cargo.toml.
if ! git diff --quiet -- Cargo.toml Cargo.lock; then
    git commit -q -m "mael: $NEWVER on upstream $TARGET" -- Cargo.toml Cargo.lock
    say "committed the version bump"
fi

# Slashless tags only: `mael/v...` breaks GitHub release-download URLs.
if git rev-parse -q --verify "refs/tags/v$NEWVER" >/dev/null; then
    say "tag v$NEWVER already exists"
else
    git tag "v$NEWVER"
    say "tagged v$NEWVER — publish to your other devices with:
  git push --force-with-lease origin main v$NEWVER"
fi

if [ "${SKIP_DAEMON:-0}" != "1" ]; then
    say "restarting engine"
    systemctl --user restart zeron.service 2>/dev/null || true
fi

# Warn when chat stores diverge: the engine opens exactly one of them.
ACTIVE="$(ls -l /proc/"$(systemctl --user show -p MainPID --value zeron.service 2>/dev/null)"/fd 2>/dev/null \
    | grep -o "$HOME/.zeron/[^ ]*/docs.sqlite3$" | head -n 1 | xargs -r dirname)"
for store in "$HOME"/.zeron/orgs/*/* "$HOME"/.zeron/profiles/*; do
    [ -f "$store/docs.sqlite3" ] || continue
    [ "$store" = "$ACTIVE" ] && continue
    n="$(ls "$store/journals" 2>/dev/null | wc -l)"
    [ "$n" -gt 0 ] && printf '\033[1;33m!! inactive chat store %s (%s journals). Active: %s\033[0m\n' "$store" "$n" "${ACTIVE:-none}"
done

say "done"
"$HOME/.local/bin/zeron" status
