#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"

if [ "${SPEAKSWIFTLY_SKIP_LIVE_SERVICE_UNLOAD:-}" = "1" ]; then
  log "Skipping live-service resident-model unload because SPEAKSWIFTLY_SKIP_LIVE_SERVICE_UNLOAD=1."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  warn "curl is not available, so SpeakSwiftly cannot probe or unload resident models from the live service before E2E."
  exit 0
fi

base_url="${SPEAKSWIFTLY_LIVE_SERVICE_BASE_URL:-http://127.0.0.1:7337}"
health_url="$base_url/healthz"
unload_timeout="${SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_TIMEOUT_SECONDS:-600}"
unload_paths="${SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_PATHS:-/models/unload /runtime/models/unload}"

if ! curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1; then
  warn "No reachable SpeakSwiftlyServer live service at '$base_url'; continuing without resident-model unload preflight."
  exit 0
fi

response_file=$(mktemp "${TMPDIR:-/tmp}/speakswiftly-live-unload.XXXXXX")
trap 'rm -f "$response_file"' EXIT INT TERM

log "Requesting resident-model unload from the live SpeakSwiftlyServer service at '$base_url'."

unload_url=""
for unload_path in $unload_paths; do
  candidate_url="$base_url$unload_path"
  if curl -fsS --max-time "$unload_timeout" -X POST "$candidate_url" -H 'accept: application/json' -o "$response_file"; then
    unload_url="$candidate_url"
    break
  fi
done

[ -n "$unload_url" ] || die "SpeakSwiftly live-service resident-model unload preflight failed after trying paths '$unload_paths' at '$base_url' for up to ${unload_timeout}s each. The live service is reachable, but it did not accept or finish any unload request. If generation or playback is active, unload_models is expected to wait behind that work; rerun after the active request drains or increase SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_TIMEOUT_SECONDS."

if grep -Eq '"resident_state"[[:space:]]*:[[:space:]]*"unloaded"|"worker_stage"[[:space:]]*:[[:space:]]*"resident_models_unloaded"|resident_models_unloaded' "$response_file"; then
  log "Live SpeakSwiftlyServer resident models are unloaded; E2E has memory headroom without uninstalling the service."
else
  die "SpeakSwiftly live-service resident-model unload preflight reached '$unload_url', but the response did not confirm an unloaded resident state. Response: $(tr '\n' ' ' < "$response_file")"
fi
