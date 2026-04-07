#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

configuration="Debug"
dry_run="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  publish-runtime.sh [--configuration Debug|Release] [--dry-run]
USAGE
      exit 0
      ;;
    *)
      die "Unknown publish-runtime argument: $1"
      ;;
  esac
done

case "$configuration" in
  Debug|Release)
    ;;
  *)
    die "Runtime publication only supports Debug or Release configurations."
    ;;
esac

ensure_git_repo

runtime_root="$REPO_ROOT/.local/xcode"
derived_data_path="$runtime_root/derived-data/$configuration"
source_packages_path="$runtime_root/source-packages"
published_products_path="$runtime_root/$configuration"
temporary_products_path="$runtime_root/.publish-$configuration.$$"
lower_configuration=$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')
metadata_path="$runtime_root/SpeakSwiftly.$lower_configuration.json"
products_path="$derived_data_path/Build/Products/$configuration"
binary_path="$products_path/SpeakSwiftly"
metallib_path="$products_path/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
published_binary_path="$published_products_path/SpeakSwiftly"
published_metallib_path="$published_products_path/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
source_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
exact_tag=$(git -C "$REPO_ROOT" describe --tags --exact-match HEAD 2>/dev/null || true)
source_dirty="false"
status_output=$(git -C "$REPO_ROOT" status --porcelain)
[ -z "$status_output" ] || source_dirty="true"
built_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if ! command -v xcodebuild >/dev/null 2>&1; then
  die "xcodebuild is required to publish a local SpeakSwiftly runtime."
fi

log "Publishing SpeakSwiftly $configuration runtime into $published_products_path"

if [ "$dry_run" = "true" ]; then
  log "Would build with xcodebuild into $derived_data_path and publish products into $published_products_path."
  exit 0
fi

mkdir -p "$runtime_root" "$source_packages_path"

xcodebuild build \
  -scheme SpeakSwiftly \
  -destination "platform=macOS" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path"

[ -x "$binary_path" ] || die "The Xcode build finished, but no executable was found at $binary_path."
[ -f "$metallib_path" ] || die "The Xcode build finished, but the MLX Metal shader bundle was not found at $metallib_path."

rm -rf "$temporary_products_path"
mkdir -p "$temporary_products_path"
cp -R "$products_path"/. "$temporary_products_path"/

[ -x "$temporary_products_path/SpeakSwiftly" ] || die "The published runtime staging directory does not contain an executable SpeakSwiftly binary."
[ -f "$temporary_products_path/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" ] || die "The published runtime staging directory does not contain default.metallib."

rm -rf "$published_products_path"
mv "$temporary_products_path" "$published_products_path"

cat > "$metadata_path" <<EOF
{
  "build_configuration": "$configuration",
  "products_path": "$published_products_path",
  "executable_path": "$published_binary_path",
  "metallib_path": "$published_metallib_path",
  "source_root": "$REPO_ROOT",
  "source_commit": "$source_commit",
  "source_dirty": $source_dirty,
  "release_tag": "$(printf '%s' "$exact_tag")",
  "built_at": "$built_at"
}
EOF

log "Published SpeakSwiftly $configuration runtime:"
log "  products: $published_products_path"
log "  binary:   $published_binary_path"
log "  metallib: $published_metallib_path"
log "  metadata: $metadata_path"
