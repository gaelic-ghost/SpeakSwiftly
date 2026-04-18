#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

suite_arg=""
audible="false"
playback_trace="false"
deep_trace="false"
benchmark="false"
benchmark_iterations=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --suite)
      suite_arg="${2:-}"
      shift 2
      ;;
    --audible)
      audible="true"
      shift
      ;;
    --playback-trace)
      playback_trace="true"
      shift
      ;;
    --deep-trace)
      deep_trace="true"
      shift
      ;;
    --benchmark)
      benchmark="true"
      shift
      ;;
    --benchmark-iterations)
      benchmark_iterations="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  run-e2e.sh --suite <name>

Suite names:
  quick | QuickE2ETests
  generated-file | GeneratedFileE2ETests
  generated-batch | GeneratedBatchE2ETests
  chatterbox | ChatterboxE2ETests
  marvis | MarvisE2ETests
  qwen | QwenE2ETests
  trace | TraceCaptureE2ETests
  deep-trace | DeepTraceE2ETests
  qwen-benchmark | QwenBenchmarkE2ETests

Flags:
  --audible
  --playback-trace
  --deep-trace
  --benchmark
  --benchmark-iterations <count>
USAGE
      exit 0
      ;;
    *)
      die "Unknown run-e2e argument: $1"
      ;;
  esac
done

[ -n "$suite_arg" ] || die "Pass --suite with one top-level E2E suite name."

resolve_suite_name() {
  case "$1" in
    quick|QuickE2ETests) printf '%s\n' "QuickE2ETests" ;;
    generated-file|GeneratedFileE2ETests) printf '%s\n' "GeneratedFileE2ETests" ;;
    generated-batch|GeneratedBatchE2ETests) printf '%s\n' "GeneratedBatchE2ETests" ;;
    chatterbox|ChatterboxE2ETests) printf '%s\n' "ChatterboxE2ETests" ;;
    marvis|MarvisE2ETests) printf '%s\n' "MarvisE2ETests" ;;
    qwen|QwenE2ETests) printf '%s\n' "QwenE2ETests" ;;
    trace|TraceCaptureE2ETests) printf '%s\n' "TraceCaptureE2ETests" ;;
    deep-trace|DeepTraceE2ETests) printf '%s\n' "DeepTraceE2ETests" ;;
    qwen-benchmark|QwenBenchmarkE2ETests) printf '%s\n' "QwenBenchmarkE2ETests" ;;
    *)
      return 1
      ;;
  esac
}

suite_name=$(resolve_suite_name "$suite_arg") \
  || die "Unsupported E2E suite '$suite_arg'. Use --help to see the supported top-level suite names."

case "$suite_name" in
  QuickE2ETests|GeneratedFileE2ETests|GeneratedBatchE2ETests|ChatterboxE2ETests|MarvisE2ETests|QwenE2ETests|TraceCaptureE2ETests|DeepTraceE2ETests|QwenBenchmarkE2ETests)
    ;;
  *)
    die "Refusing to run '$suite_name' because only one top-level E2E suite may run per invocation."
    ;;
esac

if ! command -v swift >/dev/null 2>&1; then
  die "swift is required to run the SpeakSwiftly E2E suite."
fi

export SPEAKSWIFTLY_E2E=1

if [ "$audible" = "true" ]; then
  export SPEAKSWIFTLY_AUDIBLE_E2E=1
fi

if [ "$playback_trace" = "true" ]; then
  export SPEAKSWIFTLY_PLAYBACK_TRACE=1
fi

if [ "$deep_trace" = "true" ]; then
  export SPEAKSWIFTLY_DEEP_TRACE_E2E=1
fi

if [ "$benchmark" = "true" ]; then
  export SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1
fi

if [ -n "$benchmark_iterations" ]; then
  export SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS="$benchmark_iterations"
fi

log "Running SpeakSwiftly E2E suite '$suite_name' through plain SwiftPM."
log "This wrapper intentionally runs exactly one top-level suite per invocation."
(
  cd "$REPO_ROOT"
  swift test --filter "$suite_name"
)
