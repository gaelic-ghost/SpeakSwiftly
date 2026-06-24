#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# ///
"""Plan the first Core AI / coreai-torch Qwen3-TTS talker-boundary probe."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import inspect
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
DEFAULT_REPORT = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json"
DEFAULT_EXPORT_SMOKE_REPORT = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json"
DEFAULT_REAL_BOUNDARY_REPORT = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-plan-12hz.json"
DEFAULT_REAL_CAPTURE_REPORT = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-capture-12hz.json"
DEFAULT_REAL_CODE_PREDICTOR_EXPORT_REPORT = (
  "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-code-predictor-export-smoke-12hz.json"
)
DEFAULT_REAL_MAIN_TALKER_EXPORT_REPORT = (
  "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-main-talker-export-smoke-12hz.json"
)
DEFAULT_COREAI_COMPRESSION_PREFLIGHT_REPORT = (
  "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-ane-compression-plan-12hz.json"
)
DEFAULT_TEXT_TOKEN_FIXTURE = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/text-token-fixture-0.6b-base.json"
DEFAULT_QWEN_SOURCE = ".local/coreai-qwen3tts/Qwen3-TTS-source"
COREAI_RUNTIME_WITH_REQUIREMENTS = [
  "torch==2.11.0",
  "torchaudio==2.11.0",
  "transformers==4.57.3",
  "accelerate==1.12.0",
  "numpy>=2.0.0",
  "numba>=0.61.0",
  "soundfile>=0.13.0",
  "librosa>=0.11.0",
  "sox>=1.5.0",
  "onnxruntime>=1.23.0",
  "einops>=0.8.0",
  "coreai-torch==0.4.0",
]
COREAI_COMPRESSION_WITH_REQUIREMENTS = COREAI_RUNTIME_WITH_REQUIREMENTS + [
  "coreai-opt",
]
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


def runtime_command_prefix() -> str:
  with_args = " ".join(f"--with '{requirement}'" for requirement in COREAI_RUNTIME_WITH_REQUIREMENTS)
  return f"uv run --python 3.12 {with_args}"


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
  package_names = {
    "torch": "torch",
    "torchaudio": "torchaudio",
    "transformers": "transformers",
    "accelerate": "accelerate",
    "numpy": "numpy",
    "numba": "numba",
    "soundfile": "soundfile",
    "librosa": "librosa",
    "sox": "sox",
    "onnxruntime": "onnxruntime",
    "einops": "einops",
    "coreai_torch": "coreai-torch",
  }
  return {
    "python": {
      "version": platform.python_version(),
      "implementation": platform.python_implementation(),
    },
    "packages": [module_status(module, package_name=package) for module, package in package_names.items()],
    "uv_with_requirements": COREAI_RUNTIME_WITH_REQUIREMENTS,
  }


def compression_dependency_report() -> dict[str, Any]:
  report = dependency_report()
  report["packages"].append(module_status("coreai_opt", package_name="coreai-opt"))
  report["uv_with_requirements"] = COREAI_COMPRESSION_WITH_REQUIREMENTS
  return report


def coreai_build_capability_report(args: argparse.Namespace) -> dict[str, Any]:
  import os

  env = os.environ.copy()
  developer_dir_source = "environment"
  if args.developer_dir:
    env["DEVELOPER_DIR"] = str(args.developer_dir)
    developer_dir_source = "argument"

  help_output = command_output(["xcrun", "coreai-build", "--help"], env=env)
  compile_help = command_output(["xcrun", "coreai-build", "help", "compile"], env=env)
  inspect_help = command_output(["xcrun", "coreai-build", "help", "inspect"], env=env)
  separate_inspect = command_output(["xcrun", "--find", "coreai-inspect"], env=env)
  separate_perf = command_output(["xcrun", "--find", "coreai-perf"], env=env)

  compile_stdout = compile_help.get("stdout") or ""
  inspect_stdout = inspect_help.get("stdout") or ""
  help_stdout = help_output.get("stdout") or ""
  return {
    "developer_dir_source": developer_dir_source if env.get("DEVELOPER_DIR") else "unset",
    "developer_dir_is_set": bool(env.get("DEVELOPER_DIR")),
    "coreai_build_found": help_output["found"],
    "subcommands": [
      subcommand
      for subcommand in ["compile", "package", "inspect", "metadata"]
      if subcommand in help_stdout
    ],
    "compile": {
      "preferred_compute_values": [
        value
        for value in ["gpu", "neural-engine", "none"]
        if value in compile_stdout
      ],
      "supports_frequent_reshapes_hint": "--expect-frequent-reshapes" in compile_stdout,
    },
    "inspect": {
      "supports_json": "--json" in inspect_stdout,
      "supports_storage": "--storage" in inspect_stdout,
      "supports_compute": "--compute" in inspect_stdout,
      "supports_ops": "--ops" in inspect_stdout,
    },
    "separate_tools": {
      "coreai_inspect_found": separate_inspect["found"],
      "coreai_perf_found": separate_perf["found"],
    },
    "raw": {
      "help": help_output,
      "compile_help": compile_help,
      "inspect_help": inspect_help,
      "coreai_inspect": separate_inspect,
      "coreai_perf": separate_perf,
    },
  }


def coreai_compression_api_report(allow_runtime_imports: bool) -> dict[str, Any]:
  report: dict[str, Any] = {
    "status": "not_imported",
    "requires_allow_runtime_imports": True,
  }
  if not allow_runtime_imports:
    return report

  try:
    import coreai_opt
    import coreai_torch

    api: dict[str, Any] = {
      "coreai_opt_version": getattr(coreai_opt, "__version__", importlib.metadata.version("coreai-opt")),
      "coreai_torch_version": getattr(coreai_torch, "__version__", importlib.metadata.version("coreai-torch")),
    }
    try:
      import torch
      from coreai_opt.palettization import KMeansPalettizer, KMeansPalettizerConfig
      from coreai_opt.quantization import Quantizer, QuantizerConfig

      toy_linear_for_quantization = torch.nn.Linear(2, 2)
      toy_linear_for_palettization = torch.nn.Linear(2, 2)
      quantizer = Quantizer(toy_linear_for_quantization, QuantizerConfig.presets.w8())
      palettizer = KMeansPalettizer(toy_linear_for_palettization, KMeansPalettizerConfig.presets.w8())
      api["quantization"] = {
        "has_quantizer": inspect.isclass(Quantizer),
        "has_quantizer_config": inspect.isclass(QuantizerConfig),
        "has_w8_preset": hasattr(getattr(QuantizerConfig, "presets", object()), "w8"),
        "has_w4_preset": hasattr(getattr(QuantizerConfig, "presets", object()), "w4"),
        "w8_preset_type": f"{type(QuantizerConfig.presets.w8()).__module__}.{type(QuantizerConfig.presets.w8()).__name__}",
        "lifecycle_methods": [
          method
          for method in ["prepare", "step", "finalize", "calibration_mode", "training_mode"]
          if callable(getattr(quantizer, method, None))
        ],
      }
      api["palettization"] = {
        "has_kmeans_palettizer": inspect.isclass(KMeansPalettizer),
        "has_kmeans_palettizer_config": inspect.isclass(KMeansPalettizerConfig),
        "has_w8_preset": hasattr(getattr(KMeansPalettizerConfig, "presets", object()), "w8"),
        "has_w6_preset": hasattr(getattr(KMeansPalettizerConfig, "presets", object()), "w6"),
        "has_w4_preset": hasattr(getattr(KMeansPalettizerConfig, "presets", object()), "w4"),
        "w8_preset_type": f"{type(KMeansPalettizerConfig.presets.w8()).__module__}.{type(KMeansPalettizerConfig.presets.w8()).__name__}",
        "lifecycle_methods": [
          method
          for method in ["prepare", "finalize", "calibration_mode", "training_mode"]
          if callable(getattr(palettizer, method, None))
        ],
      }
    except Exception as error:
      api["api_import_error"] = {
        "type": type(error).__name__,
        "message": str(error),
      }

    return {
      "status": "imported",
      "requires_allow_runtime_imports": True,
      "api": api,
    }
  except Exception as error:
    return {
      "status": "import_failed",
      "requires_allow_runtime_imports": True,
      "error": {
        "type": type(error).__name__,
        "message": str(error),
      },
    }


def build_coreai_compression_preflight(args: argparse.Namespace) -> dict[str, Any]:
  dependencies = compression_dependency_report()
  package_by_name = {item["package"]: item for item in dependencies["packages"]}
  coreai_build = coreai_build_capability_report(args)
  compression_api = coreai_compression_api_report(args.allow_runtime_imports)
  coreai_opt_package = package_by_name.get("coreai-opt", {"found": False, "version": None})
  coreai_torch_package = package_by_name.get("coreai-torch", {"found": False, "version": None})
  api = compression_api.get("api", {})
  quantization_api = api.get("quantization", {})
  palettization_api = api.get("palettization", {})

  next_command = (
    f"{runtime_command_prefix()} --with 'coreai-opt' "
    "scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
    "--mode coreai-compression-preflight --allow-runtime-imports "
    "--developer-dir /Users/galew/Applications/Betas/Xcode-beta.app/Contents/Developer "
    f"--report {DEFAULT_COREAI_COMPRESSION_PREFLIGHT_REPORT}"
  )
  first_probe_command = (
    "scripts/repo-maintenance/coreml-qwen3tts/run-with-live-service-headroom.sh -- "
    f"{runtime_command_prefix()} --with 'coreai-opt' "
    "scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
    "--mode real-code-predictor-export-smoke --allow-runtime-imports --allow-model-load "
    "--report .local/coreml-qwen3tts/coreai-code-predictor-w8-preflight.json"
  )

  return {
    "schema_version": 1,
    "mode": "coreai_ane_compression_plan",
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "status": (
      "validated_tooling_preflight"
      if compression_api["status"] == "imported" and coreai_build["coreai_build_found"]
      else "design_only_no_model_probe"
    ),
    "source": {
      "model_id": args.model_id,
      "scope": "Core AI runtime and compression route for Qwen3-TTS talker/code-predictor stages",
    },
    "dependencies": dependencies,
    "local_tooling": {
      "xcode_beta_coreai_build": {
        "found": coreai_build["coreai_build_found"],
        "subcommands": coreai_build["subcommands"],
        "compile_preferred_compute_values": coreai_build["compile"]["preferred_compute_values"],
        "compile_supports_frequent_reshapes_hint": coreai_build["compile"]["supports_frequent_reshapes_hint"],
        "inspect_json": coreai_build["inspect"]["supports_json"],
        "inspect_compute": coreai_build["inspect"]["supports_compute"],
        "inspect_storage": coreai_build["inspect"]["supports_storage"],
        "inspect_ops": coreai_build["inspect"]["supports_ops"],
      },
      "separate_coreai_inspect_binary": {
        "found": coreai_build["separate_tools"]["coreai_inspect_found"],
        "note": "Use coreai-build inspect instead." if not coreai_build["separate_tools"]["coreai_inspect_found"] else None,
      },
      "separate_coreai_perf_binary": {
        "found": coreai_build["separate_tools"]["coreai_perf_found"],
      },
      "ambient_coreai_opt_python_package": {
        "found": coreai_opt_package["found"],
        "version": coreai_opt_package["version"],
        "note": (
          "Install explicitly in an opt-in probe environment before compression runtime work."
          if not coreai_opt_package["found"]
          else "Available in the current probe environment."
        ),
      },
      "coreai_torch": {
        "observed_version": coreai_torch_package["version"] or "not_installed",
        "compression_support_observed_in_installed_package": {
          "palettized_weight_module": bool(palettization_api.get("has_kmeans_palettizer")),
          "subbyte_quantization_helpers": bool(quantization_api.get("has_quantizer")),
          "runtime_benchmarker": compression_api["status"] == "imported",
        },
      },
    },
    "compression_api": compression_api,
    "route": {
      "name": "coreai_opt_to_coreai_torch_to_coreai_build",
      "steps": [
        "Start from the PyTorch Qwen3-TTS boundary wrapper that already has exported-program parity.",
        "Apply coreai-opt compression to the PyTorch module or selected submodules where the API supports the desired weight and activation form.",
        "Validate compressed PyTorch parity against the frozen-cache or explicit-cache reference before conversion.",
        "Convert with coreai-torch to Core AI IR and save a .aimodel asset.",
        "Compile with coreai-build compile --preferred-compute neural-engine and a matched platform/deployment target.",
        "Inspect the .aimodel or .aimodelc with coreai-build inspect --json to capture storage, operation, and compute evidence.",
        "Profile with Core AI Runtime or Instruments before making ANE latency claims.",
      ],
      "why_coreai_torch_alone_is_not_enough": (
        "coreai-torch converts PyTorch ExportedPrograms to Core AI IR; Core AI compression "
        "is handled by the separate coreai-opt workflow or by compression modules already "
        "represented in the PyTorch graph."
      ),
    },
    "compression_options": [
      {
        "name": "w8_weight_only",
        "package": "coreai-opt",
        "first_target": "code-predictor linear layers",
        "calibration_required": False,
        "decision_use": "Fast size and storage smoke before activation quantization.",
      },
      {
        "name": "w8a8_activation_quantization",
        "package": "coreai-opt",
        "first_target": "linear and matmul-heavy code-predictor or main-talker projections",
        "calibration_required": True,
        "decision_use": "ANE-relevant path if compressed PyTorch parity and Core AI compile/inspect survive.",
      },
      {
        "name": "palettization",
        "package": "coreai-opt",
        "first_target": "large linear weights after W8 baseline",
        "calibration_required": "optional_by_workflow",
        "decision_use": (
          "Size and memory-pressure candidate; do not assume latency wins until runtime "
          "inspect/profile evidence exists."
        ),
      },
      {
        "name": "joint_palettization_activation_quantization",
        "package": "coreai-opt",
        "first_target": "defer until simple W8 or W8A8 probes have parity evidence",
        "calibration_required": True,
        "decision_use": "Escalation path for size or ANE dispatch only after simple routes are measured.",
      },
    ],
    "first_probe": {
      "name": "code_predictor_w8_weight_only_compile_inspect",
      "status": "next_concrete_slice",
      "reason": (
        "The real code-predictor boundary already exports to Core AI IR with exact parity "
        "and avoids the mutable main-talker KV-cache blocker."
      ),
      "acceptance_criteria": [
        "coreai-opt or equivalent compression setup is installed only in an opt-in uv script environment",
        "compressed PyTorch module preserves exported-program parity within a recorded tolerance",
        "coreai-torch emits Core AI IR after compression",
        "coreai-build compile accepts the saved .aimodel with --preferred-compute neural-engine",
        "coreai-build inspect --json records storage, operation, and compute metadata",
        "no public SpeechBackend or runtime dependency is added",
      ],
      "non_goals": [
        "audible generation",
        "full model conversion",
        "resident runtime integration",
        "claiming ANE benefit from compile preference alone",
      ],
    },
    "ane_evidence_gates": [
      {
        "gate": "compile_preference",
        "signal": "coreai-build accepts --preferred-compute neural-engine",
        "sufficient_for_ane_claim": False,
      },
      {
        "gate": "compiled_model_inspect",
        "signal": "coreai-build inspect --json reports compute, storage, and operation metadata",
        "sufficient_for_ane_claim": "partial",
      },
      {
        "gate": "runtime_profile",
        "signal": "Core AI Runtime or Instruments shows actual placement and latency for the compressed boundary",
        "sufficient_for_ane_claim": True,
      },
    ],
    "risks": [
      "Core AI may compile with neural-engine preference while still dispatching some operations elsewhere.",
      "Activation quantization may reproduce the Core ML decoder lesson: broad W8A8 can drift audibly, so per-op scope matters.",
      "Main-talker mutable cache remains a separate blocker even if code-predictor compression works.",
      "Palettization can reduce package size without improving hot latency.",
    ],
    "evidence_sources": [
      "https://developer.apple.com/machine-learning/",
      "https://developer.apple.com/documentation/coreai",
      "https://github.com/apple/coreai-torch",
      "https://apple.github.io/coreai-torch/main/",
      "https://github.com/apple/coreai-optimization",
      "https://apple.github.io/coreai-optimization/",
    ],
    "next_command": next_command,
    "first_probe_command": first_probe_command,
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
  real_boundary_report_path = relative_package_path(resolve_package_path(Path(DEFAULT_REAL_BOUNDARY_REPORT)))
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
    "second_slice": {
      "status": "planned_after_toy_conversion",
      "next_command": (
        "uv run --script scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
        f"--mode real-boundary-plan --report {real_boundary_report_path}"
      ),
      "acceptance_criteria": [
        "names the first real Qwen graph boundary to export after the toy smoke",
        "records which existing fixtures feed the boundary",
        "keeps model downloads and runtime imports opt-in",
        "separates the main talker decode step from code-predictor continuation",
      ],
    },
    "guardrails": [
      "Do not add a public SpeechBackend for this slice.",
      "Do not run real-model audible generation for this slice.",
      "Do not download full Qwen3-TTS weights without an explicit opt-in flag.",
      "Keep Core ML decoder residency evidence as the baseline until Core AI produces matched outputs.",
    ],
  }


def build_real_boundary_plan(args: argparse.Namespace) -> dict[str, Any]:
  real_capture_report_path = relative_package_path(resolve_package_path(Path(DEFAULT_REAL_CAPTURE_REPORT)))
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_real_talker_boundary_plan",
    "purpose": (
      "Define the first real Qwen3-TTS talker/code-predictor boundary to try "
      "through torch.export and coreai-torch after the toy Core AI conversion."
    ),
    "source": {
      "model_id": args.model_id,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
    },
    "prior_evidence": {
      "text_token_fixture": "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/text-token-fixture-0.6b-base.json",
      "talker_code_summary": "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-qwen3-12hz-summary.json",
      "external_coreml_inventory": (
        "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/external-coreml-qwen3tts-repo-inventory-2026-06-04.json"
      ),
      "toy_coreai_export": DEFAULT_EXPORT_SMOKE_REPORT,
    },
    "target_boundary": {
      "name": "qwen3_tts_main_talker_decode_step_after_prefill",
      "model_path": "0.6B Base fixed-voice path with no reference audio and no audible output",
      "why_this_boundary": (
        "The toy Core AI smoke proved the route can lower a Qwen-shaped attention block. "
        "The next useful real boundary is one main-talker decode step after upstream "
        "PyTorch has built prompt embeddings and prefilled the cache."
      ),
      "included": [
        "main talker decode step only",
        "previous first-codebook token id",
        "prefilled main-talker KV cache",
        "cache position or generation step",
        "RoPE, RMSNorm, attention or SDPA, and output logits",
        "first-codebook logits for parity",
      ],
      "identified_not_included": [
        "code-predictor continuation inputs for codebooks 1 through 15",
        "sampling and repetition-penalty policy",
        "speech-tokenizer decoder input assembly",
      ],
      "excluded": [
        "text tokenizer implementation",
        "full prompt assembly inside Core AI",
        "reference-audio conditioning",
        "full autoregressive generation loop",
        "speech-tokenizer audio decode",
        "audible playback or quality scoring",
        "public SpeechBackend integration",
      ],
    },
    "fixture_capture_contract": {
      "default_status": "design_only_no_model_download",
      "runtime_capture_requires": [
        "--allow-model-load",
        "Qwen3-TTS source checkout",
        "live-service headroom wrapper for real-model runs",
      ],
      "capture_outputs": [
        "prompt-wrapped text token ids",
        "prefill input embedding shape",
        "main-talker KV-cache tensor names and shapes",
        "decode-step tensor input names and dtypes",
        "first-codebook logits shape and deterministic hash",
        "top candidate token ids before sampling",
        "code-predictor boundary input names and shapes",
      ],
      "committed_output": (
        "Commit only compact metadata, tensor names, shapes, hashes, and top-k token ids. "
        "Keep large tensors under .local/coreml-qwen3tts."
      ),
    },
    "coreai_export_contract": {
      "route": "coreai_torch",
      "first_command_shape": (
        "Use an explicit uv environment with torch and coreai-torch, then export only "
        "the captured main-talker decode-step module."
      ),
      "success_criteria": [
        "torch.export captures the boundary without running full generation",
        "coreai-torch emits a Core AI program",
        "attention or SDPA remains visible in the exported graph",
        "RoPE and RMSNorm remain visible enough for parity triage",
        "KV-cache inputs and outputs keep stable names and shapes",
        "first-codebook logits can be compared against the PyTorch fixture",
      ],
      "stop_conditions": [
        "capture requires full audible generation or reference-audio conditioning",
        "torch.export cannot isolate the decode step from generation side effects",
        "Core AI conversion hides or drops the boundaries needed for first-token parity",
        "the route requires custom Metal kernels before a PyTorch parity fixture exists",
      ],
    },
    "next_runtime_capture": {
      "status": "ready_for_opt_in_real_model_probe",
      "command": (
        "scripts/repo-maintenance/coreml-qwen3tts/run-with-live-service-headroom.sh -- "
        f"{runtime_command_prefix()} "
        "scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py "
        f"--mode real-boundary-capture --allow-model-load --report {real_capture_report_path}"
      ),
    },
    "decision_after_slice": [
      "Continue CoreAI if first-token parity and boundary visibility are intact.",
      "Compare ExecuTorch MLX if CoreAI conversion works but runtime instrumentation or packaging looks poor.",
      "Compare ExecuTorch Core ML if CoreAI loses placement/residency control but export boundaries are clear.",
      "Fall back to hand-rolled Core ML stages if CoreAI cannot preserve the real talker boundary.",
    ],
  }


def tensor_summary(tensor: Any, *, include_hash: bool = True, topk: int | None = None) -> dict[str, Any]:
  import torch

  if tensor is None:
    return {"present": False}
  with torch.no_grad():
    detached = tensor.detach().cpu()
    summary: dict[str, Any] = {
      "present": True,
      "shape": list(detached.shape),
      "dtype": str(tensor.dtype).replace("torch.", ""),
      "device": str(tensor.device),
      "numel": int(detached.numel()),
    }
    if detached.is_floating_point():
      finite = torch.isfinite(detached)
      summary["finite"] = bool(finite.all().item()) if detached.numel() else True
      if detached.numel():
        summary["min"] = float(detached[finite].min().item()) if finite.any() else None
        summary["max"] = float(detached[finite].max().item()) if finite.any() else None
        summary["mean"] = float(detached[finite].float().mean().item()) if finite.any() else None
    elif detached.numel():
      summary["min"] = int(detached.min().item())
      summary["max"] = int(detached.max().item())
    if include_hash:
      hash_tensor = detached.contiguous()
      if hash_tensor.is_floating_point():
        hash_tensor = hash_tensor.float()
      else:
        hash_tensor = hash_tensor.to(torch.int64)
      summary["sha256"] = hashlib.sha256(hash_tensor.numpy().tobytes()).hexdigest()
    if topk is not None and detached.numel():
      flat = detached.reshape(-1).float()
      values, indices = torch.topk(flat, k=min(topk, flat.numel()))
      summary["topk"] = [
        {"index": int(index.item()), "value": float(value.item())}
        for value, index in zip(values, indices)
      ]
    return summary


def cache_summary(cache: Any) -> dict[str, Any]:
  if cache is None:
    return {"present": False}
  summary: dict[str, Any] = {
    "present": True,
    "python_type": f"{type(cache).__module__}.{type(cache).__name__}",
  }
  get_seq_length = getattr(cache, "get_seq_length", None)
  if callable(get_seq_length):
    try:
      summary["sequence_length"] = int(get_seq_length())
    except Exception as error:
      summary["sequence_length_error"] = f"{type(error).__name__}: {error}"
  layers = getattr(cache, "layers", None)
  if layers is not None:
    summary["layer_count"] = len(layers)
    layer_summaries = []
    for index, layer in enumerate(layers[:2]):
      keys = getattr(layer, "keys", None)
      values = getattr(layer, "values", None)
      layer_summaries.append(
        {
          "index": index,
          "python_type": f"{type(layer).__module__}.{type(layer).__name__}",
          "keys": tensor_summary(keys, include_hash=False) if keys is not None else {"present": False},
          "values": tensor_summary(values, include_hash=False) if values is not None else {"present": False},
        }
      )
    summary["first_layers"] = layer_summaries
  return summary


def load_json_fixture(path: Path) -> dict[str, Any]:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception as error:
    raise RuntimeError(f"Unable to read JSON fixture '{path}'.") from error


def text_prompt_ids(fixture: dict[str, Any], kind: str) -> list[int]:
  for prompt in fixture.get("prompts", []):
    if prompt.get("kind") == kind:
      return prompt["input_ids"]
  raise RuntimeError(f"Text token fixture does not contain a prompt with kind '{kind}'.")


def run_real_boundary_capture(args: argparse.Namespace) -> dict[str, Any]:
  if not args.allow_model_load:
    raise RuntimeError(
      "Real-boundary capture loads the cached Qwen model. Rerun with --allow-model-load "
      "through run-with-live-service-headroom.sh."
    )

  dependencies = dependency_report()
  report: dict[str, Any] = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_real_talker_boundary_capture",
    "status": "running",
    "purpose": (
      "Load the real cached Qwen3-TTS Base model, run a tiny non-audible generation, "
      "and capture the first main-talker decode-step boundary for Core AI export triage."
    ),
    "source": {
      "model_id": args.model_id,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "qwen_source": relative_package_path(resolve_package_path(args.qwen_source)),
      "text_token_fixture": relative_package_path(resolve_package_path(args.text_token_fixture)),
    },
    "dependencies": dependencies,
    "parameters": {
      "language": args.language,
      "device": args.device,
      "torch_dtype": args.torch_dtype,
      "max_new_tokens": args.max_new_tokens,
      "do_sample": args.do_sample,
      "subtalker_dosample": args.subtalker_dosample,
      "top_k": args.top_k,
      "top_p": args.top_p,
      "temperature": args.temperature,
      "subtalker_top_k": args.subtalker_top_k,
      "subtalker_top_p": args.subtalker_top_p,
      "subtalker_temperature": args.subtalker_temperature,
      "repetition_penalty": args.repetition_penalty,
    },
  }

  try:
    import sys
    import torch
    from huggingface_hub import snapshot_download

    qwen_source = resolve_package_path(args.qwen_source)
    if not (qwen_source / "qwen_tts" / "core" / "models" / "modeling_qwen3_tts.py").is_file():
      raise RuntimeError(f"Qwen3-TTS source checkout is missing at '{qwen_source}'.")
    sys.path.insert(0, str(qwen_source))

    from qwen_tts.core.models import Qwen3TTSConfig, Qwen3TTSForConditionalGeneration

    torch.manual_seed(args.seed)
    fixture = load_json_fixture(resolve_package_path(args.text_token_fixture))
    target_ids = text_prompt_ids(fixture, args.prompt_kind)
    input_ids = [torch.tensor([target_ids], dtype=torch.long)]

    snapshot_path = snapshot_download(args.model_id, local_files_only=True)
    dtype = getattr(torch, args.torch_dtype)
    config = Qwen3TTSConfig.from_pretrained(snapshot_path)
    model = Qwen3TTSForConditionalGeneration.from_pretrained(
      snapshot_path,
      config=config,
      local_files_only=True,
      dtype=dtype,
    )
    model.eval()
    model.to(args.device)
    input_ids = [item.to(args.device) for item in input_ids]

    captures: dict[str, Any] = {
      "talker_forward_calls": [],
      "code_predictor_generate_calls": [],
    }
    original_talker_forward = model.talker.forward
    original_code_predictor_generate = model.talker.code_predictor.generate

    def recording_code_predictor_generate(*cp_args: Any, **cp_kwargs: Any) -> Any:
      call_index = len(captures["code_predictor_generate_calls"])
      call_record = {
        "call_index": call_index,
        "inputs_embeds": tensor_summary(cp_kwargs.get("inputs_embeds"), include_hash=call_index == 0),
        "max_new_tokens": cp_kwargs.get("max_new_tokens"),
        "do_sample": cp_kwargs.get("do_sample"),
        "top_k": cp_kwargs.get("top_k"),
        "top_p": cp_kwargs.get("top_p"),
        "temperature": cp_kwargs.get("temperature"),
      }
      result = original_code_predictor_generate(*cp_args, **cp_kwargs)
      call_record["sequences"] = tensor_summary(result.sequences, include_hash=True)
      captures["code_predictor_generate_calls"].append(call_record)
      return result

    def recording_talker_forward(*forward_args: Any, **forward_kwargs: Any) -> Any:
      call_index = len(captures["talker_forward_calls"])
      stage = "prefill"
      inputs_embeds = forward_kwargs.get("inputs_embeds")
      if inputs_embeds is None or inputs_embeds.shape[1] <= 1:
        stage = "decode"
      call_record = {
        "call_index": call_index,
        "stage": stage,
        "input_ids": tensor_summary(forward_kwargs.get("input_ids"), include_hash=stage == "decode"),
        "inputs_embeds": tensor_summary(inputs_embeds, include_hash=stage == "decode"),
        "attention_mask": tensor_summary(forward_kwargs.get("attention_mask"), include_hash=False),
        "cache_position": tensor_summary(forward_kwargs.get("cache_position"), include_hash=False),
        "past_key_values": cache_summary(forward_kwargs.get("past_key_values")),
        "past_hidden": tensor_summary(forward_kwargs.get("past_hidden"), include_hash=stage == "decode"),
        "trailing_text_hidden": tensor_summary(forward_kwargs.get("trailing_text_hidden"), include_hash=False),
        "generation_step": (
          int(forward_kwargs["generation_step"])
          if forward_kwargs.get("generation_step") is not None
          and not hasattr(forward_kwargs.get("generation_step"), "item")
          else (
            int(forward_kwargs["generation_step"].item())
            if forward_kwargs.get("generation_step") is not None
            else None
          )
        ),
      }
      result = original_talker_forward(*forward_args, **forward_kwargs)
      call_record["logits"] = tensor_summary(result.logits[:, -1, :], include_hash=True, topk=8)
      call_record["output_past_key_values"] = cache_summary(result.past_key_values)
      call_record["output_past_hidden"] = tensor_summary(result.past_hidden, include_hash=stage == "decode")
      codec_ids = None
      if result.hidden_states is not None and len(result.hidden_states) > 1:
        codec_ids = result.hidden_states[-1]
      call_record["codec_ids"] = tensor_summary(codec_ids, include_hash=codec_ids is not None)
      captures["talker_forward_calls"].append(call_record)
      return result

    recording_talker_forward.__signature__ = inspect.signature(original_talker_forward)  # type: ignore[attr-defined]
    model.talker.code_predictor.generate = recording_code_predictor_generate
    model.talker.forward = recording_talker_forward

    with torch.inference_mode():
      talker_codes_list, talker_hidden_states_list = model.generate(
        input_ids=input_ids,
        languages=[args.language],
        speakers=[None],
        max_new_tokens=args.max_new_tokens,
        do_sample=args.do_sample,
        top_k=args.top_k,
        top_p=args.top_p,
        temperature=args.temperature,
        repetition_penalty=args.repetition_penalty,
        subtalker_dosample=args.subtalker_dosample,
        subtalker_top_k=args.subtalker_top_k,
        subtalker_top_p=args.subtalker_top_p,
        subtalker_temperature=args.subtalker_temperature,
      )

    decode_calls = [call for call in captures["talker_forward_calls"] if call["stage"] == "decode"]
    prefill_calls = [call for call in captures["talker_forward_calls"] if call["stage"] == "prefill"]
    final_codes = talker_codes_list[0] if talker_codes_list else None
    final_hidden = talker_hidden_states_list[0] if talker_hidden_states_list else None
    report.update(
      {
        "status": "captured_real_boundary",
        "resolved_model_snapshot": sanitize_local_paths(snapshot_path),
        "prompt": {
          "kind": args.prompt_kind,
          "token_count": len(target_ids),
          "input_ids_sha256": hashlib.sha256(
            torch.tensor(target_ids, dtype=torch.int64).numpy().tobytes()
          ).hexdigest(),
        },
        "capture": {
          "talker_forward_call_count": len(captures["talker_forward_calls"]),
          "prefill_call_count": len(prefill_calls),
          "decode_call_count": len(decode_calls),
          "code_predictor_generate_call_count": len(captures["code_predictor_generate_calls"]),
          "first_prefill_call": prefill_calls[0] if prefill_calls else None,
          "first_decode_call": decode_calls[0] if decode_calls else None,
          "first_code_predictor_generate_call": (
            captures["code_predictor_generate_calls"][0]
            if captures["code_predictor_generate_calls"]
            else None
          ),
        },
        "final_generation": {
          "talker_codes": tensor_summary(final_codes, include_hash=True),
          "talker_hidden_states": tensor_summary(final_hidden, include_hash=False),
          "first_codebook_prefix": (
            [int(item) for item in final_codes[: min(8, final_codes.shape[0]), 0].detach().cpu().tolist()]
            if final_codes is not None and final_codes.numel()
            else []
          ),
        },
        "next_action": (
          "Build a real-boundary CoreAI export wrapper around the captured first decode-step "
          "inputs, then compare exported logits against this PyTorch capture."
        ),
      }
    )
  except Exception as error:
    report.update(
      {
        "status": "real_boundary_capture_failed",
        "error": {
          "type": type(error).__name__,
          "message": str(error),
          "traceback": traceback.format_exc().splitlines()[-16:],
        },
        "next_action": "Fix the real capture blocker before attempting CoreAI export.",
      }
    )
  return report


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


def exported_graph_suspicious_nodes(exported_program: Any, *, limit: int = 40) -> list[dict[str, Any]]:
  graph = exported_program.graph_module.graph
  suspicious_fragments = [
    "full",
    "scaled_dot_product_attention",
    "_to_copy",
    "where",
    "zeros",
    "ones",
  ]
  nodes = []
  for index, node in enumerate(graph.nodes):
    target = str(node.target)
    if not any(fragment in target for fragment in suspicious_fragments):
      continue
    fake_value = node.meta.get("val")
    node_summary: dict[str, Any] = {
      "index": index,
      "name": node.name,
      "op": node.op,
      "target": target,
      "args": repr(node.args)[:500],
      "kwargs": repr(node.kwargs)[:500],
    }
    if hasattr(fake_value, "shape"):
      node_summary["shape"] = [int(dimension) for dimension in fake_value.shape]
    if hasattr(fake_value, "dtype"):
      node_summary["dtype"] = str(fake_value.dtype).replace("torch.", "")
    nodes.append(node_summary)
    if len(nodes) >= limit:
      break
  return nodes


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
      "preflight_fixture": "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json",
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


def run_real_code_predictor_export_smoke(args: argparse.Namespace) -> dict[str, Any]:
  if not args.allow_model_load:
    raise RuntimeError(
      "Real code-predictor export loads the cached Qwen model. Rerun with --allow-model-load "
      "through run-with-live-service-headroom.sh."
    )

  dependencies = dependency_report()
  report: dict[str, Any] = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_real_code_predictor_export_smoke",
    "status": "running",
    "purpose": (
      "Try torch.export plus coreai-torch on the real Qwen3-TTS code-predictor "
      "prefill boundary using embeddings captured from a tiny non-audible generation."
    ),
    "source": {
      "model_id": args.model_id,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "qwen_source": relative_package_path(resolve_package_path(args.qwen_source)),
      "text_token_fixture": relative_package_path(resolve_package_path(args.text_token_fixture)),
      "prior_capture": DEFAULT_REAL_CAPTURE_REPORT,
    },
    "dependencies": dependencies,
    "local_tooling": beta_tooling_report(args),
    "parameters": {
      "language": args.language,
      "device": args.device,
      "torch_dtype": args.torch_dtype,
      "max_new_tokens": args.max_new_tokens,
      "do_sample": args.do_sample,
      "subtalker_dosample": args.subtalker_dosample,
      "seed": args.seed,
    },
  }

  try:
    import sys
    import torch
    import coreai_torch
    from coreai_torch import TorchConverter
    from huggingface_hub import snapshot_download

    qwen_source = resolve_package_path(args.qwen_source)
    if not (qwen_source / "qwen_tts" / "core" / "models" / "modeling_qwen3_tts.py").is_file():
      raise RuntimeError(f"Qwen3-TTS source checkout is missing at '{qwen_source}'.")
    sys.path.insert(0, str(qwen_source))

    from qwen_tts.core.models import Qwen3TTSConfig, Qwen3TTSForConditionalGeneration

    torch.manual_seed(args.seed)
    fixture = load_json_fixture(resolve_package_path(args.text_token_fixture))
    target_ids = text_prompt_ids(fixture, args.prompt_kind)
    input_ids = [torch.tensor([target_ids], dtype=torch.long, device=args.device)]

    snapshot_path = snapshot_download(args.model_id, local_files_only=True)
    dtype = getattr(torch, args.torch_dtype)
    config = Qwen3TTSConfig.from_pretrained(snapshot_path)
    model = Qwen3TTSForConditionalGeneration.from_pretrained(
      snapshot_path,
      config=config,
      local_files_only=True,
      dtype=dtype,
    )
    model.eval()
    model.to(args.device)

    captured: dict[str, Any] = {}
    original_code_predictor_generate = model.talker.code_predictor.generate

    def recording_code_predictor_generate(*cp_args: Any, **cp_kwargs: Any) -> Any:
      if "inputs_embeds" not in captured:
        captured["inputs_embeds"] = cp_kwargs["inputs_embeds"].detach().clone()
      return original_code_predictor_generate(*cp_args, **cp_kwargs)

    model.talker.code_predictor.generate = recording_code_predictor_generate
    with torch.inference_mode():
      model.generate(
        input_ids=input_ids,
        languages=[args.language],
        speakers=[None],
        max_new_tokens=args.max_new_tokens,
        do_sample=args.do_sample,
        top_k=args.top_k,
        top_p=args.top_p,
        temperature=args.temperature,
        repetition_penalty=args.repetition_penalty,
        subtalker_dosample=args.subtalker_dosample,
        subtalker_top_k=args.subtalker_top_k,
        subtalker_top_p=args.subtalker_top_p,
        subtalker_temperature=args.subtalker_temperature,
      )

    if "inputs_embeds" not in captured:
      raise RuntimeError("Generation did not reach the code-predictor boundary.")

    code_predictor_inputs = captured["inputs_embeds"].to(args.device)

    class RealCodePredictorPrefillBoundary(torch.nn.Module):
      def __init__(self, code_predictor: torch.nn.Module) -> None:
        super().__init__()
        self.code_predictor = code_predictor

      def forward(self, inputs_embeds):
        outputs = self.code_predictor(
          input_ids=None,
          inputs_embeds=inputs_embeds,
          attention_mask=None,
          use_cache=False,
          output_attentions=False,
          output_hidden_states=False,
        )
        return outputs.logits

    boundary = RealCodePredictorPrefillBoundary(model.talker.code_predictor).eval()
    with torch.inference_mode():
      reference_logits = boundary(code_predictor_inputs)

    export_attempts = []
    exported = None
    for strict in [True, False]:
      try:
        exported = torch.export.export(boundary, args=(code_predictor_inputs,), strict=strict)
        export_attempts.append({"strict": strict, "status": "exported"})
        break
      except Exception as error:
        export_attempts.append(
          {
            "strict": strict,
            "status": "failed",
            "error": {
              "type": type(error).__name__,
              "message": str(error),
              "traceback": traceback.format_exc().splitlines()[-12:],
            },
          }
        )

    if exported is None:
      report.update(
        {
          "status": "torch_export_failed",
          "resolved_model_snapshot": sanitize_local_paths(snapshot_path),
          "captured_input": tensor_summary(code_predictor_inputs, include_hash=True),
          "reference_logits": tensor_summary(reference_logits, include_hash=True, topk=8),
          "torch_export_attempts": export_attempts,
          "next_action": (
            "Flatten or rewrite the code-predictor boundary before comparing CoreAI; "
            "the real module did not survive torch.export."
          ),
        }
      )
      return report

    decomposed = exported.run_decompositions(coreai_torch.get_decomp_table())
    exported_module = decomposed.module()
    with torch.inference_mode():
      exported_logits = exported_module(code_predictor_inputs)
    max_abs_diff = float((reference_logits.float() - exported_logits.float()).abs().max().item())
    targets = exported_graph_targets(decomposed)

    try:
      converter = TorchConverter().add_exported_program(decomposed)
      coreai_program = converter.to_coreai()
      if args.optimize_coreai_program:
        coreai_program.optimize()
      report.update(
        {
          "status": "converted_real_code_predictor_to_coreai_ir",
          "coreai_program": coreai_program_summary(coreai_program),
          "next_action": (
            "Inspect Core AI graph boundaries and then attempt a main-talker decode export "
            "with explicit cache tensors."
          ),
        }
      )
    except Exception as error:
      report.update(
        {
          "status": "coreai_conversion_failed_after_torch_export",
          "coreai_conversion_error": {
            "type": type(error).__name__,
            "message": str(error),
            "traceback": traceback.format_exc().splitlines()[-12:],
          },
          "next_action": (
            "Use the torch.export graph and failure point to decide whether CoreAI needs "
            "custom lowering before the main-talker cache boundary."
          ),
        }
      )

    report.update(
      {
        "resolved_model_snapshot": sanitize_local_paths(snapshot_path),
        "captured_input": tensor_summary(code_predictor_inputs, include_hash=True),
        "reference_logits": tensor_summary(reference_logits, include_hash=True, topk=8),
        "torch_export_attempts": export_attempts,
        "exported_program_parity": {
          "max_abs_diff": max_abs_diff,
          "matches_reference_within_1e_4": max_abs_diff <= 1e-4,
          "exported_logits": tensor_summary(exported_logits, include_hash=True, topk=8),
        },
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
        "dependency_versions": package_versions(dependencies["packages"]),
      }
    )
  except Exception as error:
    report.update(
      {
        "status": "real_code_predictor_export_smoke_failed",
        "error": {
          "type": type(error).__name__,
          "message": str(error),
          "traceback": traceback.format_exc().splitlines()[-16:],
        },
        "next_action": "Fix the real code-predictor export blocker before widening to the main talker.",
      }
    )
  return report


def run_real_main_talker_export_smoke(args: argparse.Namespace) -> dict[str, Any]:
  if not args.allow_model_load:
    raise RuntimeError(
      "Real main-talker export loads the cached Qwen model. Rerun with --allow-model-load "
      "through run-with-live-service-headroom.sh."
    )

  dependencies = dependency_report()
  report: dict[str, Any] = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreai_real_main_talker_export_smoke",
    "status": "running",
    "purpose": (
      "Capture the real first main-talker decode call, replay it through an explicit "
      "frozen-KV-cache wrapper, and try torch.export plus coreai-torch conversion."
    ),
    "source": {
      "model_id": args.model_id,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "qwen_source": relative_package_path(resolve_package_path(args.qwen_source)),
      "text_token_fixture": relative_package_path(resolve_package_path(args.text_token_fixture)),
      "prior_capture": DEFAULT_REAL_CAPTURE_REPORT,
      "prior_code_predictor_export": DEFAULT_REAL_CODE_PREDICTOR_EXPORT_REPORT,
    },
    "dependencies": dependencies,
    "local_tooling": beta_tooling_report(args),
    "parameters": {
      "language": args.language,
      "device": args.device,
      "torch_dtype": args.torch_dtype,
      "max_new_tokens": args.max_new_tokens,
      "do_sample": args.do_sample,
      "subtalker_dosample": args.subtalker_dosample,
      "seed": args.seed,
    },
  }

  try:
    import sys
    import torch
    import coreai_torch
    from coreai_torch import TorchConverter
    from huggingface_hub import snapshot_download

    qwen_source = resolve_package_path(args.qwen_source)
    if not (qwen_source / "qwen_tts" / "core" / "models" / "modeling_qwen3_tts.py").is_file():
      raise RuntimeError(f"Qwen3-TTS source checkout is missing at '{qwen_source}'.")
    sys.path.insert(0, str(qwen_source))

    from qwen_tts.core.models import Qwen3TTSConfig, Qwen3TTSForConditionalGeneration
    from qwen_tts.core.models.modeling_qwen3_tts import (
      ALL_ATTENTION_FUNCTIONS,
      apply_multimodal_rotary_pos_emb,
      eager_attention_forward,
    )

    torch.manual_seed(args.seed)
    fixture = load_json_fixture(resolve_package_path(args.text_token_fixture))
    target_ids = text_prompt_ids(fixture, args.prompt_kind)
    input_ids = [torch.tensor([target_ids], dtype=torch.long, device=args.device)]

    snapshot_path = snapshot_download(args.model_id, local_files_only=True)
    dtype = getattr(torch, args.torch_dtype)
    config = Qwen3TTSConfig.from_pretrained(snapshot_path)
    model = Qwen3TTSForConditionalGeneration.from_pretrained(
      snapshot_path,
      config=config,
      local_files_only=True,
      dtype=dtype,
    )
    model.eval()
    model.to(args.device)

    captured: dict[str, Any] = {}
    original_main_talker_forward = model.talker.model.forward

    def recording_main_talker_forward(*forward_args: Any, **forward_kwargs: Any) -> Any:
      past_key_values = forward_kwargs.get("past_key_values")
      inputs_embeds = forward_kwargs.get("inputs_embeds")
      sequence_length = None
      if past_key_values is not None and hasattr(past_key_values, "get_seq_length"):
        sequence_length = int(past_key_values.get_seq_length())
      should_capture = (
        "inputs_embeds" not in captured
        and inputs_embeds is not None
        and inputs_embeds.shape[1] == 1
        and sequence_length is not None
        and sequence_length > 0
      )
      if should_capture:
        cache_pairs = []
        for layer in past_key_values.layers:
          cache_pairs.append(
            (
              layer.keys.detach().clone(),
              layer.values.detach().clone(),
            )
          )
        captured.update(
          {
            "inputs_embeds": inputs_embeds.detach().clone(),
            "attention_mask": (
              forward_kwargs["attention_mask"].detach().clone()
              if forward_kwargs.get("attention_mask") is not None
              else None
            ),
            "position_ids": (
              forward_kwargs["position_ids"].detach().clone()
              if forward_kwargs.get("position_ids") is not None
              else None
            ),
            "cache_position": (
              forward_kwargs["cache_position"].detach().clone()
              if forward_kwargs.get("cache_position") is not None
              else None
            ),
            "cache_pairs": cache_pairs,
          }
        )
      outputs = original_main_talker_forward(*forward_args, **forward_kwargs)
      if should_capture:
        reference_logits = model.talker.codec_head(outputs.last_hidden_state)[:, -1, :]
        captured["reference_logits"] = reference_logits.detach().clone()
      return outputs

    model.talker.model.forward = recording_main_talker_forward
    with torch.inference_mode():
      model.generate(
        input_ids=input_ids,
        languages=[args.language],
        speakers=[None],
        max_new_tokens=args.max_new_tokens,
        do_sample=args.do_sample,
        top_k=args.top_k,
        top_p=args.top_p,
        temperature=args.temperature,
        repetition_penalty=args.repetition_penalty,
        subtalker_dosample=args.subtalker_dosample,
        subtalker_top_k=args.subtalker_top_k,
        subtalker_top_p=args.subtalker_top_p,
        subtalker_temperature=args.subtalker_temperature,
      )

    required = ["inputs_embeds", "position_ids", "cache_pairs", "reference_logits"]
    missing = [key for key in required if key not in captured or captured[key] is None]
    if missing:
      raise RuntimeError(f"Generation did not capture required main-talker decode fields: {missing}.")

    class FrozenCacheMainTalkerDecodeBoundary(torch.nn.Module):
      def __init__(
        self,
        talker_model: torch.nn.Module,
        codec_head: torch.nn.Module,
        cache_pairs: list[tuple[torch.Tensor, torch.Tensor]],
      ) -> None:
        super().__init__()
        self.layers = talker_model.layers
        self.norm = talker_model.norm
        self.rotary_emb = talker_model.rotary_emb
        self.codec_head = codec_head
        for index, (key, value) in enumerate(cache_pairs):
          self.register_buffer(f"past_key_{index}", key)
          self.register_buffer(f"past_value_{index}", value)

      def forward(self, inputs_embeds, position_ids):
        hidden_states = inputs_embeds
        position_embeddings = self.rotary_emb(hidden_states, position_ids)
        causal_mask = None
        text_position_ids = position_ids[0]

        for layer_index, decoder_layer in enumerate(self.layers):
          residual = hidden_states
          hidden_states = decoder_layer.input_layernorm(hidden_states)

          attention = decoder_layer.self_attn
          input_shape = hidden_states.shape[:-1]
          hidden_shape = (*input_shape, -1, attention.head_dim)
          query_states = attention.q_norm(attention.q_proj(hidden_states).view(hidden_shape)).transpose(1, 2)
          key_states = attention.k_norm(attention.k_proj(hidden_states).view(hidden_shape)).transpose(1, 2)
          value_states = attention.v_proj(hidden_states).view(hidden_shape).transpose(1, 2)

          cos, sin = position_embeddings
          query_states, key_states = apply_multimodal_rotary_pos_emb(
            query_states,
            key_states,
            cos,
            sin,
            attention.rope_scaling["mrope_section"],
            attention.rope_scaling["interleaved"],
          )

          past_key = getattr(self, f"past_key_{layer_index}")
          past_value = getattr(self, f"past_value_{layer_index}")
          key_states = torch.cat((past_key, key_states), dim=2)
          value_states = torch.cat((past_value, value_states), dim=2)

          attention_interface = eager_attention_forward
          if attention.config._attn_implementation != "eager":
            attention_interface = ALL_ATTENTION_FUNCTIONS[attention.config._attn_implementation]
          attn_output, _ = attention_interface(
            attention,
            query_states,
            key_states,
            value_states,
            causal_mask,
            dropout=0.0,
            scaling=attention.scaling,
            sliding_window=attention.sliding_window,
          )
          attn_output = attn_output.transpose(1, 2).contiguous()
          attn_output = attn_output.reshape(*input_shape, -1).contiguous()
          attn_output = attention.o_proj(attn_output)
          hidden_states = residual + attn_output

          residual = hidden_states
          hidden_states = decoder_layer.post_attention_layernorm(hidden_states)
          hidden_states = decoder_layer.mlp(hidden_states)
          hidden_states = residual + hidden_states

        hidden_states = self.norm(hidden_states)
        _ = text_position_ids
        return self.codec_head(hidden_states)[:, -1, :]

    inputs_embeds = captured["inputs_embeds"].to(args.device)
    position_ids = captured["position_ids"].to(args.device)
    reference_logits = captured["reference_logits"].to(args.device)
    boundary = FrozenCacheMainTalkerDecodeBoundary(
      model.talker.model,
      model.talker.codec_head,
      captured["cache_pairs"],
    ).eval()

    with torch.inference_mode():
      replay_logits = boundary(inputs_embeds, position_ids)
    replay_max_abs_diff = float((reference_logits.float() - replay_logits.float()).abs().max().item())

    export_attempts = []
    exported = None
    if replay_max_abs_diff <= args.parity_tolerance:
      for strict in [True, False]:
        try:
          exported = torch.export.export(boundary, args=(inputs_embeds, position_ids), strict=strict)
          export_attempts.append({"strict": strict, "status": "exported"})
          break
        except Exception as error:
          export_attempts.append(
            {
              "strict": strict,
              "status": "failed",
              "error": {
                "type": type(error).__name__,
                "message": str(error),
                "traceback": traceback.format_exc().splitlines()[-12:],
              },
            }
          )

    if exported is None:
      report.update(
        {
          "status": "torch_export_skipped_or_failed",
          "resolved_model_snapshot": sanitize_local_paths(snapshot_path),
          "captured_input": tensor_summary(inputs_embeds, include_hash=True),
          "captured_position_ids": tensor_summary(position_ids, include_hash=True),
          "captured_cache": {
            "layer_count": len(captured["cache_pairs"]),
            "first_key": tensor_summary(captured["cache_pairs"][0][0], include_hash=False),
            "first_value": tensor_summary(captured["cache_pairs"][0][1], include_hash=False),
          },
          "reference_logits": tensor_summary(reference_logits, include_hash=True, topk=8),
          "frozen_cache_replay": {
            "max_abs_diff": replay_max_abs_diff,
            "matches_reference_within_tolerance": replay_max_abs_diff <= args.parity_tolerance,
            "logits": tensor_summary(replay_logits, include_hash=True, topk=8),
          },
          "torch_export_attempts": export_attempts,
          "next_action": (
            "Fix frozen-cache replay parity before judging CoreAI conversion for the main talker."
          ),
        }
      )
      return report

    decomposed = exported.run_decompositions(coreai_torch.get_decomp_table())
    exported_module = decomposed.module()
    with torch.inference_mode():
      exported_logits = exported_module(inputs_embeds, position_ids)
    exported_max_abs_diff = float((reference_logits.float() - exported_logits.float()).abs().max().item())
    targets = exported_graph_targets(decomposed)
    suspicious_nodes = exported_graph_suspicious_nodes(decomposed)

    try:
      converter = TorchConverter().add_exported_program(decomposed)
      coreai_program = converter.to_coreai()
      if args.optimize_coreai_program:
        coreai_program.optimize()
      report.update(
        {
          "status": "converted_real_main_talker_frozen_cache_to_coreai_ir",
          "coreai_program": coreai_program_summary(coreai_program),
          "next_action": (
            "Replace frozen cache buffers with mutable Core AI state or explicit cache inputs, "
            "then profile Core AI runtime placement and latency."
          ),
        }
      )
    except Exception as error:
      report.update(
        {
          "status": "coreai_conversion_failed_after_main_talker_torch_export",
          "coreai_conversion_error": {
            "type": type(error).__name__,
            "message": str(error),
            "traceback": traceback.format_exc().splitlines()[-12:],
          },
          "next_action": (
            "Use the main-talker torch.export graph and failure point to decide whether CoreAI "
            "needs custom lowering or whether ExecuTorch/Core ML should be compared first."
          ),
        }
      )

    report.update(
      {
        "resolved_model_snapshot": sanitize_local_paths(snapshot_path),
        "captured_input": tensor_summary(inputs_embeds, include_hash=True),
        "captured_position_ids": tensor_summary(position_ids, include_hash=True),
        "captured_cache": {
          "layer_count": len(captured["cache_pairs"]),
          "first_key": tensor_summary(captured["cache_pairs"][0][0], include_hash=False),
          "first_value": tensor_summary(captured["cache_pairs"][0][1], include_hash=False),
        },
        "mask_policy": {
          "mode": "omitted_zero_decode_mask",
          "reason": (
            "The captured first decode step has a one-token query and all past tokens visible, "
            "so a zero additive attention mask is equivalent to no mask for parity."
          ),
        },
        "reference_logits": tensor_summary(reference_logits, include_hash=True, topk=8),
        "frozen_cache_replay": {
          "max_abs_diff": replay_max_abs_diff,
          "matches_reference_within_tolerance": replay_max_abs_diff <= args.parity_tolerance,
          "logits": tensor_summary(replay_logits, include_hash=True, topk=8),
        },
        "torch_export_attempts": export_attempts,
        "exported_program_parity": {
          "max_abs_diff": exported_max_abs_diff,
          "matches_reference_within_tolerance": exported_max_abs_diff <= args.parity_tolerance,
          "exported_logits": tensor_summary(exported_logits, include_hash=True, topk=8),
        },
        "exported_graph": {
          "call_targets": targets,
          "suspicious_nodes": suspicious_nodes,
          "call_target_count": len(targets),
          "contains_matmul": any("matmul" in target for target in targets),
          "contains_softmax": any("softmax" in target for target in targets),
          "contains_rsqrt": any("rsqrt" in target for target in targets),
          "contains_cos": any("cos" in target for target in targets),
          "contains_sin": any("sin" in target for target in targets),
          "contains_cat": any("cat" in target for target in targets),
        },
        "dependency_versions": package_versions(dependencies["packages"]),
      }
    )
  except Exception as error:
    report.update(
      {
        "status": "real_main_talker_export_smoke_failed",
        "error": {
          "type": type(error).__name__,
          "message": str(error),
          "traceback": traceback.format_exc().splitlines()[-16:],
        },
        "next_action": "Fix the real main-talker export blocker before claiming CoreAI can handle Qwen decode.",
      }
    )
  return report


def write_report(path: Path, report: dict[str, Any]) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  sanitized = sanitize_local_paths(report)
  path.write_text(json.dumps(sanitized, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument(
    "--mode",
    choices=[
      "preflight",
      "export-smoke",
      "real-boundary-plan",
      "real-boundary-capture",
      "real-code-predictor-export-smoke",
      "real-main-talker-export-smoke",
      "coreai-compression-preflight",
    ],
    default="preflight",
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--created-at-utc")
  parser.add_argument("--report", type=Path, default=Path(DEFAULT_REPORT))
  parser.add_argument("--developer-dir", type=Path)
  parser.add_argument("--allow-runtime-imports", action="store_true")
  parser.add_argument("--allow-model-load", action="store_true")
  parser.add_argument("--qwen-source", type=Path, default=Path(DEFAULT_QWEN_SOURCE))
  parser.add_argument("--text-token-fixture", type=Path, default=Path(DEFAULT_TEXT_TOKEN_FIXTURE))
  parser.add_argument("--prompt-kind", default="target")
  parser.add_argument("--language", default="english")
  parser.add_argument("--device", default="cpu")
  parser.add_argument("--torch-dtype", default="bfloat16", choices=["float16", "bfloat16", "float32"])
  parser.add_argument("--max-new-tokens", type=int, default=3)
  parser.add_argument("--do-sample", action=argparse.BooleanOptionalAction, default=False)
  parser.add_argument("--top-k", type=int, default=50)
  parser.add_argument("--top-p", type=float, default=1.0)
  parser.add_argument("--temperature", type=float, default=0.9)
  parser.add_argument("--repetition-penalty", type=float, default=1.05)
  parser.add_argument("--subtalker-dosample", action=argparse.BooleanOptionalAction, default=False)
  parser.add_argument("--subtalker-top-k", type=int, default=50)
  parser.add_argument("--subtalker-top-p", type=float, default=1.0)
  parser.add_argument("--subtalker-temperature", type=float, default=0.9)
  parser.add_argument("--parity-tolerance", type=float, default=1e-4)
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
  elif args.mode == "real-boundary-plan":
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_REAL_BOUNDARY_REPORT)
    report = build_real_boundary_plan(args)
  elif args.mode == "real-boundary-capture":
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_REAL_CAPTURE_REPORT)
    report = run_real_boundary_capture(args)
  elif args.mode == "real-code-predictor-export-smoke":
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_REAL_CODE_PREDICTOR_EXPORT_REPORT)
    report = run_real_code_predictor_export_smoke(args)
  elif args.mode == "real-main-talker-export-smoke":
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_REAL_MAIN_TALKER_EXPORT_REPORT)
    report = run_real_main_talker_export_smoke(args)
  elif args.mode == "coreai-compression-preflight":
    if args.report == Path(DEFAULT_REPORT):
      args.report = Path(DEFAULT_COREAI_COMPRESSION_PREFLIGHT_REPORT)
    report = build_coreai_compression_preflight(args)
  else:
    report = build_report(args)
  write_report(resolve_package_path(args.report), report)
  if args.print_json:
    print(json.dumps(report, indent=2, sort_keys=False))


if __name__ == "__main__":
  main()
