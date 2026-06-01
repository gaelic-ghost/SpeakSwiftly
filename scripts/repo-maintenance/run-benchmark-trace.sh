#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

benchmark_target="qwen-quant"
template="Time Profiler"
audible="false"
playback_trace="false"
iterations=""
qwen_quant_backends=""
device_label=""
time_limit=""
output_root="$REPO_ROOT/.local/traces"

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
    --template)
      template="${2:-}"
      [ -n "$template" ] || die "Pass a non-empty Instruments template name after --template."
      shift 2
      ;;
    --time-profiler)
      template="Time Profiler"
      shift
      ;;
    --metal-system-trace)
      template="Metal System Trace"
      shift
      ;;
    --allocations)
      template="Allocations"
      shift
      ;;
    --vm-tracker)
      template="VM Tracker"
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
      [ -n "$iterations" ] || die "Pass a benchmark iteration count after --iterations."
      shift 2
      ;;
    --backend)
      qwen_quant_backends="${2:-}"
      [ -n "$qwen_quant_backends" ] || die "Pass a backend name after --backend."
      shift 2
      ;;
    --backends)
      qwen_quant_backends="${2:-}"
      [ -n "$qwen_quant_backends" ] || die "Pass comma-separated backend names after --backends."
      shift 2
      ;;
    --device-label)
      device_label="${2:-}"
      [ -n "$device_label" ] || die "Pass a non-empty device label after --device-label."
      shift 2
      ;;
    --time-limit)
      time_limit="${2:-}"
      [ -n "$time_limit" ] || die "Pass an xctrace time limit such as 5m after --time-limit."
      shift 2
      ;;
    --output-root)
      output_root="${2:-}"
      [ -n "$output_root" ] || die "Pass a non-empty output directory after --output-root."
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-benchmark-trace.sh [--qwen|--qwen-quant] [--time-profiler|--metal-system-trace|--allocations|--vm-tracker]
                         [--template <name>] [--iterations <count>] [--backend <backend>|--backends <names>]
                         [--device-label <label>] [--audible] [--playback-trace]
                         [--time-limit <duration>] [--output-root <path>]

Defaults:
  --qwen-quant is the default benchmark target.
  --time-profiler is the default Instruments template.

Examples:
  sh scripts/repo-maintenance/run-benchmark-trace.sh --backend qwen3_smol_8bit --iterations 1
  sh scripts/repo-maintenance/run-benchmark-trace.sh --metal-system-trace --backend qwen3_smol_8bit --iterations 1
  sh scripts/repo-maintenance/run-benchmark-trace.sh --allocations --backend qwen3_smol_8bit --iterations 1
  sh scripts/repo-maintenance/run-benchmark-trace.sh --template "VM Tracker" --backend qwen3_smol_8bit --iterations 1
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-benchmark-trace argument: $1"
      ;;
  esac
done

command -v xcrun >/dev/null 2>&1 || die "xcrun is required to record Instruments traces with xctrace."

stamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
template_slug=$(printf '%s' "$template" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-_')
trace_dir="$output_root/$benchmark_target"
trace_path="$trace_dir/$benchmark_target-$template_slug-$stamp.trace"
mkdir -p "$trace_dir"

set -- record \
  --template "$template" \
  --output "$trace_path" \
  --no-prompt \
  --target-stdout -
if [ -n "$time_limit" ]; then
  set -- "$@" --time-limit "$time_limit"
fi

set -- "$@" --launch -- /bin/sh "$SELF_DIR/run-benchmark.sh" "--$benchmark_target"
if [ "$audible" = "true" ]; then
  set -- "$@" --audible
fi
if [ "$playback_trace" = "true" ]; then
  set -- "$@" --playback-trace
fi
if [ -n "$iterations" ]; then
  set -- "$@" --iterations "$iterations"
fi
if [ -n "$qwen_quant_backends" ]; then
  set -- "$@" --backends "$qwen_quant_backends"
fi
if [ -n "$device_label" ]; then
  set -- "$@" --device-label "$device_label"
fi

log "Recording SpeakSwiftly benchmark '$benchmark_target' with Instruments template '$template'."
log "Trace output: $trace_path"
log "Benchmark JSON output remains under .local/benchmarks."

xcrun xctrace "$@"

log "Recorded benchmark trace: $trace_path"
