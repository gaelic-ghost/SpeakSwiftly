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

runtime_root="$REPO_ROOT/.local/xcode"
products_path="$runtime_root/$configuration"
lower_configuration=$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')
metadata_path="$runtime_root/SpeakSwiftly.$lower_configuration.json"
alias_path="$runtime_root/current-$lower_configuration"
binary_path="$products_path/SpeakSwiftly"
bundle_path="$products_path/mlx-swift_Cmlx.bundle"
metallib_path="$bundle_path/Contents/Resources/default.metallib"
launcher_path="$products_path/run-speakswiftly"

[ -d "$products_path" ] || die "The published $configuration runtime directory is missing at $products_path."
[ -x "$binary_path" ] || die "The published $configuration runtime executable is missing or not executable at $binary_path."
[ -d "$bundle_path" ] || die "The published $configuration MLX bundle directory is missing at $bundle_path."
[ -f "$metallib_path" ] || die "The published $configuration MLX Metal library is missing at $metallib_path."
[ -x "$launcher_path" ] || die "The published $configuration runtime launcher script is missing or not executable at $launcher_path."
[ -f "$metadata_path" ] || die "The published $configuration runtime metadata manifest is missing at $metadata_path."
[ -L "$alias_path" ] || die "The published $configuration runtime alias is missing at $alias_path."

grep -q "\"build_configuration\": \"$configuration\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not record the expected build configuration."
grep -q "\"products_path\": \"$products_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at the published products directory."
grep -q "\"bundle_path\": \"$bundle_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at the published MLX bundle."
grep -q "\"executable_path\": \"$binary_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at the published executable."
grep -q "\"launcher_path\": \"$launcher_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at the published launcher."
grep -q "\"metallib_path\": \"$metallib_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at default.metallib."
grep -q "\"alias_path\": \"$alias_path\"" "$metadata_path" \
  || die "The $configuration runtime metadata manifest at $metadata_path does not point at the stable runtime alias."

resolved_alias_path=$(cd "$(dirname "$alias_path")" && realpath "$(basename "$alias_path")")
[ "$resolved_alias_path" = "$products_path" ] \
  || die "The published $configuration runtime alias at $alias_path resolves to $resolved_alias_path instead of $products_path."

log "Verified published SpeakSwiftly $configuration runtime:"
log "  products: $products_path"
log "  alias:    $alias_path"
log "  binary:   $binary_path"
log "  launcher: $launcher_path"
log "  metallib: $metallib_path"
log "  metadata: $metadata_path"
