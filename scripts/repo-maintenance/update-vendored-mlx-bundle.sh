#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

source_bundle_path="$REPO_ROOT/.local/xcode/Release/mlx-swift_Cmlx.bundle"
vendored_bundle_path="$REPO_ROOT/Sources/SpeakSwiftly/Resources/mlx-swift_Cmlx.bundle"
source_metallib_path="$source_bundle_path/Contents/Resources/default.metallib"
vendored_metallib_path="$vendored_bundle_path/Contents/Resources/default.metallib"

ensure_git_repo

[ -d "$source_bundle_path" ] || die "The published Release MLX bundle was not found at $source_bundle_path. Run 'sh scripts/repo-maintenance/publish-runtime.sh --configuration Release' first."
[ -f "$source_metallib_path" ] || die "The published Release MLX metallib was not found at $source_metallib_path."

rm -rf "$vendored_bundle_path"
mkdir -p "$(dirname "$vendored_bundle_path")"
cp -R "$source_bundle_path" "$vendored_bundle_path"

[ -f "$vendored_metallib_path" ] || die "The vendored MLX metallib refresh did not produce $vendored_metallib_path."

log "Updated vendored MLX shader bundle:"
log "  source:   $source_bundle_path"
log "  vendored: $vendored_bundle_path"
log "  metallib: $vendored_metallib_path"
