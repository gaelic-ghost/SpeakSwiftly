#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

benchmark_target="backend"
audible="false"
playback_trace="false"
iterations=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      benchmark_target="backend"
      shift
      ;;
    --qwen)
      benchmark_target="qwen"
      shift
      ;;
    --audible)
      audible="true"
      shift
      ;;
    --playback-trace)
      playback_trace="true"
      shift
      ;;
    --iterations)
      iterations="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-benchmark.sh [--backend|--qwen] [--audible] [--playback-trace] [--iterations <count>]

Defaults:
  --backend is the default benchmark target.

Examples:
  sh scripts/repo-maintenance/run-benchmark.sh
  sh scripts/repo-maintenance/run-benchmark.sh --audible --iterations 3
  sh scripts/repo-maintenance/run-benchmark.sh --qwen --iterations 5
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-benchmark argument: $1"
      ;;
  esac
done

suite_name="backend-benchmark"
if [ "$benchmark_target" = "qwen" ]; then
  suite_name="qwen-benchmark"
fi

suite_args=""
if [ "$audible" = "true" ]; then
  suite_args="$suite_args --audible"
fi
if [ "$playback_trace" = "true" ]; then
  suite_args="$suite_args --playback-trace"
fi
if [ -n "$iterations" ]; then
  suite_args="$suite_args --benchmark-iterations $iterations"
fi

log "Running SpeakSwiftly benchmark target '$benchmark_target' via suite '$suite_name'."
# shellcheck disable=SC2086
sh "$SELF_DIR/run-e2e.sh" --suite "$suite_name" $suite_args
