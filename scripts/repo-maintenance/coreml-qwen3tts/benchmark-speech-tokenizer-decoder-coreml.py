#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "coremltools>=8.3.0,<10",
#   "numpy>=2.0.0",
# ]
# ///
"""Benchmark the converted Qwen3-TTS 12 Hz speech-tokenizer decoder Core ML package."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np


DEFAULT_MODEL_PACKAGE = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed.mlpackage"
DEFAULT_FIXTURE_PATH = "docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"
DEFAULT_CONVERSION_REPORT_PATH = (
  "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json"
)


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def package_root() -> Path:
  return Path(__file__).resolve().parents[3]


def load_json(path: Path) -> dict[str, Any]:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception as error:
    raise RuntimeError(f"Unable to read JSON file at '{path}'.") from error


def resolve_package_path(path: Path) -> Path:
  return path if path.is_absolute() else package_root() / path


def relative_package_path(path: Path) -> str:
  try:
    return str(path.resolve().relative_to(package_root()))
  except ValueError:
    return path.name


def sysctl_value(name: str) -> str | None:
  try:
    return subprocess.check_output(["sysctl", "-n", name], text=True).strip()
  except Exception:
    return None


def hardware_report() -> dict[str, Any]:
  memory_size = sysctl_value("hw.memsize")
  return {
    "platform": platform.platform(),
    "mac_ver": platform.mac_ver()[0],
    "machine": platform.machine(),
    "processor": platform.processor(),
    "cpu_brand": sysctl_value("machdep.cpu.brand_string"),
    "physical_cpu_count": sysctl_value("hw.physicalcpu"),
    "logical_cpu_count": sysctl_value("hw.logicalcpu"),
    "memory_bytes": int(memory_size) if memory_size and memory_size.isdigit() else None,
  }


def compute_unit_value(name: str) -> ct.ComputeUnit:
  return {
    "all": ct.ComputeUnit.ALL,
    "cpuOnly": ct.ComputeUnit.CPU_ONLY,
    "cpuAndGPU": ct.ComputeUnit.CPU_AND_GPU,
    "cpuAndNeuralEngine": ct.ComputeUnit.CPU_AND_NE,
  }[name]


def stats_ms(values: list[float]) -> dict[str, float]:
  ordered = sorted(values)
  return {
    "min_ms": min(values),
    "median_ms": statistics.median(values),
    "mean_ms": statistics.fmean(values),
    "p95_ms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))],
    "max_ms": max(values),
  }


def benchmark_compute_unit(
  model_package: Path,
  compute_unit: str,
  audio_codes: np.ndarray,
  warmup_runs: int,
  measured_runs: int,
  baseline_output: np.ndarray | None,
) -> tuple[dict[str, Any], np.ndarray | None]:
  load_start = time.perf_counter()
  model = ct.models.MLModel(str(model_package), compute_units=compute_unit_value(compute_unit))
  load_duration_ms = (time.perf_counter() - load_start) * 1000

  warmup_durations = []
  for _ in range(warmup_runs):
    start = time.perf_counter()
    model.predict({"audio_codes": audio_codes})
    warmup_durations.append((time.perf_counter() - start) * 1000)

  measured_durations = []
  last_output: np.ndarray | None = None
  for _ in range(measured_runs):
    start = time.perf_counter()
    prediction = model.predict({"audio_codes": audio_codes})
    measured_durations.append((time.perf_counter() - start) * 1000)
    last_output = np.asarray(prediction["audio_values"])

  result = {
    "status": "succeeded",
    "compute_units": compute_unit,
    "load_duration_ms": load_duration_ms,
    "warmup_runs": warmup_runs,
    "measured_runs": measured_runs,
    "warmup": stats_ms(warmup_durations) if warmup_durations else None,
    "measured": stats_ms(measured_durations),
    "output_shape": list(last_output.shape) if last_output is not None else None,
    "output_dtype": str(last_output.dtype) if last_output is not None else None,
    "output_min": float(last_output.min()) if last_output is not None else None,
    "output_max": float(last_output.max()) if last_output is not None else None,
    "output_rms": float(np.sqrt(np.mean(np.square(last_output)))) if last_output is not None else None,
  }

  if baseline_output is not None and last_output is not None:
    delta = last_output - baseline_output
    result["baseline_delta"] = {
      "max_abs_diff": float(np.max(np.abs(delta))),
      "mean_abs_diff": float(np.mean(np.abs(delta))),
    }

  return result, last_output


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  fixture_path = resolve_package_path(args.fixture)
  conversion_report_path = resolve_package_path(args.conversion_report)
  model_package = resolve_package_path(args.model_package)

  if not model_package.exists():
    raise RuntimeError(
      f"Core ML package '{args.model_package}' does not exist. "
      "Run the decoder conversion probe before benchmarking."
    )

  fixture = load_json(fixture_path)
  conversion_report = load_json(conversion_report_path)
  audio_codes = np.asarray(fixture["encoded"]["audio_codes"], dtype=np.int32)[None, :, :]

  results = []
  baseline_output = None
  for compute_unit in args.compute_units:
    try:
      result, output = benchmark_compute_unit(
        model_package,
        compute_unit,
        audio_codes,
        args.warmup_runs,
        args.measured_runs,
        baseline_output,
      )
      if baseline_output is None:
        baseline_output = output
    except Exception as error:
      result = {
        "status": "failed",
        "compute_units": compute_unit,
        "error_type": type(error).__name__,
        "error_message": str(error),
      }
    results.append(result)

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_benchmark",
    "source": {
      "model_package": relative_package_path(model_package),
      "fixture_path": str(args.fixture),
      "conversion_report_path": str(args.conversion_report),
      "conversion_source": conversion_report["source"],
      "conversion_target": conversion_report["conversion_target"],
      "coremltools_version": ct.__version__,
    },
    "hardware": hardware_report(),
    "benchmark": {
      "input_name": "audio_codes",
      "input_shape": list(audio_codes.shape),
      "input_dtype": str(audio_codes.dtype),
      "warmup_runs": args.warmup_runs,
      "measured_runs": args.measured_runs,
      "compute_units_order": args.compute_units,
      "dispatch_note": (
        "Core ML compute-unit selection is a load-time preference. "
        "This timing report does not prove actual Neural Engine dispatch; "
        "use Instruments or Core ML performance diagnostics for dispatch evidence."
      ),
      "results": results,
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Benchmark the converted Qwen3-TTS 12 Hz speech-tokenizer decoder Core ML package."
  )
  parser.add_argument("--model-package", type=Path, default=Path(DEFAULT_MODEL_PACKAGE))
  parser.add_argument("--fixture", type=Path, default=Path(DEFAULT_FIXTURE_PATH))
  parser.add_argument("--conversion-report", type=Path, default=Path(DEFAULT_CONVERSION_REPORT_PATH))
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--warmup-runs", type=int, default=3)
  parser.add_argument("--measured-runs", type=int, default=10)
  parser.add_argument(
    "--compute-units",
    nargs="+",
    default=["cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine", "all"],
    choices=["all", "cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine"],
  )
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
