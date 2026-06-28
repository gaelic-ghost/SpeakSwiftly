#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# ///
"""Plan fixed-shape Core ML decoder buckets for Qwen3-TTS calibration codes."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_CALIBRATION_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json"
DEFAULT_RUNTIME_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def package_root() -> Path:
  return Path(__file__).resolve().parents[3]


def resolve_package_path(path: Path) -> Path:
  return path if path.is_absolute() else package_root() / path


def load_json(path: Path) -> dict[str, Any]:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception as error:
    raise RuntimeError(f"Unable to read JSON file at '{path}'.") from error


def bucket_for_steps(code_steps: int, buckets: list[int]) -> int:
  for bucket in sorted(buckets):
    if code_steps <= bucket:
      return bucket
  raise RuntimeError(
    f"No decoder bucket can hold {code_steps} code steps. "
    f"Available buckets: {buckets}."
  )


def sample_assignments(calibration_fixture: dict[str, Any], buckets: list[int]) -> list[dict[str, Any]]:
  assignments = []
  code_step_samples = calibration_fixture["calibration_scope"]["code_step_samples"]
  for sample in calibration_fixture.get("samples", []):
    shape = sample["encoded"]["audio_codes_shape"]
    code_steps = shape[0]
    quantizer_count = shape[1]
    bucket = bucket_for_steps(code_steps, buckets)
    assignments.append(
      {
        "id": sample.get("id"),
        "audio_codes_shape": shape,
        "assigned_bucket": bucket,
        "bucket_input_shape": [1, bucket, quantizer_count],
        "pad_value": -1,
        "padded_step_count": bucket - code_steps,
        "padded_output_sample_count": bucket * code_step_samples,
        "valid_output_sample_count": code_steps * code_step_samples,
      }
    )
  return assignments


def conversion_commands(args: argparse.Namespace, buckets: list[int]) -> list[dict[str, Any]]:
  commands = []
  for bucket in buckets:
    suffix = f"bucket-{bucket}"
    commands.append(
      {
        "bucket": bucket,
        "input_shape": [1, bucket, 16],
        "report_output": f".local/coreml-qwen3tts/qwen3tts-speech-tokenizer-decoder-conversion-{suffix}.json",
        "mlpackage_output": (
          ".local/coreml-qwen3tts/"
          f"Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-{suffix}.mlpackage"
        ),
        "command": (
          "uv run --python 3.12 "
          "--with 'numpy>=2.0.0' --with 'torch==2.7.0' --with 'torchaudio==2.7.0' "
          "--with 'transformers==4.57.3' "
          "--with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' --with 'sox>=1.5.0' "
          "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' "
          "--with 'coremltools>=8.3.0,<10' "
          "scripts/repo-maintenance/coreml-qwen3tts/convert-speech-tokenizer-decoder-coreml.py "
          "--no-preflight-only --capture-mode export --export-decomposed "
          "--wrapper-mode fixed_16q_static_mask --verify-coreml-prediction "
          "--coreml-compute-units cpuOnly "
          f"--fixture {args.runtime_fixture} "
          f"--pad-code-steps {bucket} "
          "--qwen-source /path/to/Qwen3-TTS --allow-model-download "
          f"--output .local/coreml-qwen3tts/qwen3tts-speech-tokenizer-decoder-conversion-{suffix}.json "
          "--mlpackage-output .local/coreml-qwen3tts/"
          f"Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-{suffix}.mlpackage"
        ),
      }
    )
  return commands


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  calibration_fixture = load_json(resolve_package_path(args.calibration_fixture))
  buckets = [int(bucket) for bucket in calibration_fixture["aggregate"]["suggested_decoder_buckets"]]
  assignments = sample_assignments(calibration_fixture, buckets)

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_decoder_bucket_plan",
    "source": {
      "calibration_fixture_path": str(args.calibration_fixture),
      "runtime_fixture_path": str(args.runtime_fixture),
      "dataset": calibration_fixture["source"]["dataset"],
      "dataset_config": calibration_fixture["source"]["dataset_config"],
      "dataset_split": calibration_fixture["source"]["dataset_split"],
      "model_id": calibration_fixture["source"]["model_id"],
      "resolved_revision": calibration_fixture["source"]["resolved_revision"],
    },
    "bucket_plan": {
      "stage": "speech_tokenizer_decoder",
      "wrapper_mode": "fixed_16q_static_mask",
      "input_name": "audio_codes",
      "input_dtype": "int64",
      "quantizer_count": calibration_fixture["aggregate"]["quantizer_count"],
      "samples_per_code_step": calibration_fixture["calibration_scope"]["code_step_samples"],
      "buckets": buckets,
      "required_input_shapes": [
        [1, bucket, calibration_fixture["aggregate"]["quantizer_count"]]
        for bucket in buckets
      ],
      "sample_assignments": assignments,
    },
    "conversion_commands": conversion_commands(args, buckets),
    "w8a8_follow_up": {
      "blocked_until": "bucketed_decoder_mlpackages_exist",
      "next_quantization_work": (
        "Load each bucketed package, build calibration sample_data from real LibriTTS-R "
        "codes assigned to that bucket, and scope activation quantization away from the "
        "integer audio_codes input path."
      ),
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Plan fixed-shape Core ML decoder buckets for Qwen3-TTS calibration codes."
  )
  parser.add_argument("--calibration-fixture", type=Path, default=Path(DEFAULT_CALIBRATION_FIXTURE_PATH))
  parser.add_argument("--runtime-fixture", type=Path, default=Path(DEFAULT_RUNTIME_FIXTURE_PATH))
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--output", type=Path, default=None)
  return parser.parse_args()


def write_report(report: dict[str, Any], output: Path | None) -> None:
  rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
  if output is None:
    sys.stdout.write(rendered)
    return

  output.parent.mkdir(parents=True, exist_ok=True)
  output.write_text(rendered, encoding="utf-8")


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
