#!/usr/bin/env python3
"""Generate Higgs Audio v3 codec/vocoder boundary fixtures."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_SOURCE_MAP = "docs/research/speech-pipelines/lanes/higgs-audio-v3/official-pipeline-map-2026-06-24.json"
DEFAULT_DELAY_FIXTURE = "docs/research/speech-pipelines/lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json"
DEFAULT_OUTPUT = "docs/research/speech-pipelines/lanes/higgs-audio-v3/codec-vocoder-boundary-fixture-2026-06-28.json"

CODEC_PREFIX = "tied.embedding.modality_embeddings.0.model."
TEXT_BODY_PREFIX = "body.layers."
AUDIO_EMBEDDING_PREFIX = "tied.embedding.modality_embeddings.0.embedding"
TIED_HEAD_PREFIX = "tied.head"
SAMPLE_RATE_HZ = 24000


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def read_json(path: Path) -> dict[str, Any]:
  with path.open("r", encoding="utf-8") as handle:
    value = json.load(handle)

  if not isinstance(value, dict):
    raise RuntimeError(f"{path} must contain a JSON object.")
  return value


def prefix_summary(source_map: dict[str, Any], prefix: str) -> dict[str, Any]:
  weight_index = source_map.get("hugging_face", {}).get("weight_index", {})
  prefixes = weight_index.get("prefixes", {})
  summary = prefixes.get(prefix)
  if summary is None:
    return {"count": 0, "examples": []}
  if not isinstance(summary, dict):
    raise RuntimeError(f"weight prefix '{prefix}' must contain an object summary.")
  return summary


def require_int(value: Any, description: str) -> int:
  if not isinstance(value, int):
    raise RuntimeError(f"{description} must be an integer.")
  return value


def require_list(value: Any, description: str) -> list[Any]:
  if not isinstance(value, list):
    raise RuntimeError(f"{description} must be a list.")
  return value


def build_fixture(args: argparse.Namespace) -> dict[str, Any]:
  source_map = read_json(args.source_map)
  delay_fixture = read_json(args.codebook_delay_fixture)

  weight_index = source_map.get("hugging_face", {}).get("weight_index", {})
  codec_summary = prefix_summary(source_map, CODEC_PREFIX)
  text_body_summary = prefix_summary(source_map, TEXT_BODY_PREFIX)
  audio_embedding_summary = prefix_summary(source_map, AUDIO_EMBEDDING_PREFIX)
  tied_head_summary = prefix_summary(source_map, TIED_HEAD_PREFIX)
  codec_vocoder_map = source_map.get("component_map", {}).get("codec_vocoder", {})
  output_container_map = source_map.get("component_map", {}).get("output_container", {})
  constants = delay_fixture.get("constants", {})

  raw_shape = require_list(delay_fixture.get("raw_codes", {}).get("shape"), "raw code shape")
  delayed_shape = require_list(delay_fixture.get("delayed_codes", {}).get("shape"), "delayed code shape")
  reversed_shape = require_list(delay_fixture.get("reversed_codes", {}).get("shape"), "reversed code shape")

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "higgs_audio_v3_codec_vocoder_boundary_fixture",
    "source": {
      "source_map_path": str(args.source_map),
      "codebook_delay_fixture_path": str(args.codebook_delay_fixture),
      "official_sources": {
        "codec_vocoder": codec_vocoder_map.get("official_sources", []),
        "output_container": output_container_map.get("official_sources", []),
      },
      "no_model_weights_downloaded": True,
    },
    "codec_vocoder_weight_boundary": {
      "codec_checkpoint_prefix": CODEC_PREFIX,
      "codec_weight_entry_count": require_int(
        codec_summary.get("count"),
        f"weight count for {CODEC_PREFIX}",
      ),
      "codec_weight_examples": require_list(
        codec_summary.get("examples", []),
        f"weight examples for {CODEC_PREFIX}",
      ),
      "total_weight_entry_count": require_int(
        weight_index.get("weight_entry_count"),
        "total weight entry count",
      ),
      "total_weight_size_bytes": require_int(
        weight_index.get("metadata", {}).get("total_size"),
        "total weight size",
      ),
      "text_body_prefix": TEXT_BODY_PREFIX,
      "text_body_weight_entry_count": require_int(
        text_body_summary.get("count"),
        f"weight count for {TEXT_BODY_PREFIX}",
      ),
      "audio_embedding_prefix": AUDIO_EMBEDDING_PREFIX,
      "audio_embedding_weight_entry_count": require_int(
        audio_embedding_summary.get("count"),
        f"weight count for {AUDIO_EMBEDDING_PREFIX}",
      ),
      "separate_tied_head_weight_entry_count": require_int(
        tied_head_summary.get("count"),
        f"weight count for {TIED_HEAD_PREFIX}",
      ),
      "useful_backend_requires_codec_vocoder": True,
      "negative_check": codec_vocoder_map.get("highest_risk"),
    },
    "codebook_decode_boundary": {
      "raw_codes_shape": raw_shape,
      "delayed_codes_shape": delayed_shape,
      "reversed_codes_shape": reversed_shape,
      "codebook_axis_order": "frame_major_rows_codebook_columns",
      "boc_id": require_int(constants.get("boc_id"), "BOC id"),
      "eoc_id": require_int(constants.get("eoc_id"), "EOC id"),
      "filtering_rule": "reverse_delay_pattern_then_remove_boc_eoc_markers_before_codec_decode",
      "sample_rate_hz": SAMPLE_RATE_HZ,
      "sample_rate_source": "official inventory and serving source snippets",
      "output_sample_count_known": False,
      "output_dtype_known": False,
      "output_channel_count_known": False,
    },
    "output_container_boundary": {
      "non_streaming_container_known": False,
      "streaming_container_conflict": output_container_map.get("known_conflict"),
      "streaming_pcm_is_current_serving_signal": True,
      "requires_future_official_serving_comparison": True,
    },
    "streaming_chunk_defaults": {
      "codec_chunk_frames": 25,
      "codec_left_context_frames": 25,
      "codec_right_holdback_frames": 4,
      "initial_codec_chunk_frames": 1,
    },
    "promotion_gate": {
      "graph_only_text_to_codebook_is_not_sufficient": True,
      "runtime_integration_allowed": False,
      "next_required_evidence": [
        "official serving comparison for the same prompt fixture",
        "waveform metadata capture",
        "decoded sample count capture",
        "decoded dtype capture",
        "decoded channel count capture",
      ],
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Generate a no-weight Higgs Audio v3 codec/vocoder boundary fixture."
  )
  parser.add_argument("--source-map", type=Path, default=Path(DEFAULT_SOURCE_MAP))
  parser.add_argument(
    "--codebook-delay-fixture",
    type=Path,
    default=Path(DEFAULT_DELAY_FIXTURE),
  )
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
  return parser.parse_args()


def write_fixture(fixture: dict[str, Any], output: Path | None) -> None:
  rendered = json.dumps(fixture, indent=2, ensure_ascii=False) + "\n"
  if output is None:
    sys.stdout.write(rendered)
    return

  output.parent.mkdir(parents=True, exist_ok=True)
  output.write_text(rendered, encoding="utf-8")


def main() -> int:
  args = parse_args()
  try:
    write_fixture(build_fixture(args), args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
