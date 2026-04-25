#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
  sh "$REPO_MAINTENANCE_ROOT/publish-runtime.sh" --configuration Debug --dry-run
  sh "$REPO_MAINTENANCE_ROOT/publish-runtime.sh" --configuration Release --dry-run
  exit 0
fi

sh "$REPO_MAINTENANCE_ROOT/publish-runtime.sh" --configuration Debug
sh "$REPO_MAINTENANCE_ROOT/verify-runtime.sh" --configuration Debug
sh "$REPO_MAINTENANCE_ROOT/publish-runtime.sh" --configuration Release
sh "$REPO_MAINTENANCE_ROOT/verify-runtime.sh" --configuration Release
