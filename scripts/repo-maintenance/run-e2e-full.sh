#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
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
  GeneratedFileE2ETests
  GeneratedBatchE2ETests
  ChatterboxE2ETests
  QueueControlE2ETests
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

restore_status=0
test_status=0
restore_needed="false"
restore_live_service() {
  if [ "$restore_needed" = "true" ]; then
    restore_needed="false"
    sh "$SELF_DIR/reload-live-service-resident-models.sh" || restore_status=$?
  fi
}

sh "$SELF_DIR/unload-live-service-resident-models.sh"
restore_needed="true"
trap 'restore_live_service' EXIT
trap 'restore_live_service; exit 129' HUP
trap 'restore_live_service; exit 130' INT
trap 'restore_live_service; exit 143' TERM
export SPEAKSWIFTLY_E2E_LIVE_SERVICE_MANAGED=1

run_suite() {
  suite_name="$1"
  log "Running full E2E lane step: $suite_name"
  set +e
  # shellcheck disable=SC2086
  sh "$SELF_DIR/run-e2e.sh" --suite "$suite_name" $suite_args
  suite_status=$?
  set -e
  return "$suite_status"
}

for suite_name in \
  GeneratedFileE2ETests \
  GeneratedBatchE2ETests \
  ChatterboxE2ETests \
  QueueControlE2ETests \
  MarvisE2ETests \
  QwenE2ETests
do
  set +e
  run_suite "$suite_name"
  suite_status=$?
  set -e
  if [ "$suite_status" -ne 0 ]; then
    test_status="$suite_status"
    break
  fi
done

restore_live_service
trap - EXIT HUP INT TERM

if [ "$test_status" -ne 0 ]; then
  exit "$test_status"
fi

if [ "$restore_status" -ne 0 ]; then
  exit "$restore_status"
fi

log "Full release-safe E2E lane completed successfully."
