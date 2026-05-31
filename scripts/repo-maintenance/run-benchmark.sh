#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

benchmark_target="qwen"
audible="false"
playback_trace="false"
iterations=""
qwen_quant_backends=""
device_label=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --qwen)
      benchmark_target="qwen"
      shift
      ;;
    --qwen-quant)
      benchmark_target="qwen-quant"
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
    --backend)
      qwen_quant_backends="${2:-}"
      shift 2
      ;;
    --backends)
      qwen_quant_backends="${2:-}"
      shift 2
      ;;
    --device-label)
      device_label="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-benchmark.sh [--qwen|--qwen-quant] [--audible] [--playback-trace] [--iterations <count>]
                   [--backend <backend>|--backends <comma-separated-backends>] [--device-label <label>]

Defaults:
  --qwen is the default benchmark target.

Examples:
  sh scripts/repo-maintenance/run-benchmark.sh
  sh scripts/repo-maintenance/run-benchmark.sh --audible --iterations 3
  sh scripts/repo-maintenance/run-benchmark.sh --qwen --iterations 5
  sh scripts/repo-maintenance/run-benchmark.sh --qwen-quant --backend qwen3_smol_8bit --iterations 1
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-benchmark argument: $1"
      ;;
  esac
done

case "$benchmark_target" in
  qwen)
    suite_name="qwen-benchmark"
    ;;
  qwen-quant)
    suite_name="qwen-quant-benchmark"
    ;;
  *)
    die "Unsupported benchmark target '$benchmark_target'."
    ;;
esac

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
if [ "$benchmark_target" = "qwen-quant" ]; then
  suite_args="$suite_args --qwen-quant-benchmark"
  if [ -n "$qwen_quant_backends" ]; then
    suite_args="$suite_args --qwen-quant-backends $qwen_quant_backends"
  fi
  if [ -n "$device_label" ]; then
    suite_args="$suite_args --device-label $device_label"
  fi
fi

log "Running SpeakSwiftly benchmark target '$benchmark_target' via suite '$suite_name'."
# shellcheck disable=SC2086
sh "$SELF_DIR/run-e2e.sh" --suite "$suite_name" $suite_args
