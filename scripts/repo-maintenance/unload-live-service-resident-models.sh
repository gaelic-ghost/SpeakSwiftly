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
unload_url="$base_url/runtime/models/unload"
unload_timeout="${SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_TIMEOUT_SECONDS:-600}"

if ! curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1; then
  warn "No reachable SpeakSwiftlyServer live service at '$base_url'; continuing without resident-model unload preflight."
  exit 0
fi

response_file=$(mktemp "${TMPDIR:-/tmp}/speakswiftly-live-unload.XXXXXX")
trap 'rm -f "$response_file"' EXIT INT TERM

log "Requesting resident-model unload from the live SpeakSwiftlyServer service at '$base_url'."

if ! curl -fsS --max-time "$unload_timeout" -X POST "$unload_url" -H 'accept: application/json' -o "$response_file"; then
  die "SpeakSwiftly live-service resident-model unload preflight failed while POSTing to '$unload_url' after waiting up to ${unload_timeout}s. The live service is reachable, but it did not accept or finish the unload request. If generation or playback is active, unload_models is expected to wait behind that work; rerun after the active request drains or increase SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_TIMEOUT_SECONDS."
fi

if grep -Eq '"resident_state"[[:space:]]*:[[:space:]]*"unloaded"|"worker_stage"[[:space:]]*:[[:space:]]*"resident_models_unloaded"|resident_models_unloaded' "$response_file"; then
  log "Live SpeakSwiftlyServer resident models are unloaded; E2E has memory headroom without uninstalling the service."
else
  die "SpeakSwiftly live-service resident-model unload preflight reached '$unload_url', but the response did not confirm an unloaded resident state. Response: $(tr '\n' ' ' < "$response_file")"
fi
