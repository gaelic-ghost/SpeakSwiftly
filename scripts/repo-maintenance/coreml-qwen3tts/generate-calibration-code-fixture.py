#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "huggingface-hub>=0.36.0",
#   "requests>=2.32.0",
# ]
# ///
"""Generate Qwen3-TTS speech-tokenizer code fixtures from open calibration audio."""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from huggingface_hub import HfApi


DATASETS_SERVER = "https://datasets-server.huggingface.co"
DEFAULT_DATASET = "mythicinfinity/libritts_r"
DEFAULT_CONFIG = "clean"
DEFAULT_SPLIT = "train.clean.100"
DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_SAMPLE_COUNT = 3
DEFAULT_OFFSET = 0
DEFAULT_EXPECTED_SAMPLE_RATE = 24_000
CODE_STEP_SAMPLES = 1_920


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


def get_dataset_rows(dataset: str, config: str, split: str, offset: int, length: int) -> list[dict[str, Any]]:
  response = requests.get(
    f"{DATASETS_SERVER}/rows",
    params={
      "dataset": dataset,
      "config": config,
      "split": split,
      "offset": offset,
      "length": length,
    },
    timeout=120,
  )
  if response.status_code != 200:
    raise RuntimeError(
      f"Dataset Viewer rows request failed for '{dataset}' config '{config}' split '{split}' "
      f"with HTTP {response.status_code}: {response.text[:500]}"
    )

  payload = response.json()
  return payload.get("rows", [])


def sanitized_sample_metadata(row: dict[str, Any]) -> dict[str, Any]:
  body = row.get("row", {})
  return {
    "row_idx": row.get("row_idx"),
    "id": body.get("id"),
    "speaker_id": body.get("speaker_id"),
    "chapter_id": body.get("chapter_id"),
    "text_normalized": body.get("text_normalized"),
    "text_original": body.get("text_original"),
  }


def audio_asset(row: dict[str, Any]) -> dict[str, Any]:
  assets = row.get("row", {}).get("audio", [])
  if not assets:
    raise RuntimeError(f"Dataset row {row.get('row_idx')} does not contain an audio asset.")

  asset = assets[0]
  src = asset.get("src")
  if not src:
    raise RuntimeError(f"Dataset row {row.get('row_idx')} does not expose a downloadable audio asset.")

  return asset


def qwen_source_from_args(args: argparse.Namespace) -> Path:
  source = args.qwen_source or os.environ.get("QWEN3_TTS_SOURCE")
  if not source:
    raise RuntimeError(
      "Calibration-code generation needs Qwen3-TTS source code. "
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
      "Rerun with --allow-model-download when you intentionally want real code generation."
    )

  if not args.allow_audio_download:
    raise RuntimeError(
      "Refusing to download dataset audio. Rerun with --allow-audio-download when you intentionally "
      "want transient Dataset Viewer audio assets fetched and encoded."
    )

  if total_mb > args.max_model_download_mb:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because its file inventory is about {total_mb:.1f} MB, "
      f"which is above --max-model-download-mb {args.max_model_download_mb:.1f}."
    )


def download_waveform(row: dict[str, Any], args: argparse.Namespace):
  try:
    import numpy as np
    import soundfile as sf
  except Exception as error:
    raise RuntimeError(
      "Runtime calibration-code generation needs numpy and soundfile. Rerun through uv with "
      "`--with 'numpy>=2.0.0' --with 'soundfile>=0.13.0'` plus the Qwen tokenizer runtime packages."
    ) from error

  asset = audio_asset(row)
  response = requests.get(asset["src"], timeout=120)
  if response.status_code != 200:
    raise RuntimeError(
      f"Audio download failed for row {row.get('row_idx')} with HTTP {response.status_code}: "
      f"{response.text[:500]}"
    )

  size_mb = len(response.content) / 1_000_000
  if size_mb > args.max_audio_mb:
    raise RuntimeError(
      f"Audio download for row {row.get('row_idx')} was {size_mb:.2f} MB, above --max-audio-mb {args.max_audio_mb:.2f}."
    )

  waveform, sample_rate = sf.read(io.BytesIO(response.content), dtype="float32")
  if waveform.ndim == 2:
    waveform = np.mean(waveform, axis=1).astype(np.float32)

  if sample_rate != args.expected_sample_rate:
    raise RuntimeError(
      f"Row {row.get('row_idx')} decoded at {sample_rate} Hz, expected {args.expected_sample_rate} Hz."
    )

  return waveform.astype(np.float32), int(sample_rate), asset.get("type")


def audio_stats(waveform, sample_rate: int) -> dict[str, Any]:
  import numpy as np

  return {
    "sample_rate": sample_rate,
    "sample_count": int(waveform.shape[0]),
    "duration_seconds": float(waveform.shape[0] / sample_rate),
    "min": float(waveform.min()),
    "max": float(waveform.max()),
    "mean": float(waveform.mean()),
    "rms": float(np.sqrt(np.mean(np.square(waveform)))),
  }


def code_stats(codes) -> dict[str, Any]:
  import numpy as np

  codes_array = codes.astype(int)
  return {
    "audio_codes_shape": list(codes_array.shape),
    "audio_codes_dtype": str(codes.dtype),
    "audio_codes_min": int(np.min(codes_array)),
    "audio_codes_max": int(np.max(codes_array)),
    "audio_codes_unique_count": int(np.unique(codes_array).shape[0]),
    "audio_codes": codes_array.tolist(),
    "audio_codes_prefix": codes_array[: min(8, codes_array.shape[0]), : min(8, codes_array.shape[1])].tolist(),
    "audio_codes_first_quantizer_prefix": codes_array[: min(24, codes_array.shape[0]), 0].tolist(),
  }


def bucket_for_code_steps(code_steps: int) -> int:
  return max(8, int(math.ceil(code_steps / 8) * 8))


def aggregate_samples(samples: list[dict[str, Any]]) -> dict[str, Any]:
  code_steps = [sample["encoded"]["audio_codes_shape"][0] for sample in samples]
  durations = [sample["audio"]["duration_seconds"] for sample in samples]
  return {
    "sample_count": len(samples),
    "total_code_steps": sum(code_steps),
    "min_code_steps": min(code_steps),
    "max_code_steps": max(code_steps),
    "median_code_steps": statistics.median(code_steps),
    "total_audio_seconds": sum(durations),
    "max_audio_seconds": max(durations),
    "quantizer_count": samples[0]["encoded"]["audio_codes_shape"][1],
    "suggested_decoder_buckets": sorted({bucket_for_code_steps(step) for step in code_steps}),
  }


def build_preflight_report(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  rows: list[dict[str, Any]],
) -> dict[str, Any]:
  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "preflight",
    "purpose": (
      "Preview representative LibriTTS-R rows for Qwen3-TTS 12 Hz speech-tokenizer decoder "
      "calibration without downloading audio or model weights."
    ),
    "source": {
      "dataset": args.dataset,
      "dataset_config": args.config,
      "dataset_split": args.split,
      "dataset_hub_url": f"https://hf.co/datasets/{args.dataset}",
      "row_offset": args.offset,
      "requested_sample_count": args.sample_count,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
    },
    "model_file_inventory": inventory,
    "sample_previews": [
      {
        **sanitized_sample_metadata(row),
        "audio": {
          "asset_type": audio_asset(row).get("type"),
          "src_available": True,
        },
      }
      for row in rows
    ],
    "next_command": (
      "uv run --with 'numpy>=2.0.0' --with 'torch>=2.6.0' --with 'transformers==4.57.3' "
      "--with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' --with 'sox>=1.5.0' "
      "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' --with 'torchaudio>=2.6.0' "
      "scripts/repo-maintenance/coreml-qwen3tts/generate-calibration-code-fixture.py "
      "--no-preflight-only --allow-model-download --allow-audio-download "
      "--qwen-source /path/to/Qwen3-TTS --output .local/coreml-qwen3tts/qwen3tts-calibration-code-fixture.json"
    ),
  }


def build_runtime_fixture(
  args: argparse.Namespace,
  inventory: dict[str, Any],
  rows: list[dict[str, Any]],
) -> dict[str, Any]:
  qwen_source = qwen_source_from_args(args)
  ensure_runtime_allowed(args, inventory)

  sys.path.insert(0, str(qwen_source))
  try:
    from qwen_tts import Qwen3TTSTokenizer
  except Exception as error:
    raise RuntimeError(
      f"Unable to import Qwen3TTSTokenizer from '{qwen_source}'. "
      "Confirm the upstream checkout is intact and this script's Python dependencies are installed. "
      f"Underlying import error: {error!r}"
    ) from error

  tokenizer = Qwen3TTSTokenizer.from_pretrained(args.model_id)
  samples = []

  for row in rows:
    waveform, sample_rate, asset_type = download_waveform(row, args)
    encoded = tokenizer.encode(waveform, sr=sample_rate)
    codes = encoded.audio_codes[0].detach().cpu().numpy()

    samples.append(
      {
        **sanitized_sample_metadata(row),
        "audio": {
          **audio_stats(waveform, sample_rate),
          "asset_type": asset_type,
          "source": "hugging_face_dataset_viewer_transient_audio_asset",
        },
        "encoded": code_stats(codes),
      }
    )

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "runtime",
    "purpose": (
      "Small representative audio-code fixture for Qwen3-TTS 12 Hz speech-tokenizer decoder "
      "Core ML calibration and W8A8 probing."
    ),
    "source": {
      "dataset": args.dataset,
      "dataset_config": args.config,
      "dataset_split": args.split,
      "dataset_hub_url": f"https://hf.co/datasets/{args.dataset}",
      "row_offset": args.offset,
      "requested_sample_count": args.sample_count,
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": inventory["resolved_revision"],
      "qwen_source_commit": args.upstream_commit,
    },
    "model_file_inventory": inventory,
    "calibration_scope": {
      "current_graph": "12 Hz speech-tokenizer decoder only",
      "current_input": "audio_codes shaped batch x code_steps x 16 codebooks",
      "code_step_samples": CODE_STEP_SAMPLES,
      "not_yet_covered": [
        "text tokenizer",
        "main Qwen3-TTS autoregressive talker",
        "code predictor",
        "speaker embedding and reference conditioning",
        "speech-tokenizer encoder",
      ],
    },
    "aggregate": aggregate_samples(samples),
    "samples": samples,
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  rows = get_dataset_rows(args.dataset, args.config, args.split, args.offset, args.sample_count)
  if len(rows) != args.sample_count:
    raise RuntimeError(
      f"Dataset Viewer returned {len(rows)} rows for requested sample count {args.sample_count}."
    )

  inventory = repo_file_inventory(args.model_id, args.revision)
  if args.preflight_only:
    return build_preflight_report(args, inventory, rows)

  return build_runtime_fixture(args, inventory, rows)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Generate a small Qwen3-TTS 12 Hz speech-tokenizer code fixture from open calibration audio. "
      "Default preflight mode avoids downloading audio or model weights."
    )
  )
  parser.add_argument("--dataset", default=DEFAULT_DATASET)
  parser.add_argument("--config", default=DEFAULT_CONFIG)
  parser.add_argument("--split", default=DEFAULT_SPLIT)
  parser.add_argument("--offset", type=int, default=DEFAULT_OFFSET)
  parser.add_argument("--sample-count", type=int, default=DEFAULT_SAMPLE_COUNT)
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--revision", default=None)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--qwen-source", default=None)
  parser.add_argument(
    "--preflight-only",
    action=argparse.BooleanOptionalAction,
    default=True,
    help="Only inspect Dataset Viewer rows and model file metadata. Default: true.",
  )
  parser.add_argument("--allow-model-download", action="store_true")
  parser.add_argument("--allow-audio-download", action="store_true")
  parser.add_argument("--max-model-download-mb", type=float, default=1_024.0)
  parser.add_argument("--max-audio-mb", type=float, default=25.0)
  parser.add_argument("--expected-sample-rate", type=int, default=DEFAULT_EXPECTED_SAMPLE_RATE)
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
    write_report(build_report(args), args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1

  return 0


if __name__ == "__main__":
  raise SystemExit(main())
