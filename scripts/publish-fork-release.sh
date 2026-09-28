#!/usr/bin/env bash
# Build + publish a one-click fork release.
#
# A fork release is a versioned linux tarball plus the updater metadata the
# engine polls at `{edge}/releases/`:
#   manifest.json  {version, files: {<tarball>: {sha256}}}
#   latest.txt     <version> (fallback for ancient clients)
#
# Usage:
#   scripts/publish-fork-release.sh [--skip-build] [--upload|--print]
#
#   --skip-build   reuse the tarballs already in target/package/
#   --upload       also `wrangler r2 object put` every file (needs
#                  CLOUDFLARE_API_TOKEN for remote R2, or a wrangler that
#                  supports `--local` against the selfhost persist dir —
#                  pass EDGE_PERSIST_DIR=/data for that attempt)
#   --print        (default) just list what would be uploaded
#
# Multi-arch: tarballs are merged by version — run this once per arch (or
# copy other archs' tarballs into target/package/) and the manifest covers
# every `zeron-<VERSION>-*.tar.gz` found. Publish manifest.json BEFORE
# latest.txt so no client ever sees a version without its checksums.
#
# Versioning: the fork updater only treats a release as newer when the
# numeric core grows OR the `-mael.N` suffix grows on an installed `-mael.*`
# build (see `version_newer`). Bump `[workspace.package] version` in
# Cargo.toml before publishing (e.g. 0.2.96-mael.1 → 0.2.96-mael.2).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0
UPLOAD=0
BUCKET="${RELEASES_BUCKET:-zeron-selfhost-releases}"

for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        --upload) UPLOAD=1 ;;
        --print) UPLOAD=0 ;;
        *) echo "unknown arg: $arg (want --skip-build, --upload, --print)" >&2; exit 1 ;;
    esac
done

VERSION="$(grep -m1 '^version' "$ROOT/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')"
RELDIR="$ROOT/target/package/fork-release"
mkdir -p "$RELDIR"

if [ "$SKIP_BUILD" != "1" ]; then
    PROFILE="${PROFILE:-release}" "$ROOT/scripts/package-linux.sh"
fi

shopt -s nullglob
TARBALLS=("$ROOT"/target/package/zeron-"$VERSION"-*.tar.gz)
if [ "${#TARBALLS[@]}" -eq 0 ]; then
    echo "no tarballs for $VERSION in target/package/ (ran package-linux.sh?)" >&2
    exit 1
fi
cp -f "${TARBALLS[@]}" "$RELDIR/"

# manifest.json, same shape the stock release workflow writes (jq like CI).
manifest="$(jq -n --arg version "$VERSION" '{version: $version, files: {}}')"
for f in "$RELDIR"/zeron-"$VERSION"-*.tar.gz; do
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    manifest="$(jq --arg name "$(basename "$f")" --arg sha "$sha" \
        '.files[$name] = {sha256: $sha}' <<<"$manifest")"
done
printf '%s' "$manifest" > "$RELDIR/manifest.json"
printf '%s' "$VERSION" > "$RELDIR/latest.txt"

echo "fork release $VERSION staged in $RELDIR:"
ls -l "$RELDIR"
echo
echo "clients fetch: {edge}/releases/manifest.json (then latest.txt fallback)"

if [ "$UPLOAD" != "1" ]; then
    echo
    echo "next: scripts/publish-fork-release.sh --upload"
    echo "  (remote R2 needs CLOUDFLARE_API_TOKEN; the homelab edge reads the"
    echo "  '$BUCKET' bucket — see FORK.md 'Cutting a one-click fork release')"
    exit 0
fi

# Upload order matters: artifacts, then manifest.json, then latest.txt —
# no client must ever see a version whose files are missing.
for f in "$RELDIR"/zeron-"$VERSION"-*.tar.gz "$RELDIR/manifest.json" "$RELDIR/latest.txt"; do
    key="$(basename "$f")"
    if [ -n "${EDGE_PERSIST_DIR:-}" ]; then
        (cd "$ROOT/edge" && npx wrangler@4 r2 object put "$BUCKET/$key" \
            --file "$f" --local --persist-to "$EDGE_PERSIST_DIR")
    else
        (cd "$ROOT/edge" && npx wrangler@4 r2 object put "$BUCKET/$key" \
            --file "$f" --remote)
    fi
done
echo "published $VERSION to bucket $BUCKET"
