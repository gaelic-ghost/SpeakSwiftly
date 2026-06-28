#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

backends=""
device_label=""
audible="false"
playback_trace="true"
iterations="1"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      backends="${2:-}"
      [ -n "$backends" ] || die "Pass a backend after --backend."
      shift 2
      ;;
    --backends)
      backends="${2:-}"
      [ -n "$backends" ] || die "Pass a comma-separated backend list after --backends."
      shift 2
      ;;
    --all)
      backends=""
      shift
      ;;
    --device-label)
      device_label="${2:-}"
      [ -n "$device_label" ] || die "Pass a non-empty device label after --device-label."
      shift 2
      ;;
    --iterations)
      iterations="${2:-}"
      [ -n "$iterations" ] || die "Pass an iteration count after --iterations."
      shift 2
      ;;
    --audible)
      audible="true"
      shift
      ;;
    --no-playback-trace)
      playback_trace="false"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-qwen-quant-benchmark.sh [--backend <backend>|--backends <comma-separated-backends>|--all]
                              [--device-label <label>] [--iterations <count>]
                              [--audible] [--no-playback-trace]

Examples:
  sh scripts/repo-maintenance/run-qwen-quant-benchmark.sh --backend qwen3_smol_8bit --iterations 1
  sh scripts/repo-maintenance/run-qwen-quant-benchmark.sh --all --device-label macbook-pro-m4-pro-24gb
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-qwen-quant-benchmark argument: $1"
      ;;
  esac
done

if [ -n "$backends" ]; then
  export SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_BACKENDS="$backends"
fi
if [ -n "$device_label" ]; then
  export SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_DEVICE_LABEL="$device_label"
fi

set -- "$SELF_DIR/run-benchmark.sh" --qwen-quantization --iterations "$iterations"
if [ "$audible" = "true" ]; then
  set -- "$@" --audible
fi
if [ "$playback_trace" = "true" ]; then
  set -- "$@" --playback-trace
fi

sh "$@"
