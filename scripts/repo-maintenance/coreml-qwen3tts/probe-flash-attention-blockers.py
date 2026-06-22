#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Probe FlashAttention blockers relevant to Qwen3-TTS attention research.

The script keeps third-party packages out of SpeakSwiftly. It invokes bounded
child probes through uv, records their stdout/stderr/exit codes, and emits a
portable JSON report that maintainers can compare across machines.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ChildProbe:
  name: str
  command: list[str]
  timeout_seconds: int = 90


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def run_child(probe: ChildProbe) -> dict[str, Any]:
  try:
    completed = subprocess.run(
      probe.command,
      check=False,
      capture_output=True,
      text=True,
      timeout=probe.timeout_seconds,
    )
  except subprocess.TimeoutExpired as error:
    return {
      "name": probe.name,
      "status": "timeout",
      "timeout_seconds": probe.timeout_seconds,
      "command": redact_command(probe.command),
      "stdout": error.stdout or "",
      "stderr": error.stderr or "",
    }

  parsed_stdout: Any | None = None
  stdout = completed.stdout.strip()
  if stdout:
    try:
      parsed_stdout = json.loads(stdout)
    except json.JSONDecodeError:
      parsed_stdout = None

  return {
    "name": probe.name,
    "status": "passed" if completed.returncode == 0 else "failed",
    "returncode": completed.returncode,
    "command": redact_command(probe.command),
    "stdout_json": parsed_stdout,
    "stdout": "" if parsed_stdout is not None else completed.stdout,
    "stderr": completed.stderr,
  }


def redact_command(command: list[str]) -> list[str]:
  redacted: list[str] = []
  skip_next = False
  for index, part in enumerate(command):
    if skip_next:
      skip_next = False
      continue
    if part == "-c" and index + 1 < len(command):
      redacted.extend(["-c", "<inline probe>"])
      skip_next = True
      continue
    if part.startswith("/") and "metal-flash-sdpa" in part:
      redacted.append("<local-metal-flash-sdpa-checkout>")
      continue
    redacted.append(part)
  return redacted


def mpsops_probe_command() -> list[str]:
  snippet = r"""
import json
import torch
import mps_flash_attn

cases = [
  {"name": "tiny_noncausal", "shape": [1, 1, 16, 32], "causal": False},
  {"name": "tiny_causal", "shape": [1, 1, 16, 32], "causal": True},
  {"name": "qwen_like_expanded_kv_noncausal", "shape": [1, 16, 256, 128], "causal": False},
]

results = []
for case in cases:
  batch, heads, seq, dim = case["shape"]
  torch.manual_seed(0)
  query = torch.randn(batch, heads, seq, dim, device="mps", dtype=torch.float16)
  key = torch.randn_like(query)
  value = torch.randn_like(query)
  try:
    output = mps_flash_attn.flash_attention(
      query,
      key,
      value,
      is_causal=case["causal"],
    )
    results.append({
      "case": case,
      "status": "ok",
      "output_shape": list(output.shape),
      "output_dtype": str(output.dtype),
      "finite": bool(torch.isfinite(output).all().item()),
    })
  except Exception as error:
    results.append({
      "case": case,
      "status": "exception",
      "error_type": type(error).__name__,
      "error": str(error).splitlines()[0],
    })

print(json.dumps({
  "package": "mps-flash-attn",
  "package_version": getattr(mps_flash_attn, "__version__", None),
  "torch_version": torch.__version__,
  "mps_available": bool(torch.backends.mps.is_available()),
  "is_available": bool(mps_flash_attn.is_available()),
  "cases": results,
}, sort_keys=True))
"""
  return [
    "uv",
    "run",
    "--python",
    "3.12",
    "--with",
    "torch",
    "--with",
    "numpy",
    "--with",
    "mps-flash-attn",
    "python",
    "-c",
    snippet,
  ]


def metal_sdpa_probe_command(package_path: str) -> list[str]:
  snippet = r"""
import json
import torch
import torch.nn.functional as F
import metal_flash_sdpa
from metal_flash_sdpa import MetalFlashAttentionForward


def reference_attention(query, key, value, scale, causal):
  scores = torch.matmul(query.float(), key.float().transpose(-2, -1)) * scale
  if causal:
    rows, cols = scores.shape[-2:]
    mask = torch.triu(torch.ones(rows, cols, dtype=torch.bool), diagonal=1)
    scores = scores.masked_fill(mask, float("-inf"))
  probs = torch.softmax(scores, dim=-1)
  return torch.matmul(probs, value.float())


def compare(output, reference):
  diff = (output.cpu().float() - reference).abs()
  return {
    "max_abs_diff": float(diff.max().item()),
    "mean_abs_diff": float(diff.mean().item()),
  }


def tensor_case(name, shape, dtype_name, causal):
  dtype = {
    "float32": torch.float32,
    "float16": torch.float16,
    "bfloat16": torch.bfloat16,
  }[dtype_name]
  batch, heads, seq, dim = shape
  torch.manual_seed(0)
  query = torch.randn(batch, heads, seq, dim, device="mps", dtype=dtype)
  key = torch.randn(batch, heads, seq, dim, device="mps", dtype=dtype)
  value = torch.randn(batch, heads, seq, dim, device="mps", dtype=dtype)
  scale = dim ** -0.5

  direct = MetalFlashAttentionForward.apply(query, key, value, scale, causal)
  causal_ref = reference_attention(query.cpu(), key.cpu(), value.cpu(), scale, causal=True)
  noncausal_ref = reference_attention(query.cpu(), key.cpu(), value.cpu(), scale, causal=False)

  metal_flash_sdpa.enable()
  metal_flash_sdpa.reset_dispatch_count()
  native_before_disable = F.scaled_dot_product_attention(
    query,
    key,
    value,
    is_causal=causal,
    scale=scale,
  )
  dispatch_count = int(metal_flash_sdpa.get_dispatch_count())
  metal_flash_sdpa.disable()

  return {
    "name": name,
    "shape": shape,
    "dtype": dtype_name,
    "causal_argument": causal,
    "direct_vs_causal_reference": compare(direct, causal_ref),
    "direct_vs_noncausal_reference": compare(direct, noncausal_ref),
    "patched_sdpa_dispatch_count": dispatch_count,
    "patched_sdpa_vs_direct": compare(native_before_disable, direct.cpu().float()),
  }


cases = [
  tensor_case("square_fp32_causal", [1, 8, 256, 64], "float32", True),
  tensor_case("square_fp16_causal", [1, 8, 256, 64], "float16", True),
  tensor_case("square_bf16_causal", [1, 8, 256, 64], "bfloat16", True),
  tensor_case("qwen_like_fp16_causal_expanded_kv", [1, 16, 256, 128], "float16", True),
  tensor_case("qwen_like_fp16_noncausal_expanded_kv", [1, 16, 256, 128], "float16", False),
]

print(json.dumps({
  "package": "metal-flash-sdpa",
  "package_version": getattr(metal_flash_sdpa, "__version__", None),
  "torch_version": torch.__version__,
  "mps_available": bool(torch.backends.mps.is_available()),
  "cases": cases,
}, sort_keys=True))
"""
  return [
    "uv",
    "run",
    "--with",
    "torch",
    "--with",
    "numpy",
    "--with",
    package_path,
    "python",
    "-c",
    snippet,
  ]


def classify(results: list[dict[str, Any]]) -> dict[str, Any]:
  summary: dict[str, Any] = {
    "mpsops_agx_crash": "not_run",
    "metal_flash_sdpa_causal_correctness": "not_run",
    "recommendation": "pause_flashattention_dependency_adoption",
  }

  for result in results:
    if result["name"] == "mpsops_metalasm_kernel_creation":
      stderr = result.get("stderr", "")
      if result.get("returncode") not in (0, None) and "XPC_ERROR_CONNECTION_INTERRUPTED" in stderr:
        summary["mpsops_agx_crash"] = (
          "reproduced_on_tiny_noncausal_shape_before_larger_qwen_like_cases"
        )
      elif result.get("status") == "passed":
        summary["mpsops_agx_crash"] = "not_reproduced"
      else:
        summary["mpsops_agx_crash"] = "failed_before_kernel_creation"

    if result["name"] == "metal_flash_sdpa_causal_parity":
      stdout_json = result.get("stdout_json") or {}
      cases = stdout_json.get("cases") or []
      fp16_causal = next(
        (case for case in cases if case.get("name") == "square_fp16_causal"),
        None,
      )
      fp32_causal = next(
        (case for case in cases if case.get("name") == "square_fp32_causal"),
        None,
      )
      if fp16_causal and fp32_causal:
        fp16_causal_diff = fp16_causal["direct_vs_causal_reference"]["max_abs_diff"]
        fp16_noncausal_diff = fp16_causal["direct_vs_noncausal_reference"]["max_abs_diff"]
        fp32_causal_diff = fp32_causal["direct_vs_causal_reference"]["max_abs_diff"]
        if fp32_causal_diff < 0.001 and fp16_causal_diff > 1.0 and fp16_noncausal_diff < 0.01:
          summary["metal_flash_sdpa_causal_correctness"] = (
            "lower_precision_causal_path_matches_noncausal_reference"
          )
        elif fp16_causal_diff < 0.01:
          summary["metal_flash_sdpa_causal_correctness"] = "causal_parity_passed"
        else:
          summary["metal_flash_sdpa_causal_correctness"] = "causal_parity_failed_uncategorized"

  return summary


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Run bounded FlashAttention blocker probes and emit a structured JSON report."
    )
  )
  parser.add_argument(
    "--metal-flash-sdpa-path",
    default=os.environ.get("METAL_FLASH_SDPA_CHECKOUT"),
    help=(
      "Local checkout path for alliprice/metal-flash-sdpa. "
      "The path is used only at runtime and is redacted from the report. "
      "Can also be supplied with METAL_FLASH_SDPA_CHECKOUT."
    ),
  )
  parser.add_argument(
    "--skip-mpsops",
    action="store_true",
    help="Skip the mpsops/mps-flash-attention AGX crash probe.",
  )
  parser.add_argument(
    "--skip-metal-sdpa",
    action="store_true",
    help="Skip the alliprice/metal-flash-sdpa causal parity probe.",
  )
  parser.add_argument(
    "--output",
    type=Path,
    default=None,
    help="Optional JSON report destination. Defaults to stdout only.",
  )
  return parser.parse_args()


def main() -> None:
  args = parse_args()
  probes: list[ChildProbe] = []

  if not args.skip_mpsops:
    probes.append(
      ChildProbe(
        name="mpsops_metalasm_kernel_creation",
        command=mpsops_probe_command(),
        timeout_seconds=90,
      )
    )

  if not args.skip_metal_sdpa:
    if not args.metal_flash_sdpa_path:
      raise RuntimeError(
        "metal-flash-sdpa checkout path is required. Pass --metal-flash-sdpa-path, "
        "set METAL_FLASH_SDPA_CHECKOUT, or use --skip-metal-sdpa."
      )
    package_path = Path(args.metal_flash_sdpa_path)
    if not package_path.exists():
      raise RuntimeError(
        f"metal-flash-sdpa checkout not found at '{package_path}'. "
        "Pass --metal-flash-sdpa-path or use --skip-metal-sdpa."
      )
    probes.append(
      ChildProbe(
        name="metal_flash_sdpa_causal_parity",
        command=metal_sdpa_probe_command(str(package_path)),
        timeout_seconds=90,
      )
    )

  results = [run_child(probe) for probe in probes]
  report = {
    "schema_version": 1,
    "created_at_utc": current_utc_timestamp(),
    "purpose": "bounded_flashattention_blocker_probe_for_qwen3tts",
    "host": {
      "system": platform.system(),
      "release": platform.release(),
      "machine": platform.machine(),
      "processor": platform.processor(),
      "python": sys.version.split()[0],
    },
    "qwen3_tts_attention_target": {
      "query_heads": 16,
      "key_value_heads": 8,
      "head_dim": 128,
      "causal": True,
      "decode_pattern": "autoregressive",
    },
    "results": results,
    "classification": classify(results),
  }

  encoded = json.dumps(report, indent=2, sort_keys=True)
  if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(f"{encoded}\n")
  print(encoded)


if __name__ == "__main__":
  main()
