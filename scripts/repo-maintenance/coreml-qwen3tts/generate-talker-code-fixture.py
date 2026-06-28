#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "huggingface-hub>=0.36.0",
#   "numpy>=2.0.0",
#   "soundfile>=0.13.0",
# ]
# ///
"""Capture Qwen3-TTS talker-generated decoder codes for Core ML probing."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_OUTPUT_DIR = ".local/coreml-qwen3tts/talker-code-fixtures"
DEFAULT_PROMPTS = [
  "A calm calibration sentence with steady volume and clear articulation.",
  "The quick brown fox jumps over the lazy dog while the room stays quiet.",
  "Please keep this longer spoken passage natural, even, and consistent from beginning to end.",
]
CODE_STEP_SAMPLES = 1_920


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


def repo_file_inventory(model_id: str, revision: str | None) -> dict[str, Any]:
  try:
    model_info = HfApi().model_info(model_id, revision=revision, files_metadata=True)
  except Exception as error:
    raise RuntimeError(
      f"Unable to inspect Hugging Face files for model '{model_id}'. "
      "Confirm the model id, revision, network access, and Hugging Face availability."
    ) from error

  files = [
    {
      "path": sibling.rfilename,
      "size_bytes": sibling.size,
    }
    for sibling in model_info.siblings
  ]
  files.sort(key=lambda item: item["size_bytes"] or 0, reverse=True)
  return {
    "resolved_revision": model_info.sha,
    "file_count": len(files),
    "total_size_bytes": sum(item["size_bytes"] or 0 for item in files),
    "files": files,
  }


def qwen_source_from_args(args: argparse.Namespace) -> Path:
  source = args.qwen_source or os.environ.get("QWEN3_TTS_SOURCE")
  if not source:
    raise RuntimeError(
      "Talker-code fixture generation needs Qwen3-TTS source code. "
      "Pass --qwen-source /path/to/Qwen3-TTS or set QWEN3_TTS_SOURCE."
    )

  source_path = Path(source).expanduser().resolve()
  model_file = source_path / "qwen_tts" / "inference" / "qwen3_tts_model.py"
  if not model_file.is_file():
    raise RuntimeError(
      f"The Qwen3-TTS source path '{source_path}' does not contain qwen_tts/inference/qwen3_tts_model.py."
    )
  return source_path


def ensure_runtime_allowed(args: argparse.Namespace, inventory: dict[str, Any]) -> None:
  total_mb = (inventory["total_size_bytes"] or 0) / 1_000_000
  if not args.allow_model_download:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because it may download about {total_mb:.1f} MB. "
      "Rerun with --allow-model-download when you intentionally want real Qwen talker generation."
    )
  if total_mb > args.max_model_download_mb:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because its file inventory is about {total_mb:.1f} MB, "
      f"which is above --max-model-download-mb {args.max_model_download_mb:.1f}."
    )


def prompt_items(args: argparse.Namespace) -> list[dict[str, Any]]:
  if args.prompts_json:
    path = resolve_package_path(args.prompts_json)
    try:
      payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as error:
      raise RuntimeError(f"Unable to read prompts JSON at '{path}'.") from error
    prompts = payload.get("prompts", payload)
    if not isinstance(prompts, list):
      raise RuntimeError("Prompts JSON must be either a list or an object with a 'prompts' list.")
    items = []
    for index, item in enumerate(prompts):
      if isinstance(item, str):
        items.append({"id": f"prompt-{index:03d}", "text": item})
      elif isinstance(item, dict) and isinstance(item.get("text"), str):
        items.append({"id": item.get("id", f"prompt-{index:03d}"), **item})
      else:
        raise RuntimeError(f"Prompt item at index {index} must be a string or object with text.")
    return items

  return [
    {"id": f"prompt-{index:03d}", "text": text}
    for index, text in enumerate(DEFAULT_PROMPTS[: args.sample_count])
  ]


def bucket_for_code_steps(code_steps: int) -> int:
  return max(8, int(((code_steps + 7) // 8) * 8))


def code_stats(codes: Any) -> dict[str, Any]:
  import numpy as np

  codes_array = np.asarray(codes, dtype=np.int64)
  return {
    "audio_codes_shape": list(codes_array.shape),
    "audio_codes_dtype": str(codes_array.dtype),
    "audio_codes_min": int(np.min(codes_array)) if codes_array.size else None,
    "audio_codes_max": int(np.max(codes_array)) if codes_array.size else None,
    "audio_codes_unique_count": int(np.unique(codes_array).shape[0]) if codes_array.size else 0,
    "audio_codes": codes_array.tolist(),
    "audio_codes_prefix": codes_array[: min(8, codes_array.shape[0]), : min(8, codes_array.shape[1])].tolist(),
    "audio_codes_first_quantizer_prefix": codes_array[: min(24, codes_array.shape[0]), 0].tolist(),
  }


def aggregate_samples(samples: list[dict[str, Any]]) -> dict[str, Any]:
  code_steps = [sample["encoded"]["audio_codes_shape"][0] for sample in samples]
  return {
    "sample_count": len(samples),
    "total_code_steps": sum(code_steps),
    "min_code_steps": min(code_steps) if code_steps else None,
    "max_code_steps": max(code_steps) if code_steps else None,
    "quantizer_count": samples[0]["encoded"]["audio_codes_shape"][1] if samples else None,
    "suggested_decoder_buckets": sorted({bucket_for_code_steps(step) for step in code_steps}),
  }


def compact_sample(sample: dict[str, Any]) -> dict[str, Any]:
  encoded = sample["encoded"]
  return {
    "id": sample["id"],
    "text": sample["text"],
    "generation_parameters": sample["generation_parameters"],
    "encoded": {
      "audio_codes_shape": encoded["audio_codes_shape"],
      "audio_codes_dtype": encoded["audio_codes_dtype"],
      "audio_codes_min": encoded["audio_codes_min"],
      "audio_codes_max": encoded["audio_codes_max"],
      "audio_codes_unique_count": encoded["audio_codes_unique_count"],
      "audio_codes_prefix": encoded["audio_codes_prefix"],
      "audio_codes_first_quantizer_prefix": encoded["audio_codes_first_quantizer_prefix"],
    },
    "bucket_assignment": sample["bucket_assignment"],
    "generated_audio": sample["generated_audio"],
  }


def compact_report(report: dict[str, Any]) -> dict[str, Any]:
  return {
    **report,
    "mode": f"{report['mode']}_summary",
    "purpose": (
      "Compact summary of Qwen3-TTS talker-generated audio-code fixtures. "
      "Full audio_codes arrays remain in the local artifact named by full_fixture_path."
    ),
    "full_fixture_path": report.get("artifact_paths", {}).get("full_fixture_path"),
    "samples": [compact_sample(sample) for sample in report.get("samples", [])],
  }


def reset_output_dir(output_dir: Path, replace_existing: bool) -> None:
  if output_dir.exists():
    if not replace_existing:
      raise RuntimeError(
        f"Talker-code output directory '{relative_package_path(output_dir)}' already exists. "
        "Pass --replace-existing to clear stale artifacts before writing new ones."
      )
    shutil.rmtree(output_dir)
  output_dir.mkdir(parents=True, exist_ok=True)


def write_wav(path: Path, audio: Any, sample_rate: int) -> None:
  import numpy as np
  import soundfile as sf

  sf.write(path, np.clip(np.asarray(audio, dtype=np.float32), -1.0, 1.0), sample_rate)


def build_preflight_report(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  prompts: list[dict[str, Any]],
) -> dict[str, Any]:
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "preflight",
    "purpose": (
      "Plan Qwen3-TTS talker-code capture for decoder calibration and evaluation. "
      "Runtime mode monkeypatches speech_tokenizer.decode, records exact audio_codes, "
      "then calls the original decode so generated audio remains the normal output."
    ),
    "source": {
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
    },
    "model_file_inventory": inventory,
    "generation_defaults": generation_parameters(args),
    "prompt_plan": {
      "requested_sample_count": args.sample_count,
      "prompt_count": len(prompts),
      "prompts": prompts,
    },
    "calibration_scope": calibration_scope(),
    "next_command": (
      "scripts/repo-maintenance/coreml-qwen3tts/run-with-live-service-headroom.sh "
      "-- "
      "uv run --python 3.12 "
      "--with 'torch==2.7.0' --with 'transformers==4.57.3' "
      "--with 'accelerate==1.12.0' "
      "--with 'numpy>=2.0.0' --with 'soundfile>=0.13.0' "
      "--with 'librosa>=0.11.0' --with 'sox>=1.5.0' "
      "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' --with 'torchaudio==2.7.0' "
      "scripts/repo-maintenance/coreml-qwen3tts/generate-talker-code-fixture.py "
      "--no-preflight-only --allow-model-download --replace-existing "
      "--qwen-source .local/coreml-qwen3tts/Qwen3-TTS-source "
      "--output .local/coreml-qwen3tts/talker-code-fixture-qwen3-12hz.json "
      "--summary-output docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-qwen3-12hz-summary.json"
    ),
  }


def generation_parameters(args: argparse.Namespace) -> dict[str, Any]:
  return {
    "language": args.language,
    "voice": args.voice,
    "seed": args.seed,
    "max_new_tokens": args.max_new_tokens,
    "do_sample": args.do_sample,
    "top_k": args.top_k,
    "top_p": args.top_p,
    "temperature": args.temperature,
    "repetition_penalty": args.repetition_penalty,
    "subtalker_dosample": args.subtalker_dosample,
    "subtalker_top_k": args.subtalker_top_k,
    "subtalker_top_p": args.subtalker_top_p,
    "subtalker_temperature": args.subtalker_temperature,
  }


def calibration_scope() -> dict[str, Any]:
  return {
    "current_graph": "12 Hz speech-tokenizer decoder only",
    "current_input": "audio_codes captured from Qwen3-TTS talker generation immediately before speech_tokenizer.decode",
    "code_step_samples": CODE_STEP_SAMPLES,
    "output_audio_role": "evaluation_only_for_coreml_activation_calibration",
  }


def build_runtime_report(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  prompts: list[dict[str, Any]],
) -> dict[str, Any]:
  import numpy as np
  import torch

  qwen_source = qwen_source_from_args(args)
  ensure_runtime_allowed(args, inventory)
  output_dir = resolve_package_path(args.output_dir)
  reset_output_dir(output_dir, args.replace_existing)

  sys.path.insert(0, str(qwen_source))
  try:
    from qwen_tts import Qwen3TTSModel
  except Exception as error:
    raise RuntimeError(
      f"Unable to import Qwen3TTSModel from '{qwen_source}'. "
      f"Underlying import error: {error!r}"
    ) from error

  if args.seed is not None:
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

  model = Qwen3TTSModel.from_pretrained(
    args.model_id,
    dtype=getattr(torch, args.torch_dtype),
    device_map=args.device,
  )

  captured_decode_inputs: list[Any] = []
  original_decode = model.model.speech_tokenizer.decode

  def recording_decode(encoded: Any, *decode_args: Any, **decode_kwargs: Any) -> Any:
    captured_decode_inputs.append(encoded)
    return original_decode(encoded, *decode_args, **decode_kwargs)

  model.model.speech_tokenizer.decode = recording_decode

  samples = []
  for index, prompt in enumerate(prompts):
    captured_decode_inputs.clear()
    generation_kwargs = {
      "text": prompt["text"],
      "language": args.language,
      "max_new_tokens": args.max_new_tokens,
      "do_sample": args.do_sample,
      "top_k": args.top_k,
      "top_p": args.top_p,
      "temperature": args.temperature,
      "repetition_penalty": args.repetition_penalty,
      "subtalker_dosample": args.subtalker_dosample,
      "subtalker_top_k": args.subtalker_top_k,
      "subtalker_top_p": args.subtalker_top_p,
      "subtalker_temperature": args.subtalker_temperature,
    }
    if model.model.tts_model_type == "custom_voice":
      wavs, sample_rate = model.generate_custom_voice(
        speaker=args.voice,
        **generation_kwargs,
      )
    elif model.model.tts_model_type == "voice_design":
      wavs, sample_rate = model.generate_voice_design(
        instruct=args.voice_design_instruction,
        **generation_kwargs,
      )
    else:
      raise RuntimeError(
        "Talker-code capture defaults to Qwen3 custom-voice or voice-design models so no reference audio "
        "is required. Base voice-clone capture should be added as a separate fixture mode with explicit "
        "ref_audio and ref_text inputs."
      )
    if not captured_decode_inputs:
      raise RuntimeError(f"Qwen generation for prompt '{prompt['id']}' did not call speech_tokenizer.decode.")
    encoded = captured_decode_inputs[-1]
    if not isinstance(encoded, list) or not encoded:
      raise RuntimeError(f"Captured decode input for prompt '{prompt['id']}' was not a non-empty list.")
    codes = encoded[0]["audio_codes"]
    if hasattr(codes, "detach"):
      codes = codes.detach().cpu().numpy()

    wav_path = output_dir / f"{index:03d}-{prompt['id']}.wav"
    write_wav(wav_path, wavs[0], sample_rate)
    code_steps = int(np.asarray(codes).shape[0])
    bucket = bucket_for_code_steps(code_steps)
    samples.append(
      {
        "id": prompt["id"],
        "text": prompt["text"],
        "generation_parameters": generation_parameters(args),
        "encoded": code_stats(codes),
        "bucket_assignment": {
          "assigned_bucket": bucket,
          "bucket_input_shape": [1, bucket, int(np.asarray(codes).shape[1])],
          "pad_value": -1,
          "padded_step_count": bucket - code_steps,
          "valid_output_sample_count": code_steps * CODE_STEP_SAMPLES,
          "padded_output_sample_count": bucket * CODE_STEP_SAMPLES,
        },
        "generated_audio": {
          "sample_rate": int(sample_rate),
          "sample_count": int(np.asarray(wavs[0]).shape[0]),
          "wav_path": relative_package_path(wav_path),
        },
      }
    )

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "runtime",
    "purpose": "Qwen3-TTS talker-generated audio-code fixture for decoder Core ML calibration and evaluation.",
    "source": {
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "qwen_source_path": relative_package_path(qwen_source),
    },
    "model_file_inventory": inventory,
    "calibration_scope": calibration_scope(),
    "aggregate": aggregate_samples(samples),
    "artifact_paths": {
      "full_fixture_path": relative_package_path(resolve_package_path(args.output)) if args.output else None,
      "output_dir": relative_package_path(output_dir),
    },
    "samples": samples,
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  prompts = prompt_items(args)
  inventory = repo_file_inventory(args.model_id, args.revision)
  if args.preflight_only:
    return build_preflight_report(args, inventory, prompts)
  return build_runtime_report(args, inventory, prompts)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Capture Qwen3-TTS talker-generated audio_codes before speech_tokenizer.decode."
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--revision", default=None)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--qwen-source", default=None)
  parser.add_argument("--prompts-json", type=Path, default=None)
  parser.add_argument("--sample-count", type=int, default=len(DEFAULT_PROMPTS))
  parser.add_argument("--language", default="English")
  parser.add_argument("--voice", default="Ryan")
  parser.add_argument(
    "--voice-design-instruction",
    default="A clear, steady English-speaking voice with even volume.",
  )
  parser.add_argument("--device", default="cpu")
  parser.add_argument("--torch-dtype", default="bfloat16", choices=["float16", "bfloat16", "float32"])
  parser.add_argument("--seed", type=int, default=20260531)
  parser.add_argument("--max-new-tokens", type=int, default=512)
  parser.add_argument("--do-sample", action=argparse.BooleanOptionalAction, default=True)
  parser.add_argument("--top-k", type=int, default=50)
  parser.add_argument("--top-p", type=float, default=1.0)
  parser.add_argument("--temperature", type=float, default=0.9)
  parser.add_argument("--repetition-penalty", type=float, default=1.05)
  parser.add_argument("--subtalker-dosample", action=argparse.BooleanOptionalAction, default=True)
  parser.add_argument("--subtalker-top-k", type=int, default=50)
  parser.add_argument("--subtalker-top-p", type=float, default=1.0)
  parser.add_argument("--subtalker-temperature", type=float, default=0.9)
  parser.add_argument("--preflight-only", action=argparse.BooleanOptionalAction, default=True)
  parser.add_argument("--allow-model-download", action="store_true")
  parser.add_argument("--max-model-download-mb", type=float, default=12_000.0)
  parser.add_argument("--replace-existing", action="store_true")
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--output-dir", type=Path, default=Path(DEFAULT_OUTPUT_DIR))
  parser.add_argument("--output", type=Path, default=None)
  parser.add_argument("--summary-output", type=Path, default=None)
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
    report = build_report(args)
    write_report(report, args.output)
    if args.summary_output:
      write_report(compact_report(report), args.summary_output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
