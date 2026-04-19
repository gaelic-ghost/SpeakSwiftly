#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

configuration=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  verify-runtime.sh --configuration Debug|Release
USAGE
      exit 0
      ;;
    *)
      die "Unknown verify-runtime argument: $1"
      ;;
  esac
done

[ -n "$configuration" ] || die "Pass --configuration Debug or --configuration Release."

case "$configuration" in
  Debug|Release)
    ;;
  *)
    die "Runtime verification only supports Debug or Release configurations."
    ;;
esac

ensure_git_repo

lower_configuration=$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')
runtime_root="$REPO_ROOT/.local/derived-data/runtime-$lower_configuration"
products_path="$runtime_root/Build/Products/$configuration"
binary_path="$products_path/SpeakSwiftlyTool"
bundle_path="$products_path/mlx-swift_Cmlx.bundle"
metallib_path="$bundle_path/Contents/Resources/default.metallib"
launcher_path="$runtime_root/run-speakswiftly"

[ -d "$products_path" ] || die "The deterministic $configuration runtime products directory is missing at $products_path."
[ -x "$binary_path" ] || die "The deterministic $configuration runtime executable is missing or not executable at $binary_path."
[ -d "$bundle_path" ] || die "The deterministic $configuration MLX bundle directory is missing at $bundle_path."
[ -f "$metallib_path" ] || die "The deterministic $configuration MLX Metal library is missing at $metallib_path."
[ -x "$launcher_path" ] || die "The deterministic $configuration runtime launcher script is missing or not executable at $launcher_path."

log "Verified deterministic SpeakSwiftly $configuration runtime:"
log "  runtime:  $runtime_root"
log "  products: $products_path"
log "  binary:   $binary_path"
log "  launcher: $launcher_path"
log "  metallib: $metallib_path"
