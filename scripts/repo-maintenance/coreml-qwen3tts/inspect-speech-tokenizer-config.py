#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "huggingface-hub>=0.36.0",
# ]
# ///
"""Record config-only metadata for the Qwen3-TTS 12 Hz speech tokenizer."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi, hf_hub_download


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"


def load_repo_json(model_id: str, revision: str | None, filename: str) -> dict[str, Any]:
  try:
    downloaded_path = hf_hub_download(repo_id=model_id, revision=revision, filename=filename)
  except Exception as error:
    raise RuntimeError(
      f"Unable to download '{filename}' from Hugging Face model '{model_id}'. "
      "Confirm the model id, revision, network access, and Hugging Face cache state."
    ) from error

  return json.loads(Path(downloaded_path).read_text(encoding="utf-8"))


def nested_get(object: dict[str, Any], path: list[str], default: Any = None) -> Any:
  value: Any = object
  for key in path:
    if not isinstance(value, dict) or key not in value:
      return default
    value = value[key]
  return value


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  config = load_repo_json(args.model_id, args.revision, "config.json")
  feature_extractor = load_repo_json(args.model_id, args.revision, "preprocessor_config.json")

  try:
    model_info = HfApi().model_info(args.model_id, revision=args.revision)
    resolved_revision = model_info.sha
  except Exception:
    resolved_revision = None

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "source": {
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": resolved_revision,
    },
    "model_config": {
      "model_type": config.get("model_type"),
      "input_sample_rate": config.get("input_sample_rate"),
      "output_sample_rate": config.get("output_sample_rate"),
      "encode_downsample_rate": config.get("encode_downsample_rate"),
      "decode_upsample_rate": config.get("decode_upsample_rate"),
      "encoder_valid_num_quantizers": config.get("encoder_valid_num_quantizers"),
    },
    "feature_extractor": {
      "feature_extractor_type": feature_extractor.get("feature_extractor_type"),
      "sampling_rate": feature_extractor.get("sampling_rate"),
      "padding_value": feature_extractor.get("padding_value"),
      "return_attention_mask": feature_extractor.get("return_attention_mask"),
    },
    "encoder_config": {
      "model_type": nested_get(config, ["encoder_config", "model_type"]),
      "num_quantizers": nested_get(config, ["encoder_config", "num_quantizers"]),
      "codebook_size": nested_get(config, ["encoder_config", "codebook_size"]),
      "sampling_rate": nested_get(config, ["encoder_config", "sampling_rate"]),
    },
    "decoder_config": {
      "hidden_size": nested_get(config, ["decoder_config", "hidden_size"]),
      "num_hidden_layers": nested_get(config, ["decoder_config", "num_hidden_layers"]),
      "num_attention_heads": nested_get(config, ["decoder_config", "num_attention_heads"]),
      "num_key_value_heads": nested_get(config, ["decoder_config", "num_key_value_heads"]),
      "latent_dim": nested_get(config, ["decoder_config", "latent_dim"]),
      "decoder_dim": nested_get(config, ["decoder_config", "decoder_dim"]),
      "upsample_rates": nested_get(config, ["decoder_config", "upsample_rates"]),
      "upsampling_ratios": nested_get(config, ["decoder_config", "upsampling_ratios"]),
    },
    "coreml_boundary_implications": [
      "12 Hz encode/decode uses 24000 Hz audio and 1920 samples per code step.",
      "Core ML decode should accept padded int64 codes shaped batch x codes_length x num_quantizers.",
      "Padding uses -1 before decode, then upstream clamps codes to zero and trims by valid CB0 length.",
      "The first Core ML speech-tokenizer probe should split encoder and decoder instead of using one graph.",
    ],
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Download only small Hugging Face metadata files for the Qwen3-TTS 12 Hz "
      "speech tokenizer and emit a JSON report for Core ML planning."
    )
  )
  parser.add_argument(
    "--model-id",
    default=DEFAULT_MODEL_ID,
    help=f"Hugging Face 12 Hz tokenizer model id. Default: {DEFAULT_MODEL_ID}",
  )
  parser.add_argument(
    "--revision",
    default=None,
    help="Optional Hugging Face revision to inspect.",
  )
  parser.add_argument(
    "--upstream-commit",
    default=DEFAULT_UPSTREAM_COMMIT,
    help="Qwen3-TTS source commit used when matching speech-tokenizer behavior.",
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
