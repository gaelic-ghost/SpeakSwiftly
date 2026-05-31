#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "huggingface-hub>=0.36.0",
#   "transformers>=4.57.0",
# ]
# ///
"""Generate Qwen3-TTS text-token fixtures for Core ML parity work."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from transformers import AutoTokenizer


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_TARGET_TEXT = "Hello, this is a small Qwen3 TTS tokenizer parity test."


@dataclass(frozen=True)
class PromptFixture:
  kind: str
  raw_text: str
  wrapped_text: str
  input_ids: list[int]
  attention_mask: list[int]
  tokens: list[str]

  @property
  def length(self) -> int:
    return len(self.input_ids)

  def as_json(self) -> dict[str, Any]:
    return {
      "kind": self.kind,
      "raw_text": self.raw_text,
      "wrapped_text": self.wrapped_text,
      "length": self.length,
      "input_ids": self.input_ids,
      "attention_mask": self.attention_mask,
      "tokens": self.tokens,
    }


def target_prompt(text: str) -> str:
  return f"<|im_start|>assistant\n{text}<|im_end|>\n<|im_start|>assistant\n"


def reference_prompt(text: str) -> str:
  return f"<|im_start|>assistant\n{text}<|im_end|>\n"


def instruction_prompt(text: str) -> str:
  return f"<|im_start|>user\n{text}<|im_end|>\n"


def encode_prompt(tokenizer: Any, kind: str, raw_text: str, wrapped_text: str) -> PromptFixture:
  encoded = tokenizer(wrapped_text, return_attention_mask=True)
  input_ids = [int(token_id) for token_id in encoded["input_ids"]]
  attention_mask = [int(value) for value in encoded["attention_mask"]]
  tokens = [str(token) for token in tokenizer.convert_ids_to_tokens(input_ids)]

  return PromptFixture(
    kind=kind,
    raw_text=raw_text,
    wrapped_text=wrapped_text,
    input_ids=input_ids,
    attention_mask=attention_mask,
    tokens=tokens,
  )


def build_fixture(args: argparse.Namespace) -> dict[str, Any]:
  tokenizer_kwargs: dict[str, str] = {}
  if args.revision:
    tokenizer_kwargs["revision"] = args.revision

  try:
    tokenizer = AutoTokenizer.from_pretrained(args.model_id, **tokenizer_kwargs)
  except Exception as error:
    raise RuntimeError(
      f"Unable to load Qwen3-TTS tokenizer for model '{args.model_id}'. "
      "Confirm the model id, revision, network access, and Hugging Face cache state."
    ) from error

  prompts = [
    encode_prompt(tokenizer, "target", args.target_text, target_prompt(args.target_text))
  ]

  if args.reference_text:
    prompts.append(
      encode_prompt(
        tokenizer,
        "reference",
        args.reference_text,
        reference_prompt(args.reference_text),
      )
    )

  if args.instruction_text:
    prompts.append(
      encode_prompt(
        tokenizer,
        "instruction",
        args.instruction_text,
        instruction_prompt(args.instruction_text),
      )
    )

  return {
    "schema_version": 1,
    "created_at_utc": datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z"),
    "source": {
      "upstream_repository": "https://github.com/QwenLM/Qwen3-TTS",
      "upstream_commit": args.upstream_commit,
      "model_id": args.model_id,
      "revision": args.revision,
      "tokenizer_class": tokenizer.__class__.__name__,
      "tokenizer_name_or_path": str(tokenizer.name_or_path),
      "vocab_size": int(tokenizer.vocab_size),
      "model_max_length": int(tokenizer.model_max_length),
    },
    "upstream_prompt_wrappers": {
      "target": "<|im_start|>assistant\\n{text}<|im_end|>\\n<|im_start|>assistant\\n",
      "reference": "<|im_start|>assistant\\n{text}<|im_end|>\\n",
      "instruction": "<|im_start|>user\\n{instruct}<|im_end|>\\n",
    },
    "generation_defaults_from_upstream_wrapper": {
      "top_k": 50,
      "top_p": 1.0,
      "temperature": 0.9,
      "repetition_penalty": 1.05,
      "min_new_tokens": 2,
      "subtalker_top_k": 50,
      "subtalker_top_p": 1.0,
      "subtalker_temperature": 0.9,
    },
    "prompts": [prompt.as_json() for prompt in prompts],
  }


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Generate a small Qwen3-TTS text-token fixture that can be used to verify "
      "Swift prompt assembly and tokenizer parity before Core ML conversion."
    )
  )
  parser.add_argument(
    "--model-id",
    default=DEFAULT_MODEL_ID,
    help=f"Hugging Face model id that owns the Qwen3-TTS tokenizer. Default: {DEFAULT_MODEL_ID}",
  )
  parser.add_argument(
    "--revision",
    default=None,
    help="Optional Hugging Face revision to load for tokenizer files.",
  )
  parser.add_argument(
    "--upstream-commit",
    default=DEFAULT_UPSTREAM_COMMIT,
    help="Qwen3-TTS source commit used when matching prompt wrapper behavior.",
  )
  parser.add_argument(
    "--target-text",
    default=DEFAULT_TARGET_TEXT,
    help="Target sentence to wrap as the assistant TTS prompt.",
  )
  parser.add_argument(
    "--reference-text",
    default=None,
    help="Optional reference transcript to wrap as an ICL reference prompt.",
  )
  parser.add_argument(
    "--instruction-text",
    default=None,
    help="Optional voice-design instruction to wrap as a user prompt.",
  )
  parser.add_argument(
    "--output",
    type=Path,
    default=None,
    help="Optional output JSON path. Defaults to stdout.",
  )
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
    fixture = build_fixture(args)
    write_fixture(fixture, args.output)
  except Exception as error:
    print(f"ERROR: {error}", file=sys.stderr)
    return 1

  return 0


if __name__ == "__main__":
  raise SystemExit(main())
