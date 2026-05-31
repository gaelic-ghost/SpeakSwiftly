#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

ensure_git_repo

input_root="$REPO_ROOT/.local/benchmarks/qwen-quant"
output_root="$input_root/summaries"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input-root)
      input_root="${2:-}"
      [ -n "$input_root" ] || die "Pass a non-empty input root after --input-root."
      shift 2
      ;;
    --output-root)
      output_root="${2:-}"
      [ -n "$output_root" ] || die "Pass a non-empty output root after --output-root."
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  summarize-qwen-quant-benchmark.sh [--input-root <path>] [--output-root <path>]

Reads each <input-root>/<device>/latest.json and writes a Markdown comparison
report under <output-root>.
USAGE
      exit 0
      ;;
    *)
      die "Unknown summarize-qwen-quant-benchmark argument: $1"
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required to summarize qwen quant benchmark JSON artifacts."
[ -d "$input_root" ] || die "Qwen quant benchmark input root '$input_root' does not exist."

mkdir -p "$output_root"
stamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
report_path="$output_root/qwen-quant-comparison-$stamp.md"
latest_path="$output_root/qwen-quant-comparison-latest.md"

{
  printf '# Qwen Quant Benchmark Comparison\n\n'
  printf 'Generated: `%s`\n\n' "$stamp"
  printf '| Device | Backend | Completed | Failed | Timed out | Live first audio avg ms | Live complete avg ms | Peak resident GB | Quality warnings |\n'
  printf '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n'

  find "$input_root" -mindepth 2 -maxdepth 2 -name latest.json -print | sort | while IFS= read -r summary_file; do
    jq -r '
      def fmt($value): if $value == null then "n/a" else (($value * 100 | round) / 100 | tostring) end;
      def avg($values): if ($values | length) == 0 then "n/a" else fmt(($values | add) / ($values | length)) end;
      .deviceLabel as $device
      | .backends[]
      | .backend as $backend
      | [.outcomes[] | select(.status == "completed")] as $completed
      | [.outcomes[] | select(.status == "failed")] as $failed
      | [.outcomes[] | select(.status == "timedOut")] as $timedOut
      | [$completed[].sample.liveSpeech.generation.firstAudioChunkAtMS] as $firstAudio
      | [$completed[].sample.liveSpeech.lifecycle.completedAtMS] as $completedMS
      | [$completed[].sample.resources.processResidentBytes] as $resident
      | [$completed[].sample.warnings.generationQualityWarningCount] as $qualityWarnings
      | [
          $device,
          $backend,
          ($completed | length | tostring),
          ($failed | length | tostring),
          ($timedOut | length | tostring),
          avg($firstAudio),
          avg($completedMS),
          (if ($resident | length) == 0 then "n/a" else fmt(($resident | max) / 1073741824) end),
          (if ($qualityWarnings | length) == 0 then "0" else ($qualityWarnings | add | tostring) end)
        ]
      | "| " + join(" | ") + " |"
    ' "$summary_file"
  done

  printf '\n## Default Candidate Signals\n\n'
  find "$input_root" -mindepth 2 -maxdepth 2 -name latest.json -print | sort | while IFS= read -r summary_file; do
    jq -r '
      def fmt($value): if $value == null then "n/a" else (($value * 100 | round) / 100 | tostring) end;
      def avg($values): if ($values | length) == 0 then null else (($values | add) / ($values | length)) end;
      .deviceLabel as $device
      | .backends[]
      | .backend as $backend
      | [.outcomes[] | select(.status == "completed")] as $completed
      | [.outcomes[] | select(.status == "failed" or .status == "timedOut")] as $incomplete
      | [$completed[].sample.warnings.generationQualityWarningCount] as $qualityWarnings
      | [$completed[].sample.liveSpeech.generation.firstAudioChunkAtMS] as $firstAudio
      | select(($completed | length) > 0 and ($incomplete | length) == 0 and (($qualityWarnings | add // 0) == 0))
      | "- `" + $device + "` candidate: `" + $backend + "` completed all recorded samples with no generation-quality warnings; average live first audio `" + fmt(avg($firstAudio)) + "` ms."
    ' "$summary_file"
  done

  printf '\n## Variants To Review Or Prune\n\n'
  find "$input_root" -mindepth 2 -maxdepth 2 -name latest.json -print | sort | while IFS= read -r summary_file; do
    jq -r '
      .deviceLabel as $device
      | .backends[]
      | .backend as $backend
      | [.outcomes[] | select(.status == "failed")] as $failed
      | [.outcomes[] | select(.status == "timedOut")] as $timedOut
      | [.outcomes[] | select(.status == "completed")] as $completed
      | [$completed[].sample.warnings.generationQualityWarningCount] as $qualityWarnings
      | ($qualityWarnings | add // 0) as $qualityWarningCount
      | select(($failed | length) > 0 or ($timedOut | length) > 0 or $qualityWarningCount > 0)
      | "- `" + $device + "` review: `" + $backend + "` has failed samples `" + ($failed | length | tostring) + "`, timed-out samples `" + ($timedOut | length | tostring) + "`, and generation-quality warnings `" + ($qualityWarningCount | tostring) + "`."
    ' "$summary_file"
  done

  printf '\n## Notes\n\n'
  printf -- '- Treat failed backend rows as benchmark evidence, especially on memory-constrained machines.\n'
  printf -- '- Prefer a default only when first-audio latency, completion time, memory, and quality warning counts are all acceptable for that device.\n'
  printf -- '- Keep raw JSON artifacts local unless they have been reviewed for machine-local paths and private data.\n'
} > "$report_path"

cp "$report_path" "$latest_path"

log "Wrote qwen quant benchmark report: $report_path"
log "Updated latest qwen quant benchmark report: $latest_path"
