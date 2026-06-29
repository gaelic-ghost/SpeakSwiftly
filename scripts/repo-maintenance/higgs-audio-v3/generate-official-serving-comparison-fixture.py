#!/usr/bin/env python3
"""Generate Higgs Audio v3 official-serving comparison fixtures."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_SOURCE_MAP = "docs/research/speech-pipelines/lanes/higgs-audio-v3/official-pipeline-map-2026-06-24.json"
DEFAULT_TOKENIZER_FIXTURE = "docs/research/speech-pipelines/lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json"
DEFAULT_CODEC_FIXTURE = "docs/research/speech-pipelines/lanes/higgs-audio-v3/codec-vocoder-boundary-fixture-2026-06-28.json"
DEFAULT_OUTPUT = "docs/research/speech-pipelines/lanes/higgs-audio-v3/official-serving-comparison-fixture-2026-06-29.json"


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


def require_int(value: Any, description: str) -> int:
  if not isinstance(value, int):
    raise RuntimeError(f"{description} must be an integer.")
  return value


def require_bool(value: Any, description: str) -> bool:
  if not isinstance(value, bool):
    raise RuntimeError(f"{description} must be a boolean.")
  return value


def require_list(value: Any, description: str) -> list[Any]:
  if not isinstance(value, list):
    raise RuntimeError(f"{description} must be a list.")
  return value


def prompt_case(tokenizer_fixture: dict[str, Any], name: str) -> dict[str, Any]:
  cases = require_list(tokenizer_fixture.get("cases"), "tokenizer fixture cases")
  for candidate in cases:
    if isinstance(candidate, dict) and candidate.get("name") == name:
      return candidate
  raise RuntimeError(f"tokenizer fixture does not contain case '{name}'.")


def build_fixture(args: argparse.Namespace) -> dict[str, Any]:
  source_map = read_json(args.source_map)
  tokenizer_fixture = read_json(args.tokenizer_fixture)
  codec_fixture = read_json(args.codec_fixture)

  component_map = source_map.get("component_map", {})
  output_container_map = component_map.get("output_container", {})
  waveform_map = component_map.get("waveform_post_processing", {})
  prompt = prompt_case(tokenizer_fixture, args.prompt_case)
  runtime_constants = tokenizer_fixture.get("official_runtime_constants", {})
  codec_decode = codec_fixture.get("codebook_decode_boundary", {})
  streaming_defaults = codec_fixture.get("streaming_chunk_defaults", {})

  sample_rate_hz = require_int(runtime_constants.get("sample_rate_hz"), "sample rate")
  codec_chunk_frames = require_int(streaming_defaults.get("codec_chunk_frames"), "codec chunk frames")

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "higgs_audio_v3_official_serving_comparison_fixture",
    "source": {
      "source_map_path": str(args.source_map),
      "tokenizer_fixture_path": str(args.tokenizer_fixture),
      "codec_fixture_path": str(args.codec_fixture),
      "official_sources": {
        "waveform_post_processing": waveform_map.get("official_sources", []),
        "output_container": output_container_map.get("official_sources", []),
      },
      "no_model_weights_downloaded": True,
      "no_serving_request_executed": True,
    },
    "prompt_case": {
      "name": prompt.get("name"),
      "kind": prompt.get("kind"),
      "raw_text": prompt.get("raw_text"),
      "prompt_shape": prompt.get("prompt_shape"),
      "prompt_length": require_int(prompt.get("prompt_length"), "prompt length"),
    },
    "official_serving_signals": [
      {
        "source": "vLLM HIGGS_AUDIO_V3_PIPELINE docstring",
        "signal": "Talker text-to-eight-codebook rows feed Code2Wav codec-to-24-kHz-PCM output.",
        "captured_from": "official-pipeline-map key lines for vllm_omni/model_executor/pipeline_configs/higgs_audio_v3.py",
      },
      {
        "source": "vLLM Higgs multimodal deploy YAML",
        "signal": "async_chunk streams PCM bytes back to the client as Stage 1 emits each chunk.",
        "captured_from": "official-pipeline-map key lines for vllm_omni/deploy/higgs_multimodal_qwen3.yaml",
      },
      {
        "source": "Boson/SGLang current serving docs versus model-card wording",
        "signal": output_container_map.get("known_conflict"),
        "captured_from": "official-pipeline-map component_map.output_container.known_conflict",
      },
    ],
    "non_streaming_output_contract": {
      "container_known": False,
      "container": None,
      "serving_signal": "not captured by the current no-weight source map",
      "requires_executed_official_serving_request": True,
    },
    "streaming_output_contract": {
      "container_known": True,
      "container": "raw_pcm_bytes",
      "container_conflict_preserved": output_container_map.get("known_conflict"),
      "pcm_signal_source": "vLLM deploy YAML",
      "base64_wav_signal_still_unresolved": True,
      "requires_executed_official_serving_request": True,
    },
    "waveform_metadata": {
      "sample_rate_hz": sample_rate_hz,
      "sample_rate_confirmed_by_source_map": sample_rate_hz == require_int(
        codec_decode.get("sample_rate_hz"),
        "codec fixture sample rate",
      ),
      "decoded_sample_count_known": False,
      "decoded_dtype_known": False,
      "decoded_channel_count_known": False,
      "observed_decoded_sample_count": None,
      "observed_decoded_dtype": None,
      "observed_decoded_channel_count": None,
      "requires_executed_official_serving_request": True,
    },
    "streaming_chunk_expectations": {
      "codec_chunk_frames": codec_chunk_frames,
      "codec_left_context_frames": require_int(
        streaming_defaults.get("codec_left_context_frames"),
        "codec left context frames",
      ),
      "codec_right_holdback_frames": require_int(
        streaming_defaults.get("codec_right_holdback_frames"),
        "codec right holdback frames",
      ),
      "initial_codec_chunk_frames": require_int(
        streaming_defaults.get("initial_codec_chunk_frames"),
        "initial codec chunk frames",
      ),
      "nominal_seconds_per_codec_chunk": codec_chunk_frames / 25,
      "nominal_codec_frame_rate_hz": 25,
    },
    "promotion_gate": {
      "runtime_integration_allowed": False,
      "official_serving_comparison_started": True,
      "official_serving_request_executed": False,
      "remaining_blockers": [
        "execute one official serving request for the plain prompt fixture",
        "capture non-streaming container behavior",
        "capture decoded sample count",
        "capture decoded dtype",
        "capture decoded channel count",
        "resolve raw PCM versus WAV/base64 streaming contract with observed output",
      ],
      "codec_fixture_runtime_promotion_allowed": require_bool(
        codec_fixture.get("promotion_gate", {}).get("runtime_integration_allowed"),
        "codec fixture runtime promotion flag",
      ),
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Generate a no-weight Higgs Audio v3 official-serving comparison fixture."
  )
  parser.add_argument("--source-map", type=Path, default=Path(DEFAULT_SOURCE_MAP))
  parser.add_argument(
    "--tokenizer-fixture",
    type=Path,
    default=Path(DEFAULT_TOKENIZER_FIXTURE),
  )
  parser.add_argument("--codec-fixture", type=Path, default=Path(DEFAULT_CODEC_FIXTURE))
  parser.add_argument("--prompt-case", default="plain-english-tts")
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
