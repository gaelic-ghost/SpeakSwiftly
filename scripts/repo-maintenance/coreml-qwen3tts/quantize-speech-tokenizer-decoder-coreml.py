#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "coremltools>=8.3.0,<10",
#   "numpy>=2.0.0",
# ]
# ///
"""Probe Core ML quantization readiness for the Qwen3-TTS speech-tokenizer decoder."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import coremltools as ct
import coremltools.optimize as cto
import numpy as np


DEFAULT_MODEL_PACKAGE = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed.mlpackage"
DEFAULT_RUNTIME_FIXTURE_PATH = "docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"
DEFAULT_CALIBRATION_FIXTURE_PATH = "docs/maintainers/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json"
DEFAULT_CONVERSION_REPORT_PATH = (
  "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json"
)
DEFAULT_WEIGHT_OUTPUT = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-w8.mlpackage"
DEFAULT_W8A8_OUTPUT = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-w8a8.mlpackage"


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


def remove_existing_package(path: Path) -> None:
  if path.exists():
    if path.is_dir():
      shutil.rmtree(path)
    else:
      path.unlink()


def fixed_decoder_shape(conversion_report: dict[str, Any]) -> list[int]:
  target = conversion_report.get("conversion_target", {})
  shape = target.get("input_shape")
  if not isinstance(shape, list) or len(shape) != 3:
    raise RuntimeError("Conversion report does not contain a fixed 3D decoder input_shape.")
  return [int(item) for item in shape]


def runtime_codes(runtime_fixture: dict[str, Any]) -> np.ndarray:
  codes = np.asarray(runtime_fixture["encoded"]["audio_codes"], dtype=np.int32)
  return codes


def calibration_code_shapes(calibration_fixture: dict[str, Any]) -> list[dict[str, Any]]:
  return [
    {
      "id": sample.get("id"),
      "audio_codes_shape": sample["encoded"]["audio_codes_shape"],
      "audio_seconds": sample.get("audio", {}).get("duration_seconds"),
    }
    for sample in calibration_fixture.get("samples", [])
  ]


def compatibility_report(
  model_input_shape: list[int],
  runtime_fixture: dict[str, Any],
  calibration_fixture: dict[str, Any],
) -> dict[str, Any]:
  runtime_shape = list(runtime_codes(runtime_fixture).shape)
  fixed_code_steps = model_input_shape[1]
  quantizer_count = model_input_shape[2]
  calibration_shapes = calibration_code_shapes(calibration_fixture)
  matching_real_samples = [
    sample for sample in calibration_shapes
    if sample["audio_codes_shape"] == [fixed_code_steps, quantizer_count]
  ]
  mismatched_real_samples = [
    sample for sample in calibration_shapes
    if sample["audio_codes_shape"] != [fixed_code_steps, quantizer_count]
  ]

  return {
    "current_model_input_shape": model_input_shape,
    "synthetic_runtime_sample": {
      "audio_codes_shape": runtime_shape,
      "matches_current_model": runtime_shape == model_input_shape[1:],
    },
    "real_speech_calibration": {
      "sample_count": len(calibration_shapes),
      "matching_sample_count": len(matching_real_samples),
      "mismatched_sample_count": len(mismatched_real_samples),
      "sample_shapes": calibration_shapes,
      "suggested_decoder_buckets": calibration_fixture.get("aggregate", {}).get("suggested_decoder_buckets", []),
    },
    "decision": (
      "The current 8-step decoder package can only run a synthetic W8A8 smoke calibration. "
      "Representative real-speech activation calibration needs bucketed decoder conversions "
      "that match the 40, 72, and 88 step calibration buckets."
    ),
  }


def quantization_api_report() -> dict[str, Any]:
  experimental = getattr(cto.coreml, "experimental", None)
  return {
    "coremltools_version": ct.__version__,
    "has_linear_quantize_weights": hasattr(cto.coreml, "linear_quantize_weights"),
    "has_experimental_linear_quantize_activations": bool(
      experimental and hasattr(experimental, "linear_quantize_activations")
    ),
    "weight_quantization_note": (
      "Core ML Tools weight-only quantization compresses stored weights; runtime computation "
      "for consuming ops still uses float precision."
    ),
    "w8a8_note": (
      "Core ML Tools W8A8 requires activation quantization from calibration sample_data, "
      "then int8 weight quantization of the activation-quantized model."
    ),
  }


def build_sample_data(runtime_fixture: dict[str, Any], model_input_shape: list[int]) -> list[dict[str | None, np.ndarray]]:
  codes = runtime_codes(runtime_fixture)
  expected_shape = model_input_shape[1:]
  if list(codes.shape) != expected_shape:
    raise RuntimeError(
      f"Synthetic runtime fixture has audio_codes shape {list(codes.shape)}, "
      f"but the fixed Core ML decoder expects {expected_shape}."
    )
  return [{"audio_codes": codes[None, :, :]}]


def predict_summary(model: ct.models.MLModel, sample_data: list[dict[str | None, np.ndarray]]) -> dict[str, Any]:
  prediction = model.predict(sample_data[0])
  output = np.asarray(prediction["audio_values"])
  return {
    "output_shape": list(output.shape),
    "output_dtype": str(output.dtype),
    "output_min": float(output.min()),
    "output_max": float(output.max()),
    "output_rms": float(np.sqrt(np.mean(np.square(output)))),
  }


def run_weight_quantization(
  model: ct.models.MLModel,
  output_path: Path,
  replace_existing: bool,
) -> dict[str, Any]:
  if replace_existing:
    remove_existing_package(output_path)

  start = time.perf_counter()
  config = cto.coreml.OptimizationConfig(
    global_config=cto.coreml.OpLinearQuantizerConfig(
      mode="linear_symmetric",
      dtype="int8",
      granularity="per_channel",
    )
  )
  quantized = cto.coreml.linear_quantize_weights(model, config)
  quantized.save(str(output_path))
  duration_ms = (time.perf_counter() - start) * 1000
  return {
    "status": "succeeded",
    "mode": "weight_only_int8",
    "output_package": relative_package_path(output_path),
    "duration_ms": duration_ms,
    "package_size_bytes": directory_size_bytes(output_path),
  }


def run_w8a8_quantization(
  model: ct.models.MLModel,
  sample_data: list[dict[str | None, np.ndarray]],
  output_path: Path,
  replace_existing: bool,
  calibration_op_group_size: int,
) -> dict[str, Any]:
  if replace_existing:
    remove_existing_package(output_path)

  start = time.perf_counter()
  activation_config = cto.coreml.OptimizationConfig(
    global_config=cto.coreml.OpLinearQuantizerConfig(mode="linear_symmetric")
  )
  activation_quantized = cto.coreml.experimental.linear_quantize_activations(
    model,
    activation_config,
    sample_data,
    calibration_op_group_size=calibration_op_group_size,
  )
  weight_config = cto.coreml.OptimizationConfig(
    global_config=cto.coreml.OpLinearQuantizerConfig(
      mode="linear_symmetric",
      dtype="int8",
      granularity="per_channel",
    )
  )
  quantized = cto.coreml.linear_quantize_weights(activation_quantized, weight_config)
  quantized.save(str(output_path))
  duration_ms = (time.perf_counter() - start) * 1000
  return {
    "status": "succeeded",
    "mode": "w8a8_synthetic_smoke",
    "output_package": relative_package_path(output_path),
    "duration_ms": duration_ms,
    "package_size_bytes": directory_size_bytes(output_path),
    "calibration_op_group_size": calibration_op_group_size,
    "sample_data_count": len(sample_data),
  }


def build_preflight_report(args: argparse.Namespace) -> dict[str, Any]:
  conversion_report = load_json(resolve_package_path(args.conversion_report))
  runtime_fixture = load_json(resolve_package_path(args.runtime_fixture))
  calibration_fixture = load_json(resolve_package_path(args.calibration_fixture))
  model_input_shape = fixed_decoder_shape(conversion_report)
  model_package = resolve_package_path(args.model_package)

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_quantization_preflight",
    "source": {
      "model_package": relative_package_path(model_package),
      "model_package_exists": model_package.exists(),
      "model_package_size_bytes": directory_size_bytes(model_package),
      "conversion_report_path": str(args.conversion_report),
      "runtime_fixture_path": str(args.runtime_fixture),
      "calibration_fixture_path": str(args.calibration_fixture),
      "conversion_source": conversion_report["source"],
      "conversion_target": conversion_report["conversion_target"],
    },
    "coremltools": quantization_api_report(),
    "calibration_compatibility": compatibility_report(model_input_shape, runtime_fixture, calibration_fixture),
    "quantization_plan": {
      "weight_only_int8": {
        "status": "available",
        "purpose": "storage and load-size smoke test; not expected to prove Neural Engine dispatch by itself",
      },
      "w8a8_synthetic_smoke": {
        "status": "available_when_local_model_exists",
        "purpose": "API and model-load smoke test using the current 8-step synthetic fixture",
        "known_risk": (
          "Global activation quantization can try to quantize integer audio-code input paths. "
          "If that happens, scope activation quantization to float-producing ops or split the "
          "integer code lookup from the float decoder graph before treating W8A8 as blocked."
        ),
      },
      "w8a8_representative": {
        "status": "blocked_until_bucketed_decoder_packages_exist",
        "required_decoder_input_shapes": [
          [1, bucket, model_input_shape[2]]
          for bucket in calibration_fixture.get("aggregate", {}).get("suggested_decoder_buckets", [])
        ],
      },
    },
    "next_command": (
      "uv run --python 3.12 "
      "scripts/repo-maintenance/coreml-qwen3tts/quantize-speech-tokenizer-decoder-coreml.py "
      "--no-preflight-only --run-weight-only --run-w8a8 "
      "--output .local/coreml-qwen3tts/qwen3tts-decoder-quantization-smoke.json"
    ),
  }


def build_runtime_report(args: argparse.Namespace) -> dict[str, Any]:
  report = build_preflight_report(args)
  report["mode"] = "coreml_quantization_runtime"

  model_package = resolve_package_path(args.model_package)
  if not model_package.exists():
    raise RuntimeError(
      f"Core ML package '{args.model_package}' does not exist. "
      "Run the decoder conversion probe before quantization runtime probing."
    )

  runtime_fixture = load_json(resolve_package_path(args.runtime_fixture))
  sample_data = build_sample_data(runtime_fixture, report["source"]["conversion_target"]["input_shape"])
  model = ct.models.MLModel(str(model_package), compute_units=ct.ComputeUnit.CPU_ONLY)
  report["runtime"] = {
    "sample_data": {
      "count": len(sample_data),
      "input_name": "audio_codes",
      "input_shape": list(sample_data[0]["audio_codes"].shape),
      "input_dtype": str(sample_data[0]["audio_codes"].dtype),
      "scope_warning": (
        "This runtime probe uses the synthetic 8-step fixture because the current decoder "
        "package is fixed to 8 code steps."
      ),
    },
    "baseline_prediction": predict_summary(model, sample_data) if args.verify_prediction else None,
    "results": [],
  }

  if args.run_weight_only:
    try:
      report["runtime"]["results"].append(
        run_weight_quantization(
          model,
          resolve_package_path(args.weight_output),
          args.replace_existing,
        )
      )
    except Exception as error:
      report["runtime"]["results"].append(
        {
          "status": "failed",
          "mode": "weight_only_int8",
          "error_type": type(error).__name__,
          "error_message": str(error),
        }
      )

  if args.run_w8a8:
    try:
      report["runtime"]["results"].append(
        run_w8a8_quantization(
          model,
          sample_data,
          resolve_package_path(args.w8a8_output),
          args.replace_existing,
          args.calibration_op_group_size,
        )
      )
    except Exception as error:
      report["runtime"]["results"].append(
        {
          "status": "failed",
          "mode": "w8a8_synthetic_smoke",
          "error_type": type(error).__name__,
          "error_message": str(error),
        }
      )

  return report


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Probe Core ML Tools quantization readiness for the converted Qwen3-TTS "
      "12 Hz speech-tokenizer decoder."
    )
  )
  parser.add_argument("--model-package", type=Path, default=Path(DEFAULT_MODEL_PACKAGE))
  parser.add_argument("--runtime-fixture", type=Path, default=Path(DEFAULT_RUNTIME_FIXTURE_PATH))
  parser.add_argument("--calibration-fixture", type=Path, default=Path(DEFAULT_CALIBRATION_FIXTURE_PATH))
  parser.add_argument("--conversion-report", type=Path, default=Path(DEFAULT_CONVERSION_REPORT_PATH))
  parser.add_argument("--weight-output", type=Path, default=Path(DEFAULT_WEIGHT_OUTPUT))
  parser.add_argument("--w8a8-output", type=Path, default=Path(DEFAULT_W8A8_OUTPUT))
  parser.add_argument(
    "--preflight-only",
    action=argparse.BooleanOptionalAction,
    default=True,
  )
  parser.add_argument("--run-weight-only", action="store_true")
  parser.add_argument("--run-w8a8", action="store_true")
  parser.add_argument("--replace-existing", action="store_true")
  parser.add_argument("--verify-prediction", action="store_true")
  parser.add_argument("--calibration-op-group-size", type=int, default=16)
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
    if args.preflight_only:
      report = build_preflight_report(args)
    else:
      report = build_runtime_report(args)
    write_report(report, args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1

  return 0


if __name__ == "__main__":
  raise SystemExit(main())
