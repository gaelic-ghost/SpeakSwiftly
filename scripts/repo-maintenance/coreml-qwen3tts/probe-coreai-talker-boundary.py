#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# ///
"""Plan the first Core AI / coreai-torch Qwen3-TTS talker-boundary probe."""

from __future__ import annotations

import argparse
import importlib.metadata
import importlib.util
import json
import platform
import re
import subprocess
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_REPORT = "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json"
DEFAULT_EXPORT_SMOKE_REPORT = "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json"
LOCAL_PATH_REPLACEMENTS = [
  (str(Path.home()), "<local-home-path>"),
]


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


def sanitize_local_paths(value: Any) -> Any:
  if isinstance(value, dict):
    return {key: sanitize_local_paths(item) for key, item in value.items()}
  if isinstance(value, list):
    return [sanitize_local_paths(item) for item in value]
  if isinstance(value, str):
    sanitized = value
    for prefix, replacement in LOCAL_PATH_REPLACEMENTS:
      sanitized = sanitized.replace(prefix, replacement)
    return sanitized
  return value


def command_output(command: list[str], env: dict[str, str] | None = None) -> dict[str, Any]:
  try:
    completed = subprocess.run(
      command,
      check=False,
      capture_output=True,
      text=True,
      env=env,
    )
  except FileNotFoundError:
    return {
      "command": command,
      "found": False,
      "exit_code": None,
      "stdout": "",
      "stderr": "command not found",
    }
  return {
    "command": command,
    "found": completed.returncode == 0,
    "exit_code": completed.returncode,
    "stdout": sanitize_local_paths(completed.stdout.strip()),
    "stderr": sanitize_local_paths(completed.stderr.strip()),
  }


def module_status(module_name: str, package_name: str | None = None) -> dict[str, Any]:
  package = package_name or module_name
  found = importlib.util.find_spec(module_name) is not None
  version = None
  if found:
    try:
      version = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
      version = "unknown"
  return {
    "module": module_name,
    "package": package,
    "found": found,
    "version": version,
  }


def dependency_report() -> dict[str, Any]:
  return {
    "python": {
      "version": platform.python_version(),
      "implementation": platform.python_implementation(),
    },
    "packages": [
      module_status("torch"),
      module_status("coreai_torch", package_name="coreai-torch"),
    ],
  }


def beta_tooling_report(args: argparse.Namespace) -> dict[str, Any]:
  import os

  env = os.environ.copy()
  developer_dir_source = "environment"
  if args.developer_dir:
    env["DEVELOPER_DIR"] = str(args.developer_dir)
    developer_dir_source = "argument"
  coreai_build = command_output(["xcrun", "--find", "coreai-build"], env=env)
  xctrace = command_output(["xcrun", "--find", "xctrace"], env=env)
  xctrace_templates = command_output(
    ["xcrun", "xctrace", "list", "templates"],
    env=env,
  )
  return {
    "developer_dir_source": developer_dir_source if env.get("DEVELOPER_DIR") else "unset",
    "developer_dir_is_set": bool(env.get("DEVELOPER_DIR")),
    "summary": {
      "coreai_build_found": coreai_build["found"],
      "xctrace_found": xctrace["found"],
      "core_ai_template_found": "Core AI" in (xctrace_templates.get("stdout") or ""),
    },
    "coreai_build": coreai_build,
    "xctrace": xctrace,
    "xctrace_core_ai_template": xctrace_templates,
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  export_smoke_report_path = relative_package_path(resolve_package_path(Path(DEFAULT_EXPORT_SMOKE_REPORT)))
  next_command = (
    "uv run --script scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
    "--mode export-smoke --allow-runtime-imports "
    f"--report {export_smoke_report_path}"
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


def package_versions(packages: list[dict[str, Any]]) -> dict[str, Any]:
  return {item["package"]: item["version"] for item in packages if item["found"]}


def exported_graph_targets(exported_program: Any) -> list[str]:
  graph = exported_program.graph_module.graph
  targets = []
  for node in graph.nodes:
    if node.op == "call_function":
      targets.append(str(node.target))
    elif node.op == "call_module":
      targets.append(f"module:{node.target}")
  return targets


def coreai_program_summary(program: Any) -> dict[str, Any]:
  stable_repr = re.sub(r" at 0x[0-9a-fA-F]+", " at <address>", repr(program)[:500])
  summary = {
    "python_type": f"{type(program).__module__}.{type(program).__name__}",
    "repr_prefix": stable_repr,
  }
  functions = getattr(program, "functions", None)
  if isinstance(functions, dict):
    summary["function_names"] = sorted(functions.keys())
  return summary


def run_coreai_export_smoke(args: argparse.Namespace) -> dict[str, Any]:
  dependencies = dependency_report()
  missing = [
    item["package"]
    for item in dependencies["packages"]
    if item["package"] in {"torch", "coreai-torch"} and not item["found"]
  ]
  report: dict[str, Any] = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_talker_boundary_export_smoke",
    "status": "blocked_missing_runtime_dependencies" if missing else "running",
    "purpose": (
      "Try the smallest local Core AI / coreai-torch export smoke for the "
      "Qwen3-TTS talker first-codec-token boundary without downloading Qwen weights."
    ),
    "source": {
      "model_id": args.model_id,
      "upstream_commit": args.upstream_commit,
      "preflight_fixture": "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json",
    },
    "dependencies": dependencies,
    "local_tooling": beta_tooling_report(args),
    "target_subgraph": {
      "name": "toy_qwen_talker_first_codec_token_boundary",
      "input_shapes": {
        "input_embeds": [1, args.sequence_length, args.hidden_size],
        "key_cache": [1, args.attention_heads, args.sequence_length, args.head_dim],
        "value_cache": [1, args.attention_heads, args.sequence_length, args.head_dim],
      },
      "features": [
        "RMSNorm-style normalization",
        "RoPE-style pair rotation",
        "causal scaled_dot_product_attention",
        "KV-cache-shaped inputs",
        "first-codebook logits projection",
      ],
    },
    "missing_dependencies": missing,
  }
  if missing:
    report["next_action"] = (
      "Install torch and coreai-torch in an explicit opt-in environment, then rerun "
      "export-smoke. Do not add either package as a project dependency yet."
    )
    return report

  try:
    import torch
    import torch.nn.functional as F
    import coreai_torch
    from coreai_torch import TorchConverter

    torch.manual_seed(args.seed)

    class ToyQwenTalkerBoundary(torch.nn.Module):
      def __init__(self) -> None:
        super().__init__()
        self.norm_weight = torch.nn.Parameter(torch.ones(args.hidden_size))
        self.q_proj = torch.nn.Linear(args.hidden_size, args.hidden_size, bias=False)
        self.out_proj = torch.nn.Linear(args.hidden_size, args.codec_vocab_size, bias=False)

      def forward(self, input_embeds, key_cache, value_cache):
        variance = input_embeds.pow(2).mean(dim=-1, keepdim=True)
        hidden = input_embeds * torch.rsqrt(variance + 1e-5)
        hidden = hidden * self.norm_weight
        query = self.q_proj(hidden).reshape(
          1,
          args.sequence_length,
          args.attention_heads,
          args.head_dim,
        )
        query = query.transpose(1, 2)
        even = query[..., 0::2]
        odd = query[..., 1::2]
        rotated = torch.stack((-odd, even), dim=-1).flatten(-2)
        positions = torch.arange(args.sequence_length, dtype=query.dtype, device=query.device)
        frequencies = torch.linspace(0.0, 1.0, args.head_dim, dtype=query.dtype, device=query.device)
        angles = positions.reshape(1, 1, args.sequence_length, 1) * frequencies.reshape(1, 1, 1, args.head_dim)
        query = query * torch.cos(angles) + rotated * torch.sin(angles)
        attended = F.scaled_dot_product_attention(query, key_cache, value_cache, is_causal=True)
        last_hidden = attended.transpose(1, 2).reshape(1, args.sequence_length, args.hidden_size)[:, -1, :]
        return self.out_proj(last_hidden)

    model = ToyQwenTalkerBoundary().eval()
    sample = (
      torch.randn(1, args.sequence_length, args.hidden_size),
      torch.randn(1, args.attention_heads, args.sequence_length, args.head_dim),
      torch.randn(1, args.attention_heads, args.sequence_length, args.head_dim),
    )
    exported = torch.export.export(model, args=sample)
    decomposed = exported.run_decompositions(coreai_torch.get_decomp_table())
    converter = TorchConverter().add_exported_program(decomposed)
    coreai_program = converter.to_coreai()
    if args.optimize_coreai_program:
      coreai_program.optimize()

    targets = exported_graph_targets(decomposed)
    report.update(
      {
        "status": "converted_to_coreai_ir",
        "dependency_versions": package_versions(dependencies["packages"]),
        "exported_graph": {
          "call_targets": targets,
          "call_target_count": len(targets),
          "contains_scaled_dot_product_attention": any(
            "scaled_dot_product_attention" in target for target in targets
          ),
          "contains_rsqrt": any("rsqrt" in target for target in targets),
          "contains_cos": any("cos" in target for target in targets),
          "contains_sin": any("sin" in target for target in targets),
        },
        "coreai_program": coreai_program_summary(coreai_program),
        "next_action": (
          "Review the exported call targets and Core AI program summary before trying "
          "the real Qwen3-TTS talker boundary."
        ),
      }
    )
  except Exception as error:
    report.update(
      {
        "status": "export_smoke_failed",
        "error": {
          "type": type(error).__name__,
          "message": str(error),
          "traceback": traceback.format_exc().splitlines()[-12:],
        },
        "next_action": (
          "Use the failure to decide whether the next slice needs custom lowerings, "
          "different sample shapes, or an ExecuTorch comparison first."
        ),
      }
    )
  return report


def write_report(path: Path, report: dict[str, Any]) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  sanitized = sanitize_local_paths(report)
  path.write_text(json.dumps(sanitized, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--mode", choices=["preflight", "export-smoke"], default="preflight")
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--created-at-utc")
  parser.add_argument("--report", type=Path, default=Path(DEFAULT_REPORT))
  parser.add_argument("--developer-dir", type=Path)
  parser.add_argument("--allow-runtime-imports", action="store_true")
  parser.add_argument("--optimize-coreai-program", action="store_true")
  parser.add_argument("--sequence-length", type=int, default=4)
  parser.add_argument("--hidden-size", type=int, default=32)
  parser.add_argument("--attention-heads", type=int, default=4)
  parser.add_argument("--head-dim", type=int, default=8)
  parser.add_argument("--codec-vocab-size", type=int, default=128)
  parser.add_argument("--seed", type=int, default=13)
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
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_EXPORT_SMOKE_REPORT)
    report = run_coreai_export_smoke(args)
  else:
    report = build_report(args)
  write_report(resolve_package_path(args.report), report)
  if args.print_json:
    print(json.dumps(report, indent=2, sort_keys=False))


if __name__ == "__main__":
  main()
