#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "huggingface-hub>=0.36.0",
#   "tokenizers>=0.20.0",
# ]
# ///
"""Generate no-weight Higgs Audio v3 tokenizer parity fixtures."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi, hf_hub_download
from tokenizers import Tokenizer


DEFAULT_MODEL_ID = "bosonai/higgs-audio-v3-tts-4b"
DEFAULT_SOURCE_MAP = "docs/maintainers/higgs-audio-v3/official-pipeline-map-2026-06-24.json"
DEFAULT_PLAIN_TEXT = (
  "Welcome to SpeakSwiftly. This is the first official Higgs Audio v3 parity fixture."
)
DEFAULT_CONTROL_TEXT = (
  "<|emotion:elation|>Welcome aboard. Hello there <|prosody:pause|> and thanks for listening."
)

REQUIRED_SPECIAL_TOKENS = {
  "<|tts|>": 151667,
  "<|audio|>": 151670,
  "<|audio_end|>": 151671,
  "<|text|>": 151672,
  "<|ref_audio|>": 151679,
  "<|ref_text|>": 151680,
}

CONTROL_SPECIAL_TOKENS = {
  "<|emotion:elation|>": 151681,
  "<|prosody:pause|>": 151722,
}


@dataclass(frozen=True)
class PromptCase:
  name: str
  kind: str
  raw_text: str
  prompt_ids: list[int]
  prompt_tokens: list[str]
  section_ranges: dict[str, list[int]]

  def as_json(self) -> dict[str, Any]:
    return {
      "name": self.name,
      "kind": self.kind,
      "raw_text": self.raw_text,
      "prompt_shape": "<|tts|> <|text|> target text tokens <|audio|>",
      "prompt_shape_note": (
        "The spaces in prompt_shape are prose separators only. Official "
        "SGLang and vLLM prompt builders append token ids directly."
      ),
      "prompt_length": len(self.prompt_ids),
      "prompt_ids": self.prompt_ids,
      "prompt_tokens": self.prompt_tokens,
      "section_ranges": self.section_ranges,
    }


def current_utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def resolve_package_path(path: Path) -> Path:
  if path.is_absolute():
    return path
  return Path.cwd() / path


def load_json(path: Path) -> dict[str, Any]:
  try:
    value = json.loads(path.read_text(encoding="utf-8"))
  except FileNotFoundError as error:
    raise RuntimeError(f"Required JSON file '{path}' does not exist.") from error
  except json.JSONDecodeError as error:
    raise RuntimeError(f"Required JSON file '{path}' is not valid JSON.") from error

  if not isinstance(value, dict):
    raise RuntimeError(f"Required JSON file '{path}' must contain a JSON object.")
  return value


def hf_download(model_id: str, revision: str | None, filename: str) -> Path:
  try:
    return Path(hf_hub_download(repo_id=model_id, revision=revision, filename=filename))
  except Exception as error:
    raise RuntimeError(
      f"Unable to download '{filename}' from Hugging Face model '{model_id}'. "
      "Confirm the model id, revision, network access, and Hugging Face cache state."
    ) from error


def token_id(tokenizer: Tokenizer, token: str) -> int:
  token_id_value = tokenizer.token_to_id(token)
  if token_id_value is None:
    raise RuntimeError(f"Official Higgs tokenizer is missing required special token '{token}'.")
  return int(token_id_value)


def validate_special_tokens(tokenizer: Tokenizer) -> dict[str, int]:
  expected = REQUIRED_SPECIAL_TOKENS | CONTROL_SPECIAL_TOKENS
  observed: dict[str, int] = {}

  for token, expected_id in expected.items():
    observed_id = token_id(tokenizer, token)
    observed[token] = observed_id
    if observed_id != expected_id:
      raise RuntimeError(
        f"Official Higgs tokenizer special token '{token}' resolved to id {observed_id}, "
        f"but the checked-in source map expects {expected_id}."
      )

  return observed


def token_text(tokenizer: Tokenizer, token_id_value: int) -> str:
  if token_id_value < 0:
    return "<placeholder:-100>"
  token = tokenizer.id_to_token(token_id_value)
  return str(token) if token is not None else f"<unknown:{token_id_value}>"


def build_plain_prompt(tokenizer: Tokenizer, name: str, text: str) -> PromptCase:
  tts_id = token_id(tokenizer, "<|tts|>")
  text_id = token_id(tokenizer, "<|text|>")
  audio_id = token_id(tokenizer, "<|audio|>")
  text_ids = [int(token_id_value) for token_id_value in tokenizer.encode(text, add_special_tokens=False).ids]
  prompt_ids = [tts_id, text_id, *text_ids, audio_id]

  return PromptCase(
    name=name,
    kind="plain_tts",
    raw_text=text,
    prompt_ids=prompt_ids,
    prompt_tokens=[token_text(tokenizer, token_id_value) for token_id_value in prompt_ids],
    section_ranges={
      "tts_marker": [0, 1],
      "text_marker": [1, 2],
      "target_text": [2, 2 + len(text_ids)],
      "audio_marker": [len(prompt_ids) - 1, len(prompt_ids)],
    },
  )


def summarize_source_map(source_map: dict[str, Any]) -> dict[str, Any]:
  hf = source_map.get("hugging_face") or {}
  text_config = hf.get("text_config") or {}
  audio_encoder_config = hf.get("audio_encoder_config") or {}

  return {
    "model_type": (hf.get("model_config") or {}).get("model_type"),
    "architecture": (hf.get("model_config") or {}).get("architectures"),
    "text_hidden_size": text_config.get("hidden_size"),
    "text_vocab_size": text_config.get("vocab_size"),
    "text_layers": text_config.get("num_hidden_layers"),
    "attention_heads": text_config.get("num_attention_heads"),
    "kv_heads": text_config.get("num_key_value_heads"),
    "rope_parameters": text_config.get("rope_parameters"),
    "audio_placeholder_id": (hf.get("model_config") or {}).get("audio_token_id"),
    "num_codebooks": audio_encoder_config.get("num_codebooks"),
    "codebook_vocab_size": audio_encoder_config.get("vocab_size"),
    "mel_per_sample": audio_encoder_config.get("mel_per_sample"),
    "uses_delay_pattern": audio_encoder_config.get("use_delay_pattern"),
    "codec_checkpoint_prefix": "tied.embedding.modality_embeddings.0.model.",
    "sample_rate_hz": 24000,
    "boc_id": 1024,
    "eoc_id": 1025,
  }


def build_fixture(args: argparse.Namespace) -> dict[str, Any]:
  source_map_path = resolve_package_path(args.source_map)
  source_map = load_json(source_map_path)

  tokenizer_path = hf_download(args.model_id, args.revision, "tokenizer.json")
  tokenizer_config_path = hf_download(args.model_id, args.revision, "tokenizer_config.json")
  chat_template_path = hf_download(args.model_id, args.revision, "chat_template.jinja")

  try:
    model_info = HfApi().model_info(args.model_id, revision=args.revision)
    resolved_revision = model_info.sha
  except Exception:
    resolved_revision = None

  try:
    tokenizer = Tokenizer.from_file(str(tokenizer_path))
  except Exception as error:
    raise RuntimeError(f"Unable to load official tokenizer JSON from '{tokenizer_path}'.") from error

  special_tokens = validate_special_tokens(tokenizer)
  cases = [
    build_plain_prompt(tokenizer, "plain-english-tts", args.plain_text),
    build_plain_prompt(tokenizer, "control-tags-tts", args.control_text),
  ]

  tokenizer_config = load_json(tokenizer_config_path)
  chat_template = chat_template_path.read_text(encoding="utf-8")

  return {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or current_utc_timestamp(),
    "mode": "higgs_audio_v3_tokenizer_parity_fixture",
    "source": {
      "model_id": args.model_id,
      "requested_revision": args.revision,
      "resolved_revision": resolved_revision,
      "source_map_path": str(args.source_map),
      "source_map_created_at_utc": source_map.get("created_at_utc"),
      "files_downloaded": [
        "tokenizer.json",
        "tokenizer_config.json",
        "chat_template.jinja",
      ],
      "no_model_weights_downloaded": True,
    },
    "official_runtime_constants": summarize_source_map(source_map),
    "tokenizer": {
      "tokenizer_config_class": tokenizer_config.get("tokenizer_class"),
      "tokenizer_model_type": tokenizer.model.__class__.__name__,
      "model_max_length": tokenizer_config.get("model_max_length"),
      "added_token_count": len(tokenizer.get_added_tokens_decoder()),
      "special_tokens": special_tokens,
      "chat_template_available": bool(chat_template.strip()),
      "chat_template_participates_in_tts_prompt": False,
      "prompt_builder_source": (
        "Official SGLang and vLLM Higgs prompt builders append token ids directly: "
        "[tts_id, text_id, tokenized target text..., audio_id]."
      ),
    },
    "cases": [case.as_json() for case in cases],
    "next_checks": [
      "Compare prompt_ids with an official SGLang or vLLM preprocessing run for the same text.",
      "Capture first decode-step shape from an official serving path before selecting a Core AI boundary.",
      "Keep codec/vocoder parity separate from text-to-codebook parity.",
    ],
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Generate a no-weight Higgs Audio v3 tokenizer parity fixture from the official "
      "Hugging Face tokenizer and checked-in source map."
    )
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--revision", default=None)
  parser.add_argument(
    "--source-map",
    type=Path,
    default=Path(DEFAULT_SOURCE_MAP),
    help=f"Checked-in official pipeline map. Default: {DEFAULT_SOURCE_MAP}",
  )
  parser.add_argument("--plain-text", default=DEFAULT_PLAIN_TEXT)
  parser.add_argument("--control-text", default=DEFAULT_CONTROL_TEXT)
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument("--output", type=Path, default=None)
  return parser.parse_args()


def write_fixture(fixture: dict[str, Any], output: Path | None) -> None:
  rendered = json.dumps(fixture, indent=2, ensure_ascii=False) + "\n"
  if output is None:
    sys.stdout.write(rendered)
    return

  output.parent.mkdir(parents=True, exist_ok=True)
  output.write_text(rendered, encoding="utf-8")


def main() -> int:
  args = parse_args()
  try:
    write_fixture(build_fixture(args), args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
