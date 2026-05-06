#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required to refresh SpeakSwiftly E2E profile fixtures."
}

require_command swift
require_command jq

fixture_root="$REPO_ROOT/Tests/SpeakSwiftlyTests/Resources/E2EProfiles/profiles"
work_root="$REPO_ROOT/.local/e2e-profile-fixture-refresh"
profile_root="$work_root/store"

log "Refreshing E2E profile fixtures in $fixture_root"
rm -rf "$work_root"
mkdir -p "$profile_root"

create_design_profile() {
  profile_name="$1"
  vibe="$2"
  voice_description="$3"

  log "Creating fixture profile: $profile_name"
  (
    cd "$REPO_ROOT"
    swift run SpeakSwiftlyProbeTool create-design-profile \
      --profile "$profile_name" \
      --vibe "$vibe" \
      --voice "$voice_description" \
      --text "This imported reference audio should let SpeakSwiftly build a clone profile for end to end coverage with a clean transcript and steady speech." \
      --profile-root "$profile_root"
  )
}

copy_fixture_profile() {
  profile_name="$1"
  source_dir="$profile_root/profiles/$profile_name"

  [ -d "$source_dir" ] || die "Expected generated profile fixture at $source_dir."
  rm -rf "$fixture_root/$profile_name"
  mkdir -p "$fixture_root"
  cp -R "$source_dir" "$fixture_root/$profile_name"
}

derive_clone_fixture() {
  source_name="$1"
  target_name="$2"
  transcript_source="$3"
  transcription_model_repo="$4"

  rm -rf "$fixture_root/$target_name"
  cp -R "$fixture_root/$source_name" "$fixture_root/$target_name"

  if [ "$transcription_model_repo" = "null" ]; then
    jq \
      --arg profile_name "$target_name" \
      --arg transcript_source "$transcript_source" \
      '.profileName = $profile_name
        | .sourceKind = "imported_clone"
        | .modelRepo = "SpeakSwiftly/imported-reference-audio"
        | .voiceDescription = "Imported reference audio clone."
        | .transcriptProvenance = {
            "source": $transcript_source,
            "createdAt": .createdAt,
            "transcriptionModelRepo": null
          }' \
      "$fixture_root/$target_name/profile.json" > "$fixture_root/$target_name/profile.json.tmp"
  else
    jq \
      --arg profile_name "$target_name" \
      --arg transcript_source "$transcript_source" \
      --arg transcription_model_repo "$transcription_model_repo" \
      '.profileName = $profile_name
        | .sourceKind = "imported_clone"
        | .modelRepo = "SpeakSwiftly/imported-reference-audio"
        | .voiceDescription = "Imported reference audio clone."
        | .transcriptProvenance = {
            "source": $transcript_source,
            "createdAt": .createdAt,
            "transcriptionModelRepo": $transcription_model_repo
          }' \
      "$fixture_root/$target_name/profile.json" > "$fixture_root/$target_name/profile.json.tmp"
  fi

  mv "$fixture_root/$target_name/profile.json.tmp" "$fixture_root/$target_name/profile.json"
}

create_design_profile \
  e2e-masc-design \
  masc \
  "A generic, warm, masculine, slow speaking voice."
create_design_profile \
  e2e-femme-design \
  femme \
  "A warm, bright, feminine narrator voice."

copy_fixture_profile e2e-masc-design
copy_fixture_profile e2e-femme-design
derive_clone_fixture \
  e2e-masc-design \
  e2e-masc-clone-provided \
  provided \
  null
derive_clone_fixture \
  e2e-masc-design \
  e2e-masc-clone-inferred \
  inferred \
  mlx-community/GLM-ASR-Nano-2512-4bit

rm -rf "$work_root"
log "E2E profile fixtures refreshed successfully."
