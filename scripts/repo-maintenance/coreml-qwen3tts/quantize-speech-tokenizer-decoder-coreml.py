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
DEFAULT_RUNTIME_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"
DEFAULT_CALIBRATION_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json"
DEFAULT_BUCKET_PLAN_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-bucket-plan-12hz.json"
DEFAULT_TALKER_CODE_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-qwen3-12hz.json"
DEFAULT_CONVERSION_REPORT_PATH = (
  "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json"
)
DEFAULT_WEIGHT_OUTPUT = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-w8.mlpackage"
DEFAULT_W8A8_OUTPUT = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-w8a8.mlpackage"
COMPUTE_ONLY_ACTIVATION_OP_TYPES = ["conv", "linear", "matmul", "conv_transpose"]


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


def bucket_conversion_report_path(bucket: int) -> Path:
  return Path(f"docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-{bucket}-12hz.json")


def bucketed_conversion_report(bucket_plan: dict[str, Any] | None) -> dict[str, Any]:
  if bucket_plan is None:
    return {
      "status": "missing_bucket_plan",
      "required_input_shapes": [],
      "pinned_report_count": 0,
      "missing_reports": [],
    }

  buckets = bucket_plan.get("bucket_plan", {}).get("buckets", [])
  missing_reports = [
    str(bucket_conversion_report_path(int(bucket)))
    for bucket in buckets
    if not resolve_package_path(bucket_conversion_report_path(int(bucket))).is_file()
  ]
  return {
    "status": "complete" if not missing_reports else "missing_reports",
    "required_input_shapes": bucket_plan.get("bucket_plan", {}).get("required_input_shapes", []),
    "pinned_report_count": len(buckets) - len(missing_reports),
    "missing_reports": missing_reports,
  }


def compatibility_report(
  model_input_shape: list[int],
  runtime_fixture: dict[str, Any],
  calibration_fixture: dict[str, Any],
  bucket_plan: dict[str, Any] | None,
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
    "bucketed_decoder_conversions": bucketed_conversion_report(bucket_plan),
    "decision": (
      "The original 8-step decoder package can only run a synthetic W8A8 smoke calibration. "
      "The checked bucketed decoder reports now provide the static shapes needed for representative "
      "real-speech activation calibration."
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
    "activation_scope_note": (
      "OptimizationConfig can scope activation quantization by op type or op name. "
      "The decoder's integer audio-code lookup path should not be globally activation-quantized."
    ),
  }


def build_synthetic_sample_data(
  runtime_fixture: dict[str, Any],
  model_input_shape: list[int],
) -> tuple[list[dict[str | None, np.ndarray]], dict[str, Any]]:
  codes = runtime_codes(runtime_fixture)
  expected_shape = model_input_shape[1:]
  if list(codes.shape) != expected_shape:
    raise RuntimeError(
      f"Synthetic runtime fixture has audio_codes shape {list(codes.shape)}, "
      f"but the fixed Core ML decoder expects {expected_shape}."
    )
  return [{"audio_codes": codes[None, :, :]}], {
    "source": "synthetic_runtime_fixture",
    "count": 1,
    "input_name": "audio_codes",
    "input_shape": [1, *list(codes.shape)],
    "input_dtype": str(codes.dtype),
    "scope_warning": (
      "This runtime probe uses the synthetic 8-step fixture because the original decoder "
      "package is fixed to 8 code steps."
    ),
  }


def representative_bucket_assignments(
  bucket_plan: dict[str, Any] | None,
  bucket: int,
) -> list[dict[str, Any]]:
  if bucket_plan is None:
    raise RuntimeError("Representative calibration requires a bucket plan fixture.")

  assignments = bucket_plan.get("bucket_plan", {}).get("sample_assignments", [])
  return [
    assignment for assignment in assignments
    if int(assignment.get("assigned_bucket", -1)) == bucket
  ]


def calibration_sample_by_id(
  calibration_fixture: dict[str, Any],
  sample_id: str,
) -> dict[str, Any]:
  for sample in calibration_fixture.get("samples", []):
    if sample.get("id") == sample_id:
      return sample
  raise RuntimeError(f"Calibration fixture does not contain sample id '{sample_id}'.")


def build_representative_sample_data(
  calibration_fixture: dict[str, Any],
  bucket_plan: dict[str, Any] | None,
  model_input_shape: list[int],
  requested_bucket: int | None,
) -> tuple[list[dict[str | None, np.ndarray]], dict[str, Any]]:
  bucket = requested_bucket or model_input_shape[1]
  if bucket != model_input_shape[1]:
    raise RuntimeError(
      f"Representative bucket {bucket} does not match fixed decoder input steps {model_input_shape[1]}."
    )

  quantizer_count = model_input_shape[2]
  assignments = representative_bucket_assignments(bucket_plan, bucket)
  if not assignments:
    raise RuntimeError(f"Bucket plan does not assign any calibration samples to bucket {bucket}.")

  sample_data: list[dict[str | None, np.ndarray]] = []
  sample_reports: list[dict[str, Any]] = []
  for assignment in assignments:
    sample = calibration_sample_by_id(calibration_fixture, str(assignment["id"]))
    codes = np.asarray(sample["encoded"]["audio_codes"], dtype=np.int32)
    if codes.ndim != 2:
      raise RuntimeError(f"Calibration sample '{sample['id']}' audio_codes must be rank 2.")
    if codes.shape[1] != quantizer_count:
      raise RuntimeError(
        f"Calibration sample '{sample['id']}' has {codes.shape[1]} quantizers, "
        f"but the decoder expects {quantizer_count}."
      )
    if codes.shape[0] > bucket:
      raise RuntimeError(
        f"Calibration sample '{sample['id']}' has {codes.shape[0]} steps, "
        f"which exceeds bucket {bucket}."
      )

    padded = np.full((bucket, quantizer_count), int(assignment.get("pad_value", -1)), dtype=np.int32)
    padded[: codes.shape[0], :] = codes
    sample_data.append({"audio_codes": padded[None, :, :]})
    sample_reports.append(
      {
        "id": sample["id"],
        "audio_codes_shape": list(codes.shape),
        "padded_input_shape": [1, *list(padded.shape)],
        "padded_step_count": bucket - codes.shape[0],
        "pad_value": int(assignment.get("pad_value", -1)),
        "audio_seconds": sample.get("audio", {}).get("duration_seconds"),
        "valid_output_sample_count": assignment.get("valid_output_sample_count"),
        "padded_output_sample_count": assignment.get("padded_output_sample_count"),
      }
    )

  return sample_data, {
    "source": "representative_calibration_fixture",
    "bucket": bucket,
    "count": len(sample_data),
    "input_name": "audio_codes",
    "input_shape": list(sample_data[0]["audio_codes"].shape),
    "input_dtype": str(sample_data[0]["audio_codes"].dtype),
    "samples": sample_reports,
    "scope_warning": (
      "This runtime probe uses real LibriTTS-R speech-tokenizer codes padded to the fixed bucket shape. "
      "It is representative for decoder activation ranges, but it is still not an audio-quality decision."
    ),
  }


def build_talker_sample_data(
  talker_fixture: dict[str, Any],
  model_input_shape: list[int],
  requested_bucket: int | None,
) -> tuple[list[dict[str | None, np.ndarray]], dict[str, Any]]:
  bucket = requested_bucket or model_input_shape[1]
  if bucket != model_input_shape[1]:
    raise RuntimeError(
      f"Talker-code bucket {bucket} does not match fixed decoder input steps {model_input_shape[1]}."
    )

  quantizer_count = model_input_shape[2]
  matching_samples = [
    sample for sample in talker_fixture.get("samples", [])
    if int(sample.get("bucket_assignment", {}).get("assigned_bucket", -1)) == bucket
  ]
  if not matching_samples:
    raise RuntimeError(f"Talker-code fixture does not contain samples assigned to bucket {bucket}.")

  sample_data: list[dict[str | None, np.ndarray]] = []
  sample_reports: list[dict[str, Any]] = []
  for sample in matching_samples:
    assignment = sample["bucket_assignment"]
    codes = np.asarray(sample["encoded"]["audio_codes"], dtype=np.int32)
    if codes.ndim != 2:
      raise RuntimeError(f"Talker sample '{sample['id']}' audio_codes must be rank 2.")
    if codes.shape[1] != quantizer_count:
      raise RuntimeError(
        f"Talker sample '{sample['id']}' has {codes.shape[1]} quantizers, "
        f"but the decoder expects {quantizer_count}."
      )
    if codes.shape[0] > bucket:
      raise RuntimeError(
        f"Talker sample '{sample['id']}' has {codes.shape[0]} steps, which exceeds bucket {bucket}."
      )

    padded = np.full((bucket, quantizer_count), int(assignment.get("pad_value", -1)), dtype=np.int32)
    padded[: codes.shape[0], :] = codes
    sample_data.append({"audio_codes": padded[None, :, :]})
    sample_reports.append(
      {
        "id": sample["id"],
        "text": sample.get("text"),
        "audio_codes_shape": list(codes.shape),
        "padded_input_shape": [1, *list(padded.shape)],
        "padded_step_count": bucket - codes.shape[0],
        "pad_value": int(assignment.get("pad_value", -1)),
        "valid_output_sample_count": assignment.get("valid_output_sample_count"),
        "padded_output_sample_count": assignment.get("padded_output_sample_count"),
      }
    )

  return sample_data, {
    "source": "talker_code_fixture",
    "bucket": bucket,
    "count": len(sample_data),
    "input_name": "audio_codes",
    "input_shape": list(sample_data[0]["audio_codes"].shape),
    "input_dtype": str(sample_data[0]["audio_codes"].dtype),
    "samples": sample_reports,
    "scope_warning": (
      "This runtime probe uses Qwen3 talker-generated code tensors captured immediately before "
      "speech_tokenizer.decode. It is closer to production decoder inputs than audio re-encoded "
      "through the tokenizer, but output audio still remains evaluation data for Core ML calibration."
    ),
  }


def build_runtime_sample_data(
  args: argparse.Namespace,
  runtime_fixture: dict[str, Any],
  calibration_fixture: dict[str, Any],
  talker_code_fixture: dict[str, Any] | None,
  bucket_plan: dict[str, Any] | None,
  model_input_shape: list[int],
) -> tuple[list[dict[str | None, np.ndarray]], dict[str, Any]]:
  if args.sample_source == "synthetic":
    return build_synthetic_sample_data(runtime_fixture, model_input_shape)
  if args.sample_source == "representative":
    return build_representative_sample_data(
      calibration_fixture,
      bucket_plan,
      model_input_shape,
      args.bucket,
    )
  if args.sample_source == "talker":
    if talker_code_fixture is None:
      raise RuntimeError("Talker sample source requires --talker-code-fixture.")
    return build_talker_sample_data(
      talker_code_fixture,
      model_input_shape,
      args.bucket,
    )
  raise RuntimeError(f"Unsupported sample source '{args.sample_source}'.")


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
  sample_data_report: dict[str, Any],
  output_path: Path,
  replace_existing: bool,
  calibration_op_group_size: int,
  activation_scope: str,
  activation_op_types: list[str] | None,
  baseline_output: np.ndarray | None,
  candidate_label: str | None,
) -> dict[str, Any]:
  if replace_existing:
    remove_existing_package(output_path)

  start = time.perf_counter()
  activation_quantizer_config = cto.coreml.OpLinearQuantizerConfig(mode="linear_symmetric")
  if activation_scope == "global":
    activation_config = cto.coreml.OptimizationConfig(global_config=activation_quantizer_config)
    scoped_op_types: list[str] = []
  elif activation_scope == "compute_only":
    scoped_op_types = activation_op_types or COMPUTE_ONLY_ACTIVATION_OP_TYPES
    activation_config = cto.coreml.OptimizationConfig(
      op_type_configs={
        op_type: activation_quantizer_config
        for op_type in scoped_op_types
      }
    )
  else:
    raise RuntimeError(f"Unsupported activation scope '{activation_scope}'.")

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
  sample_source = sample_data_report.get("source")
  sample_mode = {
    "representative_calibration_fixture": "representative_smoke",
    "talker_code_fixture": "talker_smoke",
  }.get(sample_source, "synthetic_smoke")
  result: dict[str, Any] = {
    "status": "succeeded",
    "mode": f"w8a8_{sample_mode}_{activation_scope}",
    "candidate_label": candidate_label,
    "output_package": relative_package_path(output_path),
    "duration_ms": duration_ms,
    "package_size_bytes": directory_size_bytes(output_path),
    "calibration_op_group_size": calibration_op_group_size,
    "sample_data_count": len(sample_data),
    "activation_scope": activation_scope,
    "activation_op_types": scoped_op_types,
  }
  if baseline_output is not None:
    quantized_model = ct.models.MLModel(str(output_path), compute_units=ct.ComputeUnit.CPU_ONLY)
    prediction = quantized_model.predict(sample_data[0])
    quantized_output = np.asarray(prediction["audio_values"])
    delta = quantized_output - baseline_output
    result["output_match"] = {
      "baseline": "model_package",
      "compute_units": "cpuOnly",
      "quantized_output_shape": list(quantized_output.shape),
      "quantized_output_dtype": str(quantized_output.dtype),
      "quantized_output_min": float(quantized_output.min()),
      "quantized_output_max": float(quantized_output.max()),
      "quantized_output_rms": float(np.sqrt(np.mean(np.square(quantized_output)))),
      "max_abs_diff": float(np.max(np.abs(delta))),
      "mean_abs_diff": float(np.mean(np.abs(delta))),
    }
    samples = sample_data_report.get("samples", [])
    if len(samples) == 1 and isinstance(samples[0].get("valid_output_sample_count"), int):
      valid_output_sample_count = samples[0]["valid_output_sample_count"]
      valid_delta = delta[:, :valid_output_sample_count]
      result["output_match"]["valid_output"] = {
        "sample_count": valid_output_sample_count,
        "max_abs_diff": float(np.max(np.abs(valid_delta))),
        "mean_abs_diff": float(np.mean(np.abs(valid_delta))),
      }
      if valid_output_sample_count < delta.shape[1]:
        padded_delta = delta[:, valid_output_sample_count:]
        result["output_match"]["padded_tail"] = {
          "sample_count": int(delta.shape[1] - valid_output_sample_count),
          "max_abs_diff": float(np.max(np.abs(padded_delta))),
          "mean_abs_diff": float(np.mean(np.abs(padded_delta))),
        }
  return result


def build_preflight_report(args: argparse.Namespace) -> dict[str, Any]:
  conversion_report = load_json(resolve_package_path(args.conversion_report))
  runtime_fixture = load_json(resolve_package_path(args.runtime_fixture))
  calibration_fixture = load_json(resolve_package_path(args.calibration_fixture))
  bucket_plan_path = resolve_package_path(args.bucket_plan)
  bucket_plan = load_json(bucket_plan_path) if bucket_plan_path.is_file() else None
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
    "calibration_compatibility": compatibility_report(
      model_input_shape,
      runtime_fixture,
      calibration_fixture,
      bucket_plan,
    ),
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
        "status": (
          "ready_for_scoped_activation_probe"
          if bucketed_conversion_report(bucket_plan)["status"] == "complete"
          else "blocked_until_bucketed_decoder_packages_exist"
        ),
        "required_decoder_input_shapes": [
          [1, bucket, model_input_shape[2]]
          for bucket in calibration_fixture.get("aggregate", {}).get("suggested_decoder_buckets", [])
        ],
      },
      "w8a8_scope_strategy": {
        "status": "identified",
        "base_precision": "float16",
        "activation_scope": "compute_only",
        "activation_op_types": COMPUTE_ONLY_ACTIVATION_OP_TYPES,
        "reason": (
          "Global activation quantization touches integer code lookup. "
          "Compute-only activation quantization on the float32 package avoids that path but fails on fp16 scale "
          "versus fp32 input dtype. The successful local path uses an fp16 base package."
        ),
      },
      "w8a8_candidate_matrix": {
        "status": "planned",
        "candidate_label": args.candidate_label,
        "calibration_op_group_sizes": args.candidate_matrix_op_group_sizes,
        "sample_sources": ["representative", "talker"],
        "note": (
          "Candidate matrix runs are comparable by label, bucket, sample source, activation scope, "
          "and calibration_op_group_size. Output audio remains evaluation-only."
        ),
      },
    },
    "next_command": (
      "uv run --python 3.12 "
      "scripts/repo-maintenance/coreml-qwen3tts/quantize-speech-tokenizer-decoder-coreml.py "
      "--no-preflight-only --run-weight-only --run-w8a8 --activation-scope compute_only "
      "--model-package .local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-fp16.mlpackage "
      "--w8a8-output .local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed-fp16-w8a8-compute-only.mlpackage "
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
  calibration_fixture = load_json(resolve_package_path(args.calibration_fixture))
  bucket_plan_path = resolve_package_path(args.bucket_plan)
  bucket_plan = load_json(bucket_plan_path) if bucket_plan_path.is_file() else None
  talker_code_fixture_path = resolve_package_path(args.talker_code_fixture)
  talker_code_fixture = load_json(talker_code_fixture_path) if talker_code_fixture_path.is_file() else None
  sample_data, sample_data_report = build_runtime_sample_data(
    args,
    runtime_fixture,
    calibration_fixture,
    talker_code_fixture,
    bucket_plan,
    report["source"]["conversion_target"]["input_shape"],
  )
  model = ct.models.MLModel(str(model_package), compute_units=ct.ComputeUnit.CPU_ONLY)
  baseline_output = None
  if args.verify_prediction:
    baseline_prediction = model.predict(sample_data[0])
    baseline_output = np.asarray(baseline_prediction["audio_values"])

  report["runtime"] = {
    "sample_data": sample_data_report,
    "baseline_prediction": {
      "output_shape": list(baseline_output.shape),
      "output_dtype": str(baseline_output.dtype),
      "output_min": float(baseline_output.min()),
      "output_max": float(baseline_output.max()),
      "output_rms": float(np.sqrt(np.mean(np.square(baseline_output)))),
    } if baseline_output is not None else None,
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
    group_sizes = args.candidate_matrix_op_group_sizes if args.run_w8a8_matrix else [args.calibration_op_group_size]
    try:
      for group_size in group_sizes:
        output_path = resolve_package_path(args.w8a8_output)
        if args.run_w8a8_matrix:
          output_path = output_path.with_name(
            f"{output_path.stem}-group-{group_size}{output_path.suffix}"
          )
        report["runtime"]["results"].append(
          run_w8a8_quantization(
            model,
            sample_data,
            sample_data_report,
            output_path,
            args.replace_existing,
            group_size,
            args.activation_scope,
            args.activation_op_types,
            baseline_output,
            args.candidate_label,
          )
        )
    except Exception as error:
      report["runtime"]["results"].append(
        {
          "status": "failed",
          "mode": (
            f"w8a8_{args.sample_source}_smoke_"
            f"{args.activation_scope}"
          ),
          "error_type": type(error).__name__,
          "error_message": str(error),
          "activation_scope": args.activation_scope,
          "activation_op_types": args.activation_op_types,
          "candidate_label": args.candidate_label,
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
  parser.add_argument("--talker-code-fixture", type=Path, default=Path(DEFAULT_TALKER_CODE_FIXTURE_PATH))
  parser.add_argument("--bucket-plan", type=Path, default=Path(DEFAULT_BUCKET_PLAN_PATH))
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
  parser.add_argument("--candidate-label", default=None)
  parser.add_argument("--run-w8a8-matrix", action="store_true")
  parser.add_argument("--candidate-matrix-op-group-sizes", type=int, nargs="+", default=[1, 8, 16, 32])
  parser.add_argument(
    "--sample-source",
    default="synthetic",
    choices=["synthetic", "representative", "talker"],
  )
  parser.add_argument("--bucket", type=int, default=None)
  parser.add_argument(
    "--activation-scope",
    default="global",
    choices=["global", "compute_only"],
  )
  parser.add_argument(
    "--activation-op-types",
    nargs="+",
    default=None,
    help=(
      "Override compute_only activation op type scope. "
      "Defaults to conv linear matmul conv_transpose."
    ),
  )
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
