#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

vendored_metallib_path="$REPO_ROOT/Sources/SpeakSwiftly/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
test_metallib_path="$REPO_ROOT/Tests/SpeakSwiftlyTests/Resources/default.metallib"

[ -f "$vendored_metallib_path" ] || die "The vendored MLX metallib is missing at $vendored_metallib_path."
[ -f "$test_metallib_path" ] || die "The test-target MLX metallib is missing at $test_metallib_path. Run 'sh scripts/repo-maintenance/update-vendored-mlx-bundle.sh' to refresh it."

if ! cmp -s "$vendored_metallib_path" "$test_metallib_path"; then
  die "The test-target MLX metallib at $test_metallib_path does not match the vendored MLX metallib at $vendored_metallib_path. Run 'sh scripts/repo-maintenance/update-vendored-mlx-bundle.sh' to refresh both copies together."
fi

log "Verified MLX metallib resources:"
log "  vendored: $vendored_metallib_path"
log "  test:     $test_metallib_path"
