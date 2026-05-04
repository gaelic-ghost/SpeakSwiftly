#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"

if [ "${SPEAKSWIFTLY_SKIP_LIVE_SERVICE_RELOAD:-}" = "1" ]; then
  log "Skipping live-service resident-model reload because SPEAKSWIFTLY_SKIP_LIVE_SERVICE_RELOAD=1."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  warn "curl is not available, so SpeakSwiftly cannot reload resident models from the live service after E2E."
  exit 0
fi

base_url="${SPEAKSWIFTLY_LIVE_SERVICE_BASE_URL:-http://127.0.0.1:7337}"
health_url="$base_url/healthz"
reload_paths="${SPEAKSWIFTLY_LIVE_SERVICE_RELOAD_PATHS:-/models/reload /runtime/models/reload}"

if ! curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1; then
  warn "No reachable SpeakSwiftlyServer live service at '$base_url'; continuing without resident-model reload."
  exit 0
fi

response_file=$(mktemp "${TMPDIR:-/tmp}/speakswiftly-live-reload.XXXXXX")
trap 'rm -f "$response_file"' EXIT INT TERM

log "Requesting resident-model reload from the live SpeakSwiftlyServer service at '$base_url'."

reload_url=""
for reload_path in $reload_paths; do
  candidate_url="$base_url$reload_path"
  if curl -fsS --max-time 180 -X POST "$candidate_url" -H 'accept: application/json' -o "$response_file"; then
    reload_url="$candidate_url"
    break
  fi
done

[ -n "$reload_url" ] || die "SpeakSwiftly live-service resident-model reload failed after trying paths '$reload_paths' at '$base_url'. The live service is reachable, but it did not accept any reload request."

if grep -Eq '"resident_state"[[:space:]]*:[[:space:]]*"ready"|"worker_stage"[[:space:]]*:[[:space:]]*"resident_model_ready"|resident_model_ready' "$response_file"; then
  log "Live SpeakSwiftlyServer resident models are reloaded after E2E."
else
  die "SpeakSwiftly live-service resident-model reload reached '$reload_url', but the response did not confirm a ready resident state. Response: $(tr '\n' ' ' < "$response_file")"
fi
