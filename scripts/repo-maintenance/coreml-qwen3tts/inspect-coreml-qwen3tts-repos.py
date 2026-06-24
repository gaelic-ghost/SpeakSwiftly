#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "huggingface-hub>=0.36.0",
# ]
# ///
"""Compare public Core ML Qwen3-TTS Hugging Face artifact inventories."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi, hf_hub_download


DEFAULT_REPOS = [
  "FluidInference/qwen3-tts-coreml",
  "aufklarer/Qwen3-TTS-CoreML",
]


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def load_optional_json(repo_id: str, revision: str | None, filename: str) -> dict[str, Any] | None:
  try:
    downloaded_path = hf_hub_download(repo_id=repo_id, revision=revision, filename=filename)
  except Exception:
    return None

  try:
    return json.loads(Path(downloaded_path).read_text(encoding="utf-8"))
  except json.JSONDecodeError:
    return None


def model_names(files: list[str], suffix: str) -> list[str]:
  names = set()
  for filename in files:
    if suffix not in filename:
      continue
    names.add(filename.split(suffix, maxsplit=1)[0] + suffix)
  return sorted(names)


def has_any(files: list[str], suffix: str) -> bool:
  return any(filename.endswith(suffix) for filename in files)


def repo_summary(repo_id: str, revision: str | None) -> dict[str, Any]:
  model_info = HfApi().model_info(repo_id, revision=revision, files_metadata=False)
  files = sorted(sibling.rfilename for sibling in model_info.siblings)
  config = load_optional_json(repo_id, revision, "config.json") or {}

  return {
    "repo_id": repo_id,
    "resolved_revision": model_info.sha,
    "last_modified": model_info.last_modified.isoformat().replace("+00:00", "Z")
    if model_info.last_modified
    else None,
    "downloads": model_info.downloads,
    "likes": model_info.likes,
    "used_storage_bytes": model_info.used_storage,
    "license": (model_info.card_data or {}).get("license"),
    "languages": (model_info.card_data or {}).get("language", []),
    "base_model": (model_info.card_data or {}).get("base_model"),
    "config": {
      "model_type": config.get("model_type"),
      "architecture": config.get("architecture"),
      "model_id": config.get("model_id"),
      "models": config.get("models", []),
      "quantization": config.get("quantization"),
      "max_seq_len": config.get("max_seq_len"),
      "max_codec_tokens": config.get("max_codec_tokens"),
      "sample_rate": config.get("sample_rate"),
      "hidden_size": config.get("hidden_size"),
      "requires_speaker_embedding": config.get("requires_speaker_embedding"),
    },
    "artifact_inventory": {
      "file_count": len(files),
      "compiled_model_names": model_names(files, ".mlmodelc"),
      "source_package_names": model_names(files, ".mlpackage"),
      "has_vocab_json": "vocab.json" in files,
      "has_merges_txt": "merges.txt" in files,
      "has_cp_embeddings": "cp_embeddings.npy" in files,
      "has_speaker_embedding_official": "speaker_embedding_official.npy" in files,
      "has_speaker_embedding": "speaker_embedding.npy" in files,
      "has_tts_bos_embed": "tts_bos_embed.npy" in files,
      "has_tts_eos_embed": "tts_eos_embed.npy" in files,
      "has_tts_pad_embed": "tts_pad_embed.npy" in files,
      "has_mlmodelc_model_mil": has_any(files, "model.mil"),
      "has_mlpackage_model_mlmodel": has_any(files, "model.mlmodel"),
    },
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  repos = [repo_summary(repo_id, args.revision) for repo_id in args.repo]
  by_repo = {repo["repo_id"]: repo for repo in repos}
  aufklarer = by_repo.get("aufklarer/Qwen3-TTS-CoreML")
  fluid = by_repo.get("FluidInference/qwen3-tts-coreml")

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "coreml_qwen3tts_external_repo_inventory",
    "source": {
      "inspection_method": "Hugging Face model_info plus small config.json download",
      "repos": args.repo,
      "requested_revision": args.revision,
      "no_large_artifacts_downloaded": True,
    },
    "repositories": repos,
    "comparison": {
      "newer_candidate": "aufklarer/Qwen3-TTS-CoreML",
      "older_reference": "FluidInference/qwen3-tts-coreml",
      "shared_compiled_models": sorted(
        set(aufklarer["artifact_inventory"]["compiled_model_names"])
        & set(fluid["artifact_inventory"]["compiled_model_names"])
      )
      if aufklarer and fluid
      else [],
      "aufklarer_only_signals": [
        "Includes vocab.json and merges.txt, so text-tokenizer parity can be probed from repo-local assets.",
        "Declares a six-model W8A16 ANE-oriented architecture in config.json.",
        "Points at speech-swift Qwen3TTSCoreML as the reference Swift integration surface.",
      ],
      "fluid_only_signals": [
        "Publishes .mlpackage source packages as well as compiled .mlmodelc bundles.",
        "Publishes cp_embeddings.npy and speaker_embedding_official.npy.",
        "Model card documents LM prefill/decode and code-predictor prefill/decode stages explicitly.",
      ],
    },
    "decision": {
      "matrix_status": "add_metadata_probe_only",
      "reason": (
        "aufklarer/Qwen3-TTS-CoreML is worth tracking because it uses the same six compiled "
        "model names as FluidInference, adds tokenizer assets, declares W8A16, and has an "
        "active Swift reference implementation. It is not ready for a runtime benchmark in "
        "SpeakSwiftly until the talker/code-generator boundary probe can consume its six-model "
        "layout without introducing a new runtime backend."
      ),
      "next_probe": (
        "Use this inventory fixture to gate a later talker/code-generator probe that downloads "
        "only the minimum compiled model subset needed to compare prompt wrapping, token IDs, "
        "first codec-token generation, codebook order, and stage timing."
      ),
      "do_not_do_yet": [
        "Do not add a public SpeechBackend.",
        "Do not add speech-swift as a package dependency.",
        "Do not download the full Core ML repository in default validation.",
        "Do not compare audible quality until the talker path produces a matched waveform fixture.",
      ],
    },
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Inspect public Hugging Face Core ML Qwen3-TTS artifact inventories without "
      "downloading large model bundles."
    )
  )
  parser.add_argument(
    "--repo",
    action="append",
    default=[],
    help="Hugging Face model repo id to inspect. Defaults to FluidInference and aufklarer.",
  )
  parser.add_argument(
    "--revision",
    default=None,
    help="Optional Hugging Face revision to inspect for every repo.",
  )
  parser.add_argument(
    "--created-at-utc",
    default=None,
    help="Optional ISO-8601 UTC timestamp for stable checked-in metadata fixtures.",
  )
  parser.add_argument(
    "--output",
    type=Path,
    default=None,
    help="Optional output JSON path. Defaults to stdout.",
  )
  args = parser.parse_args()
  if not args.repo:
    args.repo = DEFAULT_REPOS
  return args


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
