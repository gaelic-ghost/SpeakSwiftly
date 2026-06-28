#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "numpy>=2.0.0",
# ]
# ///
"""Capture Instruments Core ML traces for the converted Qwen3-TTS decoder package."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_BENCHMARK_SCRIPT = "scripts/repo-maintenance/coreml-qwen3tts/benchmark-speech-tokenizer-decoder-coreml.py"
DEFAULT_MODEL_PACKAGE = ".local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed.mlpackage"
DEFAULT_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"
DEFAULT_TALKER_CODE_FIXTURE_PATH = ".local/coreml-qwen3tts/talker-code-fixture-qwen3-12hz.json"
DEFAULT_CONVERSION_REPORT_PATH = (
  "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json"
)
DEFAULT_TRACE_DIR = ".local/coreml-qwen3tts/traces"


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


def run_command(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
  return subprocess.run(
    command,
    cwd=cwd,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    check=False,
  )


def sysctl_value(name: str) -> str | None:
  result = run_command(["sysctl", "-n", name], package_root())
  return result.stdout.strip() if result.returncode == 0 else None


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


def duration_text_to_ms(value: str | None) -> float | None:
  if not value:
    return None
  stripped = value.strip()
  if not stripped:
    return None
  try:
    return float(stripped) / 1_000_000
  except ValueError:
    return None


def duration_stats(values: list[float]) -> dict[str, float] | None:
  if not values:
    return None
  ordered = sorted(values)
  return {
    "count": len(values),
    "total_ms": sum(values),
    "min_ms": min(values),
    "median_ms": statistics.median(values),
    "mean_ms": statistics.fmean(values),
    "max_ms": max(values),
    "p95_ms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))],
  }


def export_trace_table(trace_path: Path, schema: str, output_path: Path) -> dict[str, Any]:
  command = [
    "xcrun",
    "xctrace",
    "export",
    "--input",
    str(trace_path),
    "--xpath",
    f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]',
  ]
  result = run_command(command, package_root())
  output_path.parent.mkdir(parents=True, exist_ok=True)
  output_path.write_text(result.stdout, encoding="utf-8")
  if result.returncode != 0:
    return {
      "schema": schema,
      "status": "failed",
      "error_message": result.stdout.strip(),
      "xml_path": relative_package_path(output_path),
    }

  root = ET.fromstring(result.stdout)
  rows = root.findall(".//row")
  durations = [
    duration_ms
    for row in rows
    if (duration_ms := duration_text_to_ms(row.findtext("duration"))) is not None
  ]
  labels = sorted(
    {
      element.attrib["fmt"]
      for row in rows
      for element in row.iter()
      if element.tag in {"ane-event-name", "mps-event-name", "metal-device-name", "coreml-model-event"}
      and "fmt" in element.attrib
      and element.attrib["fmt"]
    }
  )
  return {
    "schema": schema,
    "status": "succeeded",
    "row_count": len(rows),
    "duration": duration_stats(durations),
    "labels": labels[:20],
    "xml_path": relative_package_path(output_path),
  }


def trace_compute_unit(args: argparse.Namespace, compute_unit: str) -> dict[str, Any]:
  trace_dir = resolve_package_path(args.trace_dir)
  trace_dir.mkdir(parents=True, exist_ok=True)
  run_id = args.run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
  trace_path = trace_dir / f"qwen3tts-decoder-coreml-{compute_unit}-{run_id}.trace"
  benchmark_output = trace_dir / f"qwen3tts-decoder-coreml-{compute_unit}-{run_id}-benchmark.json"

  uv_path = args.uv_path
  if uv_path is None:
    which_result = run_command(["which", "uv"], package_root())
    uv_path = which_result.stdout.strip() if which_result.returncode == 0 else "uv"

  command = [
    "xcrun",
    "xctrace",
    "record",
    "--template",
    "Core ML",
    "--output",
    str(trace_path),
    "--target-stdout",
    "-",
    "--launch",
    "--",
    uv_path,
    "run",
    str(args.benchmark_script),
    "--model-package",
    str(args.model_package),
    "--fixture",
    str(args.fixture),
    "--talker-code-fixture",
    str(args.talker_code_fixture),
    "--conversion-report",
    str(args.conversion_report),
    "--sample-source",
    args.sample_source,
    "--warmup-runs",
    str(args.warmup_runs),
    "--measured-runs",
    str(args.measured_runs),
    "--compute-units",
    compute_unit,
    "--output",
    str(benchmark_output),
  ]
  if args.sample_id is not None:
    command.extend(["--sample-id", args.sample_id])

  started = time.perf_counter()
  result = run_command(command, package_root())
  elapsed_ms = (time.perf_counter() - started) * 1000
  if result.returncode != 0:
    return {
      "status": "failed",
      "compute_units": compute_unit,
      "elapsed_ms": elapsed_ms,
      "error_message": result.stdout.strip(),
      "trace_path": relative_package_path(trace_path),
    }

  table_summaries = [
    export_trace_table(trace_path, schema, trace_dir / f"{trace_path.stem}-{schema}.xml")
    for schema in [
      "coreml-os-signpost",
      "ane-hw-intervals-internal",
      "mps-hw-intervals",
      "metal-gpu-intervals",
      "metal-application-command-buffer-submissions",
    ]
  ]

  benchmark = json.loads(benchmark_output.read_text(encoding="utf-8"))
  return {
    "status": "succeeded",
    "compute_units": compute_unit,
    "elapsed_ms": elapsed_ms,
    "trace_path": relative_package_path(trace_path),
    "benchmark_output": relative_package_path(benchmark_output),
    "benchmark_result": benchmark["benchmark"]["results"][0],
    "trace_tables": table_summaries,
  }


def xcode_report() -> dict[str, Any]:
  result = run_command(["xcodebuild", "-version"], package_root())
  return {
    "xcodebuild_version": result.stdout.strip().splitlines(),
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  results = [trace_compute_unit(args, compute_unit) for compute_unit in args.compute_units]
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_xctrace_profile",
    "source": {
      "benchmark_script": str(args.benchmark_script),
      "model_package": str(args.model_package),
      "fixture_path": str(args.fixture),
      "talker_code_fixture_path": str(args.talker_code_fixture),
      "conversion_report_path": str(args.conversion_report),
      "sample_source": args.sample_source,
      "sample_id": args.sample_id,
      "template": "Core ML",
      "xcode": xcode_report(),
      "xctrace_templates": ["Core ML"],
      "trace_dir": str(args.trace_dir),
    },
    "hardware": hardware_report(),
    "profile": {
      "warmup_runs": args.warmup_runs,
      "measured_runs": args.measured_runs,
      "compute_units_order": args.compute_units,
      "dispatch_evidence_note": (
        "ANE and MPS row counts come from exported Instruments trace tables. "
        "Rows indicate recorded activity in those subsystems during the launched benchmark, "
        "not a complete per-op placement map."
      ),
      "results": results,
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Capture Instruments Core ML traces for the converted Qwen3-TTS decoder package."
  )
  parser.add_argument("--benchmark-script", type=Path, default=Path(DEFAULT_BENCHMARK_SCRIPT))
  parser.add_argument("--model-package", type=Path, default=Path(DEFAULT_MODEL_PACKAGE))
  parser.add_argument("--fixture", type=Path, default=Path(DEFAULT_FIXTURE_PATH))
  parser.add_argument("--talker-code-fixture", type=Path, default=Path(DEFAULT_TALKER_CODE_FIXTURE_PATH))
  parser.add_argument("--conversion-report", type=Path, default=Path(DEFAULT_CONVERSION_REPORT_PATH))
  parser.add_argument("--sample-source", default="synthetic", choices=["synthetic", "talker"])
  parser.add_argument("--sample-id", default=None)
  parser.add_argument("--trace-dir", type=Path, default=Path(DEFAULT_TRACE_DIR))
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--run-id", default=None)
  parser.add_argument("--warmup-runs", type=int, default=2)
  parser.add_argument("--measured-runs", type=int, default=20)
  parser.add_argument("--uv-path", default=None)
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
