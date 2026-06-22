#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "requests>=2.32.0",
# ]
# ///
"""Inspect Hugging Face dataset candidates for Qwen3-TTS Core ML calibration."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Any

import requests


DATASETS_SERVER = "https://datasets-server.huggingface.co"

DEFAULT_CANDIDATES = [
  {
    "dataset": "mythicinfinity/libritts_r",
    "config": "clean",
    "split": "train.clean.100",
    "role": "primary_decoder_calibration",
    "reason": "24 kHz English TTS-oriented speech with transcripts and speaker ids.",
  },
  {
    "dataset": "parler-tts/libritts_r_filtered",
    "config": "clean",
    "split": "train.clean.100",
    "role": "filtered_decoder_calibration",
    "reason": "Filtered LibriTTS-R variant intended to remove restoration and speaker-quality problems.",
  },
  {
    "dataset": "mythicinfinity/libritts",
    "config": "clean",
    "split": "train.clean.100",
    "role": "secondary_decoder_calibration",
    "reason": "Original 24 kHz LibriTTS baseline for comparison with restored LibriTTS-R audio.",
  },
  {
    "dataset": "openslr/librispeech_asr",
    "config": "clean",
    "split": "train.100",
    "role": "broad_read_speech_control",
    "reason": "Large CC-BY English read-speech corpus, but 16 kHz and ASR-oriented.",
  },
  {
    "dataset": "fixie-ai/common_voice_17_0",
    "config": "en",
    "split": "train",
    "role": "accent_and_speaker_diversity_control",
    "reason": "Large English Common Voice mirror with accent, age, gender, and vote metadata.",
  },
]


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def get_json(path: str, params: dict[str, Any]) -> dict[str, Any]:
  response = requests.get(f"{DATASETS_SERVER}{path}", params=params, timeout=60)
  if response.status_code != 200:
    return {
      "status": "failed",
      "status_code": response.status_code,
      "error_message": response.text[:500],
    }
  return {"status": "succeeded", "payload": response.json()}


def split_available(splits_payload: dict[str, Any], config: str, split: str) -> bool:
  return any(
    item.get("config") == config and item.get("split") == split
    for item in splits_payload.get("splits", [])
  )


def sanitize_preview_row(row: dict[str, Any]) -> dict[str, Any]:
  sanitized = {}
  for key, value in row.items():
    if key == "audio":
      sanitized[key] = [
        {
          "type": item.get("type"),
          "src_available": bool(item.get("src")),
        }
        for item in value
      ]
    elif key == "path":
      sanitized[key] = "<dataset-internal-path>"
    else:
      sanitized[key] = value
  return sanitized


def inspect_candidate(candidate: dict[str, str], preview_rows: int) -> dict[str, Any]:
  dataset = candidate["dataset"]
  config = candidate["config"]
  split = candidate["split"]

  splits = get_json("/splits", {"dataset": dataset})
  result: dict[str, Any] = {
    **candidate,
    "hub_url": f"https://hf.co/datasets/{dataset}",
    "dataset_server": {
      "splits_status": splits["status"],
    },
  }

  if splits["status"] != "succeeded":
    result["dataset_server"]["splits_error"] = splits
    return result

  splits_payload = splits["payload"]
  result["available"] = split_available(splits_payload, config, split)
  result["available_splits"] = [
    {"config": item.get("config"), "split": item.get("split")}
    for item in splits_payload.get("splits", [])
  ][:20]

  if not result["available"]:
    return result

  first_rows = get_json(
    "/first-rows",
    {
      "dataset": dataset,
      "config": config,
      "split": split,
    },
  )
  result["dataset_server"]["first_rows_status"] = first_rows["status"]
  if first_rows["status"] != "succeeded":
    result["dataset_server"]["first_rows_error"] = first_rows
    return result

  payload = first_rows["payload"]
  features = payload.get("features", [])
  result["features"] = features
  audio_features = [
    feature
    for feature in features
    if isinstance(feature.get("type"), dict) and feature["type"].get("_type") == "Audio"
  ]
  result["audio_sampling_rates"] = [
    feature["type"].get("sampling_rate")
    for feature in audio_features
  ]
  result["string_columns"] = [
    feature["name"]
    for feature in features
    if isinstance(feature.get("type"), dict) and feature["type"].get("dtype") == "string"
  ]
  result["preview_rows"] = [
    {
      "row_idx": row["row_idx"],
      "row": sanitize_preview_row(row["row"]),
    }
    for row in payload.get("rows", [])[:preview_rows]
  ]
  return result


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  candidates = DEFAULT_CANDIDATES
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_calibration_dataset_inventory",
    "purpose": (
      "Identify open speech datasets for Qwen3-TTS Core ML calibration. "
      "Decoder calibration can start from audio encoded through the Qwen3 12 Hz speech tokenizer; "
      "full-stack W8A8 calibration will need representative text, generated code histories, and reference-conditioning cases."
    ),
    "calibration_scope": {
      "current_graph": "12 Hz speech-tokenizer decoder only",
      "current_input": "audio_codes shaped batch x code_steps x 16 codebooks",
      "not_yet_covered": [
        "text tokenizer",
        "main Qwen3-TTS autoregressive talker",
        "code predictor",
        "speaker embedding and reference conditioning",
        "speech-tokenizer encoder",
      ],
    },
    "candidate_policy": {
      "prefer": [
        "permissive license",
        "24 kHz speech to match Qwen3 tokenizer sample rate",
        "speaker ids for diversity sampling",
        "transcripts for later full-stack calibration",
        "small clean split for first local pass",
      ],
      "avoid_for_first_pass": [
        "gated datasets",
        "unknown license",
        "very large downloads before the sampler is proven",
        "datasets with no audio preview in the Dataset Viewer",
      ],
    },
    "candidates": [
      inspect_candidate(candidate, args.preview_rows)
      for candidate in candidates
    ],
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Inspect Hugging Face dataset candidates for Qwen3-TTS Core ML calibration."
  )
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--preview-rows", type=int, default=2)
  parser.add_argument("--output", default=None)
  return parser.parse_args()


def write_report(report: dict[str, Any], output: str | None) -> None:
  rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
  if output is None:
    sys.stdout.write(rendered)
    return

  with open(output, "w", encoding="utf-8") as file:
    file.write(rendered)


def main() -> int:
  args = parse_args()
  try:
    write_report(build_report(args), args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
