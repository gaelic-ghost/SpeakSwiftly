#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

audible="false"
playback_trace="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --audible)
      audible="true"
      shift
      ;;
    --playback-trace)
      playback_trace="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-e2e-full.sh [--audible] [--playback-trace]

Runs the default release-safe top-level E2E suite list sequentially:
  QuickE2ETests
  GeneratedFileE2ETests
  GeneratedBatchE2ETests
  ChatterboxE2ETests
  MarvisE2ETests
  QwenE2ETests
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-e2e-full argument: $1"
      ;;
  esac
done

suite_args=""

if [ "$audible" = "true" ]; then
  suite_args="$suite_args --audible"
fi

if [ "$playback_trace" = "true" ]; then
  suite_args="$suite_args --playback-trace"
fi

run_suite() {
  suite_name="$1"
  log "Running full E2E lane step: $suite_name"
  # shellcheck disable=SC2086
  sh "$SELF_DIR/run-e2e.sh" --suite "$suite_name" $suite_args
}

run_suite QuickE2ETests
run_suite GeneratedFileE2ETests
run_suite GeneratedBatchE2ETests
run_suite ChatterboxE2ETests
run_suite MarvisE2ETests
run_suite QwenE2ETests

log "Full release-safe E2E lane completed successfully."
