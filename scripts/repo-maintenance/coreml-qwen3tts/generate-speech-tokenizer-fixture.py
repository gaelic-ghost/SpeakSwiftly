#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "huggingface-hub>=0.36.0",
# ]
# ///
"""Generate opt-in Qwen3-TTS 12 Hz speech-tokenizer encode/decode fixtures."""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_SAMPLE_RATE = 24_000
DEFAULT_DURATION_SECONDS = 0.64
DEFAULT_FREQUENCY_HZ = 220.0


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


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


def synthetic_waveform(
  sample_rate: int,
  duration_seconds: float,
  frequency_hz: float,
):
  import numpy as np

  sample_count = int(round(sample_rate * duration_seconds))
  if sample_count <= 0:
    raise ValueError("Synthetic speech-tokenizer fixture audio must contain at least one sample.")

  timeline = np.arange(sample_count, dtype=np.float32) / np.float32(sample_rate)
  carrier = np.sin(2.0 * np.pi * np.float32(frequency_hz) * timeline)
  ramp_length = max(1, min(sample_count // 8, sample_rate // 100))
  envelope = np.ones(sample_count, dtype=np.float32)
  ramp = np.linspace(0.0, 1.0, ramp_length, dtype=np.float32)
  envelope[:ramp_length] = ramp
  envelope[-ramp_length:] = ramp[::-1]
  return (0.05 * carrier * envelope).astype(np.float32)


def qwen_source_from_args(args: argparse.Namespace) -> Path:
  source = args.qwen_source or os.environ.get("QWEN3_TTS_SOURCE")
  if not source:
    raise RuntimeError(
      "The speech-tokenizer fixture generator needs Qwen3-TTS source code. "
      "Pass --qwen-source /path/to/Qwen3-TTS or set QWEN3_TTS_SOURCE."
    )

  source_path = Path(source).expanduser().resolve()
  tokenizer_file = source_path / "qwen_tts" / "inference" / "qwen3_tts_tokenizer.py"
  if not tokenizer_file.is_file():
    raise RuntimeError(
      f"The Qwen3-TTS source path '{source_path}' does not contain qwen_tts/inference/qwen3_tts_tokenizer.py."
    )

  return source_path


def ensure_model_download_allowed(args: argparse.Namespace, inventory: dict[str, Any]) -> None:
  total_mb = (inventory["total_size_bytes"] or 0) / 1_000_000
  if not args.allow_model_download:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because it may download about {total_mb:.1f} MB. "
      "Rerun with --allow-model-download when you intentionally want the real encode/decode probe."
    )

  if total_mb > args.max_download_mb:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because its file inventory is about {total_mb:.1f} MB, "
      f"which is above --max-download-mb {args.max_download_mb:.1f}."
    )


def build_preflight_report(args: argparse.Namespace, inventory: dict[str, Any]) -> dict[str, Any]:
  sample_count = int(round(args.sample_rate * args.duration_seconds))
  expected_code_steps = int(math.ceil(sample_count / 1_920))

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "preflight",
    "source": {
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
    },
    "model_file_inventory": inventory,
    "synthetic_audio": {
      "sample_rate": args.sample_rate,
      "duration_seconds": args.duration_seconds,
      "frequency_hz": args.frequency_hz,
      "sample_count": sample_count,
      "expected_code_steps_at_1920_samples": expected_code_steps,
    },
    "next_command": (
      "uv run --with 'numpy>=2.0.0' --with 'torch>=2.6.0' --with 'transformers==4.57.3' "
      "--with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' --with 'sox>=1.5.0' "
      "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' --with 'torchaudio>=2.6.0' "
      "scripts/repo-maintenance/coreml-qwen3tts/generate-speech-tokenizer-fixture.py "
      "--no-preflight-only --qwen-source /path/to/Qwen3-TTS --allow-model-download "
      "--output .local/coreml-qwen3tts/qwen3tts-speech-tokenizer-fixture.json"
    ),
  }


def build_runtime_fixture(args: argparse.Namespace, inventory: dict[str, Any]) -> dict[str, Any]:
  try:
    import numpy as np
  except Exception as error:
    raise RuntimeError(
      "Runtime speech-tokenizer fixture generation needs numpy. Rerun through uv with "
      "`--with 'numpy>=2.0.0' --with 'torch>=2.6.0' --with 'transformers==4.57.3' "
      "--with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' --with 'sox>=1.5.0' "
      "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' --with 'torchaudio>=2.6.0'`."
    ) from error

  qwen_source = qwen_source_from_args(args)
  ensure_model_download_allowed(args, inventory)

  sys.path.insert(0, str(qwen_source))
  try:
    from qwen_tts import Qwen3TTSTokenizer
  except Exception as error:
    raise RuntimeError(
      f"Unable to import Qwen3TTSTokenizer from '{qwen_source}'. "
      "Confirm the upstream checkout is intact and this script's Python dependencies installed. "
      f"Underlying import error: {error!r}"
    ) from error

  waveform = synthetic_waveform(args.sample_rate, args.duration_seconds, args.frequency_hz)
  tokenizer = Qwen3TTSTokenizer.from_pretrained(args.model_id)

  encoded = tokenizer.encode(waveform, sr=args.sample_rate)
  decoded_wavs, decoded_sample_rate = tokenizer.decode(encoded)

  codes = encoded.audio_codes[0].detach().cpu().numpy()
  decoded = decoded_wavs[0].astype(np.float32)

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "runtime",
    "source": {
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "qwen_source_commit": args.upstream_commit,
    },
    "model_file_inventory": inventory,
    "synthetic_audio": {
      "sample_rate": args.sample_rate,
      "duration_seconds": args.duration_seconds,
      "frequency_hz": args.frequency_hz,
      "sample_count": int(waveform.shape[0]),
      "min": float(waveform.min()),
      "max": float(waveform.max()),
      "mean": float(waveform.mean()),
      "rms": float(np.sqrt(np.mean(np.square(waveform)))),
    },
    "encoded": {
      "audio_codes_shape": list(codes.shape),
      "audio_codes_dtype": str(codes.dtype),
      "audio_codes": codes.astype(int).tolist(),
      "audio_codes_prefix": codes[: min(8, codes.shape[0]), : min(8, codes.shape[1])].astype(int).tolist(),
      "audio_codes_first_quantizer_prefix": codes[: min(24, codes.shape[0]), 0].astype(int).tolist(),
    },
    "decoded": {
      "sample_rate": int(decoded_sample_rate),
      "sample_count": int(decoded.shape[0]),
      "duration_seconds": float(decoded.shape[0] / decoded_sample_rate),
      "min": float(decoded.min()),
      "max": float(decoded.max()),
      "mean": float(decoded.mean()),
      "rms": float(np.sqrt(np.mean(np.square(decoded)))),
    },
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  inventory = repo_file_inventory(args.model_id, args.revision)
  if args.preflight_only:
    return build_preflight_report(args, inventory)

  return build_runtime_fixture(args, inventory)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Generate a small 12 Hz speech-tokenizer encode/decode fixture. Default "
      "preflight mode avoids downloading model weights."
    )
  )
  parser.add_argument(
    "--model-id",
    default=DEFAULT_MODEL_ID,
    help=f"Hugging Face 12 Hz tokenizer model id. Default: {DEFAULT_MODEL_ID}",
  )
  parser.add_argument("--revision", default=None, help="Optional Hugging Face revision to inspect or load.")
  parser.add_argument(
    "--upstream-commit",
    default=DEFAULT_UPSTREAM_COMMIT,
    help="Qwen3-TTS source commit used when matching speech-tokenizer behavior.",
  )
  parser.add_argument(
    "--qwen-source",
    default=None,
    help="Path to an upstream Qwen3-TTS source checkout. Defaults to QWEN3_TTS_SOURCE.",
  )
  parser.add_argument(
    "--preflight-only",
    action=argparse.BooleanOptionalAction,
    default=True,
    help="Only inspect model file metadata and planned synthetic fixture shape. Default: true.",
  )
  parser.add_argument(
    "--allow-model-download",
    action="store_true",
    help="Required for runtime mode because the tokenizer weight file is large.",
  )
  parser.add_argument(
    "--max-download-mb",
    type=float,
    default=1_024.0,
    help="Maximum Hugging Face file inventory size allowed for runtime mode. Default: 1024.",
  )
  parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
  parser.add_argument("--duration-seconds", type=float, default=DEFAULT_DURATION_SECONDS)
  parser.add_argument("--frequency-hz", type=float, default=DEFAULT_FREQUENCY_HZ)
  parser.add_argument(
    "--created-at-utc",
    default=None,
    help="Optional ISO-8601 UTC timestamp for stable checked-in fixtures.",
  )
  parser.add_argument(
    "--output",
    type=Path,
    default=None,
    help="Optional output JSON path. Defaults to stdout.",
  )
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
