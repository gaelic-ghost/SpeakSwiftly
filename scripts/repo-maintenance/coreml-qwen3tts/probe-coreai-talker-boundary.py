#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# ///
"""Plan the first Core AI / coreai-torch Qwen3-TTS talker-boundary probe."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_REPORT = "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json"


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
    return str(path)


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  report_path = resolve_package_path(args.report)
  next_command = (
    "uv run --script scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
    "--mode export-smoke --allow-runtime-imports "
    f"--report {relative_package_path(report_path)}"
  )
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_talker_boundary_preflight",
    "purpose": (
      "Select the smallest Qwen3-TTS talker/code-predictor boundary worth trying "
      "through torch.export and coreai-torch before any full-model conversion or "
      "runtime backend integration."
    ),
    "source": {
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "coreai_torch_docs": "https://apple.github.io/coreai-torch/main/",
      "coreai_torch_conversion_workflows": (
        "https://apple.github.io/coreai-torch/main/guides/conversion-workflows.html"
      ),
      "coreai_torch_externalization": (
        "https://apple.github.io/coreai-torch/main/guides/externalization.html"
      ),
    },
    "target_subgraph": {
      "name": "qwen3_tts_talker_first_codec_token_boundary",
      "checkpoint": "0.6B Base before CustomVoice or reference-audio paths",
      "voice_path": "fixed Base path with no reference audio and no audible output",
      "why_this_boundary": (
        "It exercises the hard Apple-native graph questions before the audio decoder: "
        "text-side conditioning, autoregressive talker attention, KV/cache shape, "
        "codebook ordering, and the first codec-token output."
      ),
      "required_boundaries": [
        "text token ids and prompt-wrapped inputs stay explicit",
        "attention or SDPA remains compiler-visible",
        "RoPE remains compiler-visible",
        "RMSNorm remains compiler-visible",
        "KV cache input and output shapes are named and stable",
        "first codebook token output is captured for parity",
        "code predictor continuation boundary is identified but not required for the first smoke",
      ],
      "excluded_from_first_probe": [
        "full Qwen3-TTS generation",
        "reference-audio conditioning",
        "speech-tokenizer audio decode",
        "audible quality comparison",
        "public SpeechBackend integration",
      ],
    },
    "runtime_routes": [
      {
        "route": "coreai_torch",
        "first_question": "Can torch.export plus coreai-torch preserve useful talker boundaries?",
        "success_signal": "Inspectable Core AI IR with preserved composite op boundaries and fixed-shape inputs.",
      },
      {
        "route": "hand_rolled_core_ml",
        "first_question": "Does the existing stage-by-stage Core ML path remain clearer for residency and dispatch?",
        "success_signal": "Per-stage parity, timing, and dispatch evidence stay easier to reason about.",
      },
      {
        "route": "executorch_mlx",
        "first_question": "Would ExecuTorch's MLX delegate avoid custom Apple GPU plumbing for autoregressive stages?",
        "success_signal": "A Qwen-like exported graph runs with less bespoke code and acceptable runtime complexity.",
      },
      {
        "route": "executorch_core_ml",
        "first_question": "Would ExecuTorch's Core ML delegate give useful partitioning and packaging comparison?",
        "success_signal": "It exposes enough placement and timing evidence without hiding residency control.",
      },
    ],
    "first_slice": {
      "status": "preflight_only",
      "next_command": next_command,
      "acceptance_criteria": [
        "records torch, coreai-torch, and Python versions",
        "uses fixed tiny tensors or a tiny saved upstream fixture",
        "does not download full model weights unless explicitly allowed",
        "reports every preserved composite op boundary",
        "reports every custom lowering or unsupported op",
        "records whether first-token parity can be checked from the emitted outputs",
      ],
      "stop_conditions": [
        "torch.export cannot capture the selected boundary without executing broad generation side effects",
        "coreai-torch loses attention, RoPE, RMSNorm, or cache boundaries in a way that prevents useful parity checks",
        "the route requires custom Metal kernels before a first-token parity probe exists",
      ],
    },
    "guardrails": [
      "Do not add a public SpeechBackend for this slice.",
      "Do not run real-model audible generation for this slice.",
      "Do not download full Qwen3-TTS weights without an explicit opt-in flag.",
      "Keep Core ML decoder residency evidence as the baseline until Core AI produces matched outputs.",
    ],
  }


def write_report(path: Path, report: dict[str, Any]) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(report, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--mode", choices=["preflight", "export-smoke"], default="preflight")
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--created-at-utc")
  parser.add_argument("--report", type=Path, default=Path(DEFAULT_REPORT))
  parser.add_argument("--allow-runtime-imports", action="store_true")
  parser.add_argument("--print-json", action="store_true")
  return parser.parse_args()


def main() -> None:
  args = parse_args()
  if args.mode == "export-smoke" and not args.allow_runtime_imports:
    raise RuntimeError(
      "Export-smoke mode will import runtime ML packages. Rerun with "
      "--allow-runtime-imports after the preflight report is reviewed."
    )
  if args.mode == "export-smoke":
    raise RuntimeError(
      "Export-smoke mode is intentionally reserved for the next slice. "
      "This script currently pins the reviewed preflight boundary only."
    )

  report = build_report(args)
  write_report(resolve_package_path(args.report), report)
  if args.print_json:
    print(json.dumps(report, indent=2, sort_keys=False))


if __name__ == "__main__":
  main()
