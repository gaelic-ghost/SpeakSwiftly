#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "huggingface-hub>=0.36.0",
#   "numpy>=2.0.0",
#   "torch==2.7.0",
# ]
# ///
"""Prototype supervised Qwen3-TTS decoder alignment before Core ML conversion."""

from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_CALIBRATION_FIXTURE_PATH = "docs/maintainers/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json"
DEFAULT_OUTPUT_DIR = ".local/coreml-qwen3tts/decoder-alignment"


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


def repo_file_inventory(model_id: str, revision: str | None) -> dict[str, Any]:
  try:
    model_info = HfApi().model_info(model_id, revision=revision, files_metadata=True)
  except Exception as error:
    raise RuntimeError(
      f"Unable to inspect Hugging Face files for model '{model_id}'. "
      "Confirm the model id, revision, network access, and Hugging Face availability."
    ) from error
  files = [
    {"path": sibling.rfilename, "size_bytes": sibling.size}
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
      "Decoder alignment needs Qwen3-TTS source code. "
      "Pass --qwen-source /path/to/Qwen3-TTS or set QWEN3_TTS_SOURCE."
    )
  source_path = Path(source).expanduser().resolve()
  tokenizer_file = source_path / "qwen_tts" / "inference" / "qwen3_tts_tokenizer.py"
  if not tokenizer_file.is_file():
    raise RuntimeError(
      f"The Qwen3-TTS source path '{source_path}' does not contain qwen_tts/inference/qwen3_tts_tokenizer.py."
    )
  return source_path


def ensure_runtime_allowed(args: argparse.Namespace, inventory: dict[str, Any]) -> None:
  total_mb = (inventory["total_size_bytes"] or 0) / 1_000_000
  if not args.allow_model_download:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because it may download about {total_mb:.1f} MB. "
      "Rerun with --allow-model-download when intentionally training the decoder alignment probe."
    )
  if total_mb > args.max_model_download_mb:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because its file inventory is about {total_mb:.1f} MB, "
      f"which is above --max-model-download-mb {args.max_model_download_mb:.1f}."
    )


def reset_output_dir(output_dir: Path, replace_existing: bool) -> None:
  if output_dir.exists():
    if not replace_existing:
      raise RuntimeError(
        f"Decoder alignment output directory '{relative_package_path(output_dir)}' already exists. "
        "Pass --replace-existing to clear stale artifacts before writing new ones."
      )
    shutil.rmtree(output_dir)
  output_dir.mkdir(parents=True, exist_ok=True)


def fixture_samples(args: argparse.Namespace) -> list[dict[str, Any]]:
  fixture = load_json(resolve_package_path(args.calibration_fixture))
  samples = fixture.get("samples", [])
  if args.max_samples is not None:
    samples = samples[: args.max_samples]
  return samples


def build_preflight_report(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  samples: list[dict[str, Any]],
) -> dict[str, Any]:
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "preflight",
    "purpose": (
      "Plan decoder-only supervised alignment before Core ML conversion. "
      "This is separate from Core ML activation calibration and is the only lane here "
      "that uses output audio as a training target."
    ),
    "source": {
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "calibration_fixture_path": str(args.calibration_fixture),
    },
    "model_file_inventory": inventory,
    "training_plan": {
      "teacher": "frozen upstream PyTorch 12 Hz speech-tokenizer decoder",
      "student": "deepcopy of decoder with only selected late decoder blocks trainable",
      "losses": ["waveform_l1", "multi_resolution_stft_l1"],
      "trainable_scope": args.trainable_scope,
      "epochs": args.epochs,
      "learning_rate": args.learning_rate,
      "max_samples": args.max_samples,
      "sample_count": len(samples),
    },
    "samples": [
      {
        "id": sample.get("id"),
        "audio_codes_shape": sample.get("encoded", {}).get("audio_codes_shape"),
        "audio_seconds": sample.get("audio", {}).get("duration_seconds"),
      }
      for sample in samples
    ],
    "next_command": (
      "scripts/repo-maintenance/coreml-qwen3tts/run-with-live-service-headroom.sh "
      "uv run --python 3.12 "
      "--with 'torch==2.7.0' --with 'transformers==4.57.3' "
      "--with 'numpy>=2.0.0' --with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' "
      "--with 'sox>=1.5.0' --with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' "
      "--with 'torchaudio==2.7.0' "
      "scripts/repo-maintenance/coreml-qwen3tts/probe-decoder-alignment-tuning.py "
      "--no-preflight-only --allow-model-download --replace-existing "
      "--qwen-source .local/coreml-qwen3tts/Qwen3-TTS-source"
    ),
  }


def sample_audio_codes(sample: dict[str, Any], torch: Any, device: str) -> Any:
  codes = torch.tensor(sample["encoded"]["audio_codes"], dtype=torch.long, device=device)
  return codes.transpose(0, 1).unsqueeze(0)


def set_trainable_scope(student: Any, scope: str) -> None:
  for parameter in student.parameters():
    parameter.requires_grad_(False)
  if scope == "decoder_tail":
    modules = list(student.decoder)[-2:]
  elif scope == "upsample_and_decoder":
    modules = list(student.upsample) + list(student.decoder)
  else:
    raise RuntimeError(f"Unsupported trainable scope '{scope}'.")
  for module in modules:
    for parameter in module.parameters():
      parameter.requires_grad_(True)


def multi_resolution_stft_loss(prediction: Any, target: Any, torch: Any) -> Any:
  losses = []
  for n_fft, hop_length in ((512, 128), (1024, 256), (2048, 512)):
    window = torch.hann_window(n_fft, device=prediction.device, dtype=prediction.dtype)
    pred_stft = torch.stft(
      prediction,
      n_fft=n_fft,
      hop_length=hop_length,
      win_length=n_fft,
      window=window,
      return_complex=True,
    ).abs()
    target_stft = torch.stft(
      target,
      n_fft=n_fft,
      hop_length=hop_length,
      win_length=n_fft,
      window=window,
      return_complex=True,
    ).abs()
    losses.append(torch.nn.functional.l1_loss(pred_stft, target_stft))
  return sum(losses) / len(losses)


def build_runtime_report(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  samples: list[dict[str, Any]],
) -> dict[str, Any]:
  import torch

  qwen_source = qwen_source_from_args(args)
  ensure_runtime_allowed(args, inventory)
  output_dir = resolve_package_path(args.output_dir)
  reset_output_dir(output_dir, args.replace_existing)

  sys.path.insert(0, str(qwen_source))
  try:
    from qwen_tts import Qwen3TTSTokenizer
  except Exception as error:
    raise RuntimeError(
      f"Unable to import Qwen3TTSTokenizer from '{qwen_source}'. "
      f"Underlying import error: {error!r}"
    ) from error

  tokenizer = Qwen3TTSTokenizer.from_pretrained(args.model_id, torch_dtype=getattr(torch, args.torch_dtype))
  teacher = tokenizer.model.decoder.to(args.device)
  teacher.eval()
  for parameter in teacher.parameters():
    parameter.requires_grad_(False)
  student = copy.deepcopy(teacher).to(args.device)
  set_trainable_scope(student, args.trainable_scope)
  student.train()

  optimizer = torch.optim.AdamW(
    [parameter for parameter in student.parameters() if parameter.requires_grad],
    lr=args.learning_rate,
  )

  history = []
  for epoch in range(args.epochs):
    for sample in samples:
      codes = sample_audio_codes(sample, torch, args.device)
      with torch.no_grad():
        teacher_audio = teacher(codes).squeeze(1)
      student_audio = student(codes).squeeze(1)
      waveform_loss = torch.nn.functional.l1_loss(student_audio, teacher_audio)
      stft_loss = multi_resolution_stft_loss(student_audio, teacher_audio, torch)
      loss = waveform_loss + args.stft_loss_weight * stft_loss
      optimizer.zero_grad()
      loss.backward()
      torch.nn.utils.clip_grad_norm_(student.parameters(), args.gradient_clip_norm)
      optimizer.step()
      history.append(
        {
          "epoch": epoch,
          "sample_id": sample.get("id"),
          "loss": float(loss.detach().cpu()),
          "waveform_l1": float(waveform_loss.detach().cpu()),
          "stft_l1": float(stft_loss.detach().cpu()),
        }
      )

  state_path = output_dir / "student-decoder-state.pt"
  torch.save(student.state_dict(), state_path)
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "runtime",
    "purpose": "Decoder-only supervised alignment artifact for later Core ML reconversion and W8A8 probing.",
    "source": {
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "calibration_fixture_path": str(args.calibration_fixture),
    },
    "training": {
      "trainable_scope": args.trainable_scope,
      "epochs": args.epochs,
      "learning_rate": args.learning_rate,
      "stft_loss_weight": args.stft_loss_weight,
      "history": history,
      "student_state_path": relative_package_path(state_path),
    },
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  samples = fixture_samples(args)
  inventory = repo_file_inventory(args.model_id, args.revision)
  if args.preflight_only:
    return build_preflight_report(args, inventory, samples)
  return build_runtime_report(args, inventory, samples)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Run a decoder-only supervised alignment probe before Core ML conversion."
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--revision", default=None)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--calibration-fixture", type=Path, default=Path(DEFAULT_CALIBRATION_FIXTURE_PATH))
  parser.add_argument("--qwen-source", default=None)
  parser.add_argument("--device", default="cpu")
  parser.add_argument("--torch-dtype", default="float32", choices=["float16", "bfloat16", "float32"])
  parser.add_argument("--trainable-scope", default="decoder_tail", choices=["decoder_tail", "upsample_and_decoder"])
  parser.add_argument("--epochs", type=int, default=1)
  parser.add_argument("--learning-rate", type=float, default=1e-6)
  parser.add_argument("--stft-loss-weight", type=float, default=0.1)
  parser.add_argument("--gradient-clip-norm", type=float, default=1.0)
  parser.add_argument("--max-samples", type=int, default=3)
  parser.add_argument("--preflight-only", action=argparse.BooleanOptionalAction, default=True)
  parser.add_argument("--allow-model-download", action="store_true")
  parser.add_argument("--max-model-download-mb", type=float, default=2_000.0)
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
