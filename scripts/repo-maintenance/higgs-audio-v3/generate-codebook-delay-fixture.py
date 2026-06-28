#!/usr/bin/env python3
"""Generate Higgs Audio v3 synthetic delay-pattern fixtures."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT = "docs/research/speech-pipelines/lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json"
NUM_CODEBOOKS = 8
NUM_REAL_CODES = 1024
CODEBOOK_VOCAB_SIZE = 1026
BOC_ID = 1024
EOC_ID = 1025


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def default_raw_codes() -> list[list[int]]:
  return [
    [10, 11, 12, 13, 14, 15, 16, 17],
    [20, 21, 22, 23, 24, 25, 26, 27],
    [30, 31, 32, 33, 34, 35, 36, 37],
  ]


def validate_raw_codes(raw_codes: list[list[int]]) -> None:
  if not raw_codes:
    raise RuntimeError("raw_codes must contain at least one frame.")

  for row_index, row in enumerate(raw_codes):
    if len(row) != NUM_CODEBOOKS:
      raise RuntimeError(
        f"raw_codes row {row_index} has {len(row)} entries, expected {NUM_CODEBOOKS} codebooks."
      )
    for codebook_index, code in enumerate(row):
      if not 0 <= code < NUM_REAL_CODES:
        raise RuntimeError(
          f"raw_codes[{row_index}][{codebook_index}] is {code}, expected a real code in 0..<1024."
        )


def apply_delay_pattern(raw_codes: list[list[int]]) -> list[list[int]]:
  validate_raw_codes(raw_codes)
  frame_count = len(raw_codes)
  delayed_row_count = frame_count + NUM_CODEBOOKS - 1
  delayed = [[EOC_ID for _ in range(NUM_CODEBOOKS)] for _ in range(delayed_row_count)]

  for codebook_index in range(NUM_CODEBOOKS):
    for row_index in range(codebook_index):
      delayed[row_index][codebook_index] = BOC_ID
    for frame_index, raw_row in enumerate(raw_codes):
      delayed[codebook_index + frame_index][codebook_index] = raw_row[codebook_index]

  return delayed


def reverse_delay_pattern(delayed_codes: list[list[int]], frame_count: int) -> list[list[int]]:
  if len(delayed_codes) != frame_count + NUM_CODEBOOKS - 1:
    raise RuntimeError(
      "delayed_codes length does not match frame_count + num_codebooks - 1."
    )

  restored: list[list[int]] = []
  for frame_index in range(frame_count):
    row: list[int] = []
    for codebook_index in range(NUM_CODEBOOKS):
      row.append(delayed_codes[codebook_index + frame_index][codebook_index])
    restored.append(row)
  return restored


def build_fixture(args: argparse.Namespace) -> dict[str, Any]:
  raw_codes = default_raw_codes()
  delayed_codes = apply_delay_pattern(raw_codes)
  restored_codes = reverse_delay_pattern(delayed_codes, len(raw_codes))

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "higgs_audio_v3_codebook_delay_fixture",
    "source": {
      "source_map_path": args.source_map,
      "official_sources": [
        "SGLang-Omni sglang_omni/models/higgs_tts/sampler.py",
        "vLLM-Omni vllm_omni/model_executor/models/higgs_audio_v3/higgs_audio_v3_tokenizer.py",
        "vLLM-Omni vllm_omni/model_executor/stage_input_processors/higgs_audio_v3.py",
      ],
      "no_model_weights_downloaded": True,
    },
    "constants": {
      "num_codebooks": NUM_CODEBOOKS,
      "num_real_codes": NUM_REAL_CODES,
      "codebook_vocab_size": CODEBOOK_VOCAB_SIZE,
      "boc_id": BOC_ID,
      "eoc_id": EOC_ID,
      "delay_pattern": [*range(NUM_CODEBOOKS)],
      "delayed_row_count_formula": "raw_frame_count + num_codebooks - 1",
    },
    "raw_codes": {
      "shape": [len(raw_codes), NUM_CODEBOOKS],
      "rows": raw_codes,
    },
    "delayed_codes": {
      "shape": [len(delayed_codes), NUM_CODEBOOKS],
      "rows": delayed_codes,
      "row_roles": [
        "ramp_in_boc_for_later_codebooks",
        "mixed_real_codes",
        "ramp_down_eoc_for_earlier_codebooks",
      ],
    },
    "reversed_codes": {
      "shape": [len(restored_codes), NUM_CODEBOOKS],
      "rows": restored_codes,
      "matches_raw_codes": restored_codes == raw_codes,
    },
    "streaming_implication": {
      "right_holdback_frames_default": 4,
      "why_it_matters": (
        "Chunked codec decode should hold back trailing rows so delay-pattern "
        "reversal and codec context do not expose unstable tail samples."
      ),
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Generate a synthetic Higgs Audio v3 codebook delay-pattern fixture."
  )
  parser.add_argument(
    "--source-map",
    default="docs/research/speech-pipelines/lanes/higgs-audio-v3/official-pipeline-map-2026-06-24.json",
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
