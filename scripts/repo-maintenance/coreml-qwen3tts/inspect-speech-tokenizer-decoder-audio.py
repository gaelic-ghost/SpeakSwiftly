#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "coremltools>=8.3.0,<10",
#   "numpy>=2.0.0",
#   "soundfile>=0.13.0",
# ]
# ///
"""Inspect decoder audio drift between two Core ML Qwen3-TTS decoder packages."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np
import soundfile as sf


DEFAULT_BASELINE_MODEL_PACKAGE = (
  ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-bucket-40-fp16.mlpackage"
)
DEFAULT_CANDIDATE_MODEL_PACKAGE = (
  ".local/coreml-qwen3tts/"
  "Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-bucket-40-fp16-w8a8-representative.mlpackage"
)
DEFAULT_CALIBRATION_FIXTURE_PATH = "docs/maintainers/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json"
DEFAULT_TALKER_CODE_FIXTURE_PATH = ".local/coreml-qwen3tts/talker-code-fixture-qwen3-12hz.json"
DEFAULT_BUCKET_PLAN_PATH = "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-bucket-plan-12hz.json"
DEFAULT_OUTPUT_DIR = ".local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8"
DEFAULT_SAMPLE_RATE = 24_000


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


def relative_package_path(path: Path) -> str:
  try:
    return str(path.resolve().relative_to(package_root()))
  except ValueError:
    return path.name


def load_json(path: Path) -> dict[str, Any]:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception as error:
    raise RuntimeError(f"Unable to read JSON file at '{path}'.") from error


def directory_size_bytes(path: Path) -> int | None:
  if not path.exists():
    return None
  if path.is_file():
    return path.stat().st_size
  return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def reset_output_dir(output_dir: Path, replace_existing: bool) -> None:
  if output_dir.exists():
    if not replace_existing:
      raise RuntimeError(
        f"Audio inspection output directory '{relative_package_path(output_dir)}' already exists. "
        "Pass --replace-existing to clear stale inspection artifacts before writing new ones."
      )
    shutil.rmtree(output_dir)
  output_dir.mkdir(parents=True, exist_ok=True)


def sample_assignment(bucket_plan: dict[str, Any], bucket: int, sample_id: str | None) -> dict[str, Any]:
  matches = [
    assignment
    for assignment in bucket_plan.get("bucket_plan", {}).get("sample_assignments", [])
    if int(assignment.get("assigned_bucket", -1)) == bucket
    and (sample_id is None or assignment.get("id") == sample_id)
  ]
  if not matches:
    raise RuntimeError(f"Bucket plan has no sample assignment for bucket {bucket} and sample id '{sample_id}'.")
  if len(matches) > 1:
    raise RuntimeError(f"Bucket plan has {len(matches)} assignments for bucket {bucket}; pass --sample-id.")
  return matches[0]


def calibration_sample(calibration_fixture: dict[str, Any], sample_id: str) -> dict[str, Any]:
  for sample in calibration_fixture.get("samples", []):
    if sample.get("id") == sample_id:
      return sample
  raise RuntimeError(f"Calibration fixture does not contain sample id '{sample_id}'.")


def representative_audio_codes(
  calibration_fixture: dict[str, Any],
  bucket_plan: dict[str, Any],
  bucket: int,
  sample_id: str | None,
) -> tuple[np.ndarray, dict[str, Any]]:
  assignment = sample_assignment(bucket_plan, bucket, sample_id)
  sample = calibration_sample(calibration_fixture, str(assignment["id"]))
  codes = np.asarray(sample["encoded"]["audio_codes"], dtype=np.int32)
  quantizer_count = int(bucket_plan["bucket_plan"]["quantizer_count"])
  if list(codes.shape)[1] != quantizer_count:
    raise RuntimeError(
      f"Calibration sample '{sample['id']}' has {codes.shape[1]} quantizers, "
      f"but bucket plan expects {quantizer_count}."
    )
  if codes.shape[0] > bucket:
    raise RuntimeError(f"Calibration sample '{sample['id']}' has {codes.shape[0]} code steps, exceeding bucket {bucket}.")

  padded = np.full((bucket, quantizer_count), int(assignment.get("pad_value", -1)), dtype=np.int32)
  padded[: codes.shape[0], :] = codes
  sample_report = {
    "id": sample["id"],
    "text_normalized": sample.get("text_normalized"),
    "audio_codes_shape": list(codes.shape),
    "padded_input_shape": [1, *list(padded.shape)],
    "padded_step_count": bucket - codes.shape[0],
    "pad_value": int(assignment.get("pad_value", -1)),
    "source_audio_seconds": sample.get("audio", {}).get("duration_seconds"),
    "valid_output_sample_count": assignment.get("valid_output_sample_count"),
    "padded_output_sample_count": assignment.get("padded_output_sample_count"),
  }
  return padded[None, :, :], sample_report


def talker_audio_codes(
  talker_fixture: dict[str, Any],
  bucket: int,
  sample_id: str | None,
) -> tuple[np.ndarray, dict[str, Any]]:
  matches = [
    sample for sample in talker_fixture.get("samples", [])
    if int(sample.get("bucket_assignment", {}).get("assigned_bucket", -1)) == bucket
    and (sample_id is None or sample.get("id") == sample_id)
  ]
  if not matches:
    raise RuntimeError(f"Talker-code fixture has no sample assignment for bucket {bucket} and sample id '{sample_id}'.")
  if len(matches) > 1:
    raise RuntimeError(f"Talker-code fixture has {len(matches)} assignments for bucket {bucket}; pass --sample-id.")

  sample = matches[0]
  assignment = sample["bucket_assignment"]
  codes = np.asarray(sample["encoded"]["audio_codes"], dtype=np.int32)
  if codes.ndim != 2:
    raise RuntimeError(f"Talker sample '{sample['id']}' audio_codes must be rank 2.")
  if codes.shape[0] > bucket:
    raise RuntimeError(f"Talker sample '{sample['id']}' has {codes.shape[0]} code steps, exceeding bucket {bucket}.")

  quantizer_count = codes.shape[1]
  padded = np.full((bucket, quantizer_count), int(assignment.get("pad_value", -1)), dtype=np.int32)
  padded[: codes.shape[0], :] = codes
  audio = sample.get("generated_audio", {})
  sample_rate = int(audio.get("sample_rate", DEFAULT_SAMPLE_RATE))
  sample_count = audio.get("sample_count")
  sample_report = {
    "id": sample["id"],
    "text_normalized": sample.get("text"),
    "audio_codes_shape": list(codes.shape),
    "padded_input_shape": [1, *list(padded.shape)],
    "padded_step_count": bucket - codes.shape[0],
    "pad_value": int(assignment.get("pad_value", -1)),
    "source_audio_seconds": sample_count / sample_rate if sample_count is not None else None,
    "valid_output_sample_count": assignment.get("valid_output_sample_count"),
    "padded_output_sample_count": assignment.get("padded_output_sample_count"),
    "generated_audio_path": audio.get("wav_path"),
  }
  return padded[None, :, :], sample_report


def predict_audio(model_package: Path, audio_codes: np.ndarray) -> np.ndarray:
  model = ct.models.MLModel(str(model_package), compute_units=ct.ComputeUnit.CPU_ONLY)
  prediction = model.predict({"audio_codes": audio_codes})
  return np.asarray(prediction["audio_values"], dtype=np.float32).reshape(-1)


def audio_summary(audio: np.ndarray) -> dict[str, Any]:
  return {
    "sample_count": int(audio.shape[0]),
    "min": float(audio.min()),
    "max": float(audio.max()),
    "mean": float(audio.mean()),
    "rms": float(np.sqrt(np.mean(np.square(audio)))),
    "clipped_or_near_clipped_sample_count": int(np.count_nonzero(np.abs(audio) >= 0.99)),
  }


def diff_summary(delta: np.ndarray) -> dict[str, Any]:
  return {
    "sample_count": int(delta.shape[0]),
    "max_abs_diff": float(np.max(np.abs(delta))),
    "mean_abs_diff": float(np.mean(np.abs(delta))),
    "rms_diff": float(np.sqrt(np.mean(np.square(delta)))),
  }


def window_reports(
  baseline: np.ndarray,
  candidate: np.ndarray,
  sample_rate: int,
  window_seconds: float,
  alert_mean_abs_diff: float,
) -> dict[str, Any]:
  window_samples = max(1, int(round(sample_rate * window_seconds)))
  windows: list[dict[str, Any]] = []
  for start in range(0, len(baseline), window_samples):
    end = min(start + window_samples, len(baseline))
    baseline_window = baseline[start:end]
    candidate_window = candidate[start:end]
    delta = candidate_window - baseline_window
    windows.append(
      {
        "index": len(windows),
        "start_sample": start,
        "end_sample": end,
        "start_seconds": start / sample_rate,
        "end_seconds": end / sample_rate,
        "baseline_rms": float(np.sqrt(np.mean(np.square(baseline_window)))),
        "candidate_rms": float(np.sqrt(np.mean(np.square(candidate_window)))),
        "max_abs_diff": float(np.max(np.abs(delta))),
        "mean_abs_diff": float(np.mean(np.abs(delta))),
        "rms_diff": float(np.sqrt(np.mean(np.square(delta)))),
      }
    )

  alert_windows = [
    window for window in windows
    if window["mean_abs_diff"] >= alert_mean_abs_diff
  ]
  return {
    "window_seconds": window_seconds,
    "window_samples": window_samples,
    "count": len(windows),
    "alert_mean_abs_diff": alert_mean_abs_diff,
    "alert_count": len(alert_windows),
    "alert_ratio": len(alert_windows) / len(windows) if windows else 0.0,
    "top_by_mean_abs_diff": sorted(windows, key=lambda item: item["mean_abs_diff"], reverse=True)[:10],
    "top_by_max_abs_diff": sorted(windows, key=lambda item: item["max_abs_diff"], reverse=True)[:10],
  }


def write_wav(path: Path, audio: np.ndarray, sample_rate: int) -> None:
  sf.write(path, np.clip(audio, -1.0, 1.0), sample_rate)


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  baseline_model_package = resolve_package_path(args.baseline_model_package)
  candidate_model_package = resolve_package_path(args.candidate_model_package)
  output_dir = resolve_package_path(args.output_dir)
  reset_output_dir(output_dir, args.replace_existing)

  calibration_fixture = load_json(resolve_package_path(args.calibration_fixture))
  bucket_plan = load_json(resolve_package_path(args.bucket_plan))
  talker_fixture_path = resolve_package_path(args.talker_code_fixture)
  talker_fixture = load_json(talker_fixture_path) if talker_fixture_path.is_file() else None
  if args.sample_source == "representative":
    audio_codes, sample_report = representative_audio_codes(
      calibration_fixture,
      bucket_plan,
      args.bucket,
      args.sample_id,
    )
  elif args.sample_source == "talker":
    if talker_fixture is None:
      raise RuntimeError("Talker sample source requires --talker-code-fixture.")
    audio_codes, sample_report = talker_audio_codes(
      talker_fixture,
      args.bucket,
      args.sample_id,
    )
  else:
    raise RuntimeError(f"Unsupported sample source '{args.sample_source}'.")

  baseline_audio = predict_audio(baseline_model_package, audio_codes)
  candidate_audio = predict_audio(candidate_model_package, audio_codes)
  if baseline_audio.shape != candidate_audio.shape:
    raise RuntimeError(
      f"Baseline output shape {list(baseline_audio.shape)} does not match candidate shape {list(candidate_audio.shape)}."
    )

  valid_count = int(sample_report["valid_output_sample_count"])
  delta = candidate_audio - baseline_audio
  paths = {
    "baseline_wav": output_dir / "baseline-fp16.wav",
    "candidate_wav": output_dir / "candidate-w8a8.wav",
    "diff_wav": output_dir / "candidate-minus-baseline.wav",
    "baseline_valid_wav": output_dir / "baseline-fp16-valid.wav",
    "candidate_valid_wav": output_dir / "candidate-w8a8-valid.wav",
  }
  write_wav(paths["baseline_wav"], baseline_audio, args.sample_rate)
  write_wav(paths["candidate_wav"], candidate_audio, args.sample_rate)
  write_wav(paths["diff_wav"], delta, args.sample_rate)
  write_wav(paths["baseline_valid_wav"], baseline_audio[:valid_count], args.sample_rate)
  write_wav(paths["candidate_valid_wav"], candidate_audio[:valid_count], args.sample_rate)

  report = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_decoder_audio_inspection",
    "source": {
      "baseline_model_package": relative_package_path(baseline_model_package),
      "baseline_model_package_size_bytes": directory_size_bytes(baseline_model_package),
      "candidate_model_package": relative_package_path(candidate_model_package),
      "candidate_model_package_size_bytes": directory_size_bytes(candidate_model_package),
      "calibration_fixture_path": str(args.calibration_fixture),
      "talker_code_fixture_path": str(args.talker_code_fixture),
      "bucket_plan_path": str(args.bucket_plan),
      "sample_source": args.sample_source,
      "compute_units": "cpuOnly",
      "sample_rate": args.sample_rate,
    },
    "sample": sample_report,
    "artifacts": {
      key: relative_package_path(path)
      for key, path in paths.items()
    },
    "audio": {
      "baseline": audio_summary(baseline_audio),
      "candidate": audio_summary(candidate_audio),
      "full_output_diff": diff_summary(delta),
      "valid_output_diff": diff_summary(delta[:valid_count]),
      "padded_tail_diff": diff_summary(delta[valid_count:]) if valid_count < len(delta) else None,
      "windows": window_reports(
        baseline_audio[:valid_count],
        candidate_audio[:valid_count],
        args.sample_rate,
        args.window_seconds,
        args.alert_mean_abs_diff,
      ),
    },
    "interpretation": {
      "status": "needs_audio_review",
      "note": (
        "This report compares Core ML decoder outputs from the fp16 bucket package and the representative W8A8 bucket package. "
        "It localizes numeric drift in the valid decoded region, but human listening is still required before making a quality decision."
      ),
    },
  }
  return report


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Write WAV artifacts and a drift report for two Core ML Qwen3-TTS decoder packages."
  )
  parser.add_argument("--baseline-model-package", type=Path, default=Path(DEFAULT_BASELINE_MODEL_PACKAGE))
  parser.add_argument("--candidate-model-package", type=Path, default=Path(DEFAULT_CANDIDATE_MODEL_PACKAGE))
  parser.add_argument("--calibration-fixture", type=Path, default=Path(DEFAULT_CALIBRATION_FIXTURE_PATH))
  parser.add_argument("--talker-code-fixture", type=Path, default=Path(DEFAULT_TALKER_CODE_FIXTURE_PATH))
  parser.add_argument("--bucket-plan", type=Path, default=Path(DEFAULT_BUCKET_PLAN_PATH))
  parser.add_argument("--sample-source", default="representative", choices=["representative", "talker"])
  parser.add_argument("--bucket", type=int, default=40)
  parser.add_argument("--sample-id", default=None)
  parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
  parser.add_argument("--window-seconds", type=float, default=0.25)
  parser.add_argument("--alert-mean-abs-diff", type=float, default=0.01)
  parser.add_argument("--replace-existing", action="store_true")
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--output-dir", type=Path, default=Path(DEFAULT_OUTPUT_DIR))
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
