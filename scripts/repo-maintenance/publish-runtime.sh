#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
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

lower_configuration=$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')
runtime_root="$REPO_ROOT/.local/derived-data/runtime-$lower_configuration"
source_packages_path="$REPO_ROOT/.local/source-packages"
products_path="$runtime_root/Build/Products/$configuration"
launcher_path="$runtime_root/run-speakswiftly"
binary_path="$products_path/SpeakSwiftlyTool"
metallib_path="$products_path/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"

if ! command -v xcodebuild >/dev/null 2>&1; then
  die "xcodebuild is required to build a local SpeakSwiftly runtime."
fi

log "Building SpeakSwiftly $configuration runtime into $runtime_root"

if [ "$dry_run" = "true" ]; then
  log "Would build with xcodebuild into $runtime_root."
  exit 0
fi

mkdir -p "$runtime_root" "$source_packages_path"

xcodebuild build \
  -scheme SpeakSwiftlyTool \
  -destination "platform=macOS" \
  -configuration "$configuration" \
  -derivedDataPath "$runtime_root" \
  -clonedSourcePackagesDirPath "$source_packages_path"

[ -x "$binary_path" ] || die "The Xcode build finished, but no executable was found at $binary_path."
[ -f "$metallib_path" ] || die "The Xcode build finished, but the MLX Metal shader bundle was not found at $metallib_path."

cat > "$launcher_path" <<'EOF'
#!/usr/bin/env sh
set -eu

RUNTIME_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIGURATION="__CONFIGURATION__"
PRODUCTS_DIR="$RUNTIME_ROOT/Build/Products/$CONFIGURATION"
exec env DYLD_FRAMEWORK_PATH="$PRODUCTS_DIR" "$PRODUCTS_DIR/SpeakSwiftlyTool" "$@"
EOF
sed -i '' "s/__CONFIGURATION__/$configuration/" "$launcher_path"
chmod +x "$launcher_path"

[ -x "$launcher_path" ] || die "The runtime launcher script was not created at $launcher_path."

log "Built SpeakSwiftly $configuration runtime:"
log "  runtime:  $runtime_root"
log "  products: $products_path"
log "  binary:   $binary_path"
log "  launcher: $launcher_path"
log "  metallib: $metallib_path"
