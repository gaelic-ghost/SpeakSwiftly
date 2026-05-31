#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_MAINTENANCE_DIR=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$REPO_MAINTENANCE_DIR/lib"
. "$REPO_MAINTENANCE_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  run-with-live-service-headroom.sh [--clear PATH ...] -- COMMAND [ARG ...]

Unloads live SpeakSwiftlyServer resident models, optionally removes stale local
artifact paths, runs one Core ML/Qwen maintenance command, then reloads live
resident models on exit.

Only paths under .local/coreml-qwen3tts may be cleared.
USAGE
}

clear_paths=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --clear)
      [ "$#" -ge 2 ] || die "--clear requires a path."
      clear_paths="${clear_paths}
$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      die "Unknown argument '$1'. Use -- before the command."
      ;;
  esac
done

[ "$#" -gt 0 ] || die "No command was provided. Use -- COMMAND [ARG ...]."

clear_artifact_path() {
  requested_path="$1"
  case "$requested_path" in
    .local/coreml-qwen3tts/*)
      ;;
    *)
      die "Refusing to clear '$requested_path' because it is outside .local/coreml-qwen3tts."
      ;;
  esac

  artifact_path="$REPO_ROOT/$requested_path"
  if [ -e "$artifact_path" ]; then
    log "Clearing stale Core ML Qwen artifact '$requested_path'."
    rm -rf "$artifact_path"
  else
    log "No stale Core ML Qwen artifact at '$requested_path'."
  fi
}

restore_status=0
restore_live_service() {
  sh "$REPO_MAINTENANCE_DIR/reload-live-service-resident-models.sh" || restore_status=$?
}
trap restore_live_service EXIT INT TERM

sh "$REPO_MAINTENANCE_DIR/unload-live-service-resident-models.sh"

printf '%s\n' "$clear_paths" | while IFS= read -r clear_path; do
  [ -n "$clear_path" ] || continue
  clear_artifact_path "$clear_path"
done

"$@"
command_status=$?

trap - EXIT INT TERM
restore_live_service

if [ "$restore_status" -ne 0 ]; then
  exit "$restore_status"
fi

exit "$command_status"
