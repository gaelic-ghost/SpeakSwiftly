#!/usr/bin/env python3
"""Inspect official Higgs Audio v3 metadata without downloading weights."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MODEL_ID = "bosonai/higgs-audio-v3-tts-4b"
DEFAULT_HF_REVISION = "main"
DEFAULT_SGLANG_REPO = "sgl-project/sglang-omni"
DEFAULT_SGLANG_REVISION = "main"
DEFAULT_VLLM_REPO = "vllm-project/vllm-omni"
DEFAULT_VLLM_REVISION = "main"

HF_TEXT_FILES = [
  "README.md",
  "PROMPTING.md",
  "config.json",
  "tokenizer_config.json",
  "tokenizer.json",
  "chat_template.jinja",
  "model.safetensors.index.json",
]

SGLANG_SOURCE_FILES = [
  "sglang_omni/models/higgs_tts/config.py",
  "sglang_omni/models/higgs_tts/hf_config.py",
  "sglang_omni/models/higgs_tts/text_tokenizer.py",
  "sglang_omni/models/higgs_tts/request_builders.py",
  "sglang_omni/models/higgs_tts/stages.py",
  "sglang_omni/models/higgs_tts/model.py",
  "sglang_omni/models/higgs_tts/modeling.py",
  "sglang_omni/models/higgs_tts/sampler.py",
  "sglang_omni/models/higgs_tts/audio_codec.py",
  "sglang_omni/models/higgs_tts/vocoder_scheduler.py",
  "sglang_omni/models/higgs_tts/model_runner.py",
  "sglang_omni/models/higgs_tts/weight_loader.py",
]

VLLM_SOURCE_FILES = [
  "vllm_omni/model_executor/models/higgs_audio_v3/pipeline.py",
  "vllm_omni/model_executor/models/higgs_audio_v3/higgs_audio_v3_tokenizer.py",
  "vllm_omni/model_executor/models/higgs_audio_v3/higgs_audio_v3_talker.py",
  "vllm_omni/model_executor/models/higgs_audio_v3/higgs_audio_v3_code2wav.py",
  "vllm_omni/model_executor/stage_input_processors/higgs_audio_v3.py",
  "vllm_omni/entrypoints/openai/tts_adapters/higgs_audio_v3.py",
  "vllm_omni/deploy/higgs_multimodal_qwen3.yaml",
]

INTERESTING_SPECIALS = [
  "tts",
  "ref",
  "text",
  "audio",
  "emotion",
  "prosody",
  "style",
  "sfx",
  "pause",
]

RUNTIME_CONSTANT_PATTERN = re.compile(
  r"^\s*(?P<name>[A-Z][A-Z0-9_]*|_[A-Z][A-Z0-9_]*)\s*[:=]\s*(?P<value>[^#\n]+)"
)


@dataclass(frozen=True)
class TextSource:
  label: str
  url: str
  text: str


def utc_timestamp() -> str:
  return (
    datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z")
  )


def fetch_text(url: str) -> str:
  request = urllib.request.Request(
    url,
    headers={
      "User-Agent": "SpeakSwiftly-maintainer-higgs-inventory/1.0",
    },
  )
  try:
    with urllib.request.urlopen(request, timeout=45) as response:
      return response.read().decode("utf-8", "replace")
  except Exception as error:
    raise RuntimeError(f"Unable to fetch '{url}'. Confirm network access and the source revision.") from error


def fetch_json(url: str) -> Any:
  try:
    return json.loads(fetch_text(url))
  except json.JSONDecodeError as error:
    raise RuntimeError(f"Fetched '{url}', but it was not valid JSON.") from error


def hf_resolve_url(model_id: str, revision: str, filename: str) -> str:
  return f"https://huggingface.co/{model_id}/resolve/{revision}/{filename}"


def github_raw_url(repo: str, revision: str, path: str) -> str:
  return f"https://raw.githubusercontent.com/{repo}/{revision}/{path}"


def github_commit_url(repo: str, revision: str) -> str:
  return f"https://api.github.com/repos/{repo}/commits/{revision}"


def resolve_github_revision(repo: str, revision: str) -> str | None:
  try:
    data = fetch_json(github_commit_url(repo, revision))
  except RuntimeError:
    return None
  sha = data.get("sha")
  return sha if isinstance(sha, str) else None


def nested_get(value: dict[str, Any], path: list[str], default: Any = None) -> Any:
  current: Any = value
  for key in path:
    if not isinstance(current, dict) or key not in current:
      return default
    current = current[key]
  return current


def first_matching_line(text: str, patterns: list[str]) -> int | None:
  for index, line in enumerate(text.splitlines(), start=1):
    if all(pattern in line for pattern in patterns):
      return index
  return None


def extract_tokenizer_specials(tokenizer: dict[str, Any]) -> list[dict[str, Any]]:
  added_tokens = tokenizer.get("added_tokens", [])
  if not isinstance(added_tokens, list):
    return []

  specials: list[dict[str, Any]] = []
  for token in added_tokens:
    if not isinstance(token, dict):
      continue
    content = str(token.get("content", ""))
    if any(marker in content for marker in INTERESTING_SPECIALS):
      specials.append(
        {
          "id": token.get("id"),
          "content": content,
          "special": token.get("special"),
        }
      )

  return sorted(specials, key=lambda item: int(item["id"]))


def extract_prompt_tags(prompting: str) -> dict[str, Any]:
  tags: dict[str, list[str]] = {
    "emotion": [],
    "prosody": [],
    "style": [],
    "sfx": [],
  }

  for match in re.finditer(r"<\|(?P<category>emotion|prosody|style|sfx):(?P<tag>[^|]+)\|>", prompting):
    category = match.group("category")
    tag = match.group("tag")
    if tag not in tags[category]:
      tags[category].append(tag)

  for category in tags:
    tags[category].sort()

  return {
    "tag_count_in_catalog_heading": parse_int_after(prompting, "Full tag catalog ("),
    "documented_tags_seen_in_examples": tags,
    "format_rule_line": first_matching_line(prompting, ["Every tag is", "category"]),
    "inline_sfx_rule_line": first_matching_line(prompting, ["sfx", "gotcha"]),
    "inline_pause_rule_line": first_matching_line(prompting, ["Inline", "pause"]),
  }


def parse_int_after(text: str, marker: str) -> int | None:
  start = text.find(marker)
  if start < 0:
    return None
  match = re.search(r"\d+", text[start + len(marker) :])
  return int(match.group(0)) if match else None


def count_weight_prefixes(weight_map: dict[str, Any]) -> dict[str, Any]:
  prefixes = [
    "tied.embedding.modality_embeddings.0.model.",
    "tied.embedding.modality_embeddings.0.embedding",
    "tied.embedding.text_embedding",
    "body.layers.",
    "body.norm",
    "tied.head",
  ]

  result: dict[str, Any] = {}
  for prefix in prefixes:
    matches = [key for key in weight_map if key.startswith(prefix)]
    result[prefix] = {
      "count": len(matches),
      "examples": matches[:6],
    }
  return result


def extract_runtime_constants(source: TextSource) -> list[dict[str, Any]]:
  constants: list[dict[str, Any]] = []
  for line_number, line in enumerate(source.text.splitlines(), start=1):
    match = RUNTIME_CONSTANT_PATTERN.match(line)
    if match is None:
      continue
    name = match.group("name")
    if name.startswith("__") or len(name) == 1:
      continue
    constants.append(
      {
        "name": name,
        "value": match.group("value").strip().rstrip(","),
        "line": line_number,
      }
    )
  return constants


def extract_symbol_lines(source: TextSource) -> list[dict[str, Any]]:
  symbols: list[dict[str, Any]] = []
  for line_number, line in enumerate(source.text.splitlines(), start=1):
    stripped = line.strip()
    if re.match(r"^(class|def|async def)\s+", stripped):
      symbols.append(
        {
          "line": line_number,
          "declaration": stripped,
        }
      )
  return symbols


def key_lines(source: TextSource, terms: list[str], limit: int = 32) -> list[dict[str, Any]]:
  matched: list[dict[str, Any]] = []
  lowered_terms = [term.lower() for term in terms]
  for line_number, line in enumerate(source.text.splitlines(), start=1):
    lowered = line.lower()
    if any(term in lowered for term in lowered_terms):
      matched.append(
        {
          "line": line_number,
          "text": line.strip()[:220],
        }
      )
    if len(matched) >= limit:
      break
  return matched


def build_hf_inventory(model_id: str, revision: str) -> dict[str, Any]:
  files = {
    filename: fetch_text(hf_resolve_url(model_id, revision, filename))
    for filename in HF_TEXT_FILES
  }

  config = json.loads(files["config.json"])
  tokenizer = json.loads(files["tokenizer.json"])
  model_index = json.loads(files["model.safetensors.index.json"])
  weight_map = model_index.get("weight_map", {})
  if not isinstance(weight_map, dict):
    weight_map = {}

  return {
    "model_id": model_id,
    "requested_revision": revision,
    "source_files": {
      filename: {
        "url": hf_resolve_url(model_id, revision, filename),
        "bytes": len(text.encode("utf-8")),
        "lines": len(text.splitlines()),
      }
      for filename, text in files.items()
    },
    "model_config": {
      "architectures": config.get("architectures"),
      "model_type": config.get("model_type"),
      "transformers_version": config.get("transformers_version"),
      "audio_token_id": config.get("audio_token_id"),
      "ignore_index": config.get("ignore_index"),
      "hidden_size_shortcut": config.get("_hidden_size"),
      "vocab_size_shortcut": config.get("_vocab_size"),
    },
    "text_config": {
      "model_type": nested_get(config, ["text_config", "model_type"]),
      "architecture": nested_get(config, ["text_config", "architectures"]),
      "dtype": nested_get(config, ["text_config", "dtype"]),
      "hidden_size": nested_get(config, ["text_config", "hidden_size"]),
      "intermediate_size": nested_get(config, ["text_config", "intermediate_size"]),
      "num_hidden_layers": nested_get(config, ["text_config", "num_hidden_layers"]),
      "num_attention_heads": nested_get(config, ["text_config", "num_attention_heads"]),
      "num_key_value_heads": nested_get(config, ["text_config", "num_key_value_heads"]),
      "head_dim": nested_get(config, ["text_config", "head_dim"]),
      "vocab_size": nested_get(config, ["text_config", "vocab_size"]),
      "max_position_embeddings": nested_get(config, ["text_config", "max_position_embeddings"]),
      "max_window_layers": nested_get(config, ["text_config", "max_window_layers"]),
      "bos_token_id": nested_get(config, ["text_config", "bos_token_id"]),
      "eos_token_id": nested_get(config, ["text_config", "eos_token_id"]),
      "pad_token_id": nested_get(config, ["text_config", "pad_token_id"]),
      "rms_norm_eps": nested_get(config, ["text_config", "rms_norm_eps"]),
      "rope_parameters": nested_get(config, ["text_config", "rope_parameters"]),
      "attention_dropout": nested_get(config, ["text_config", "attention_dropout"]),
      "attention_bias": nested_get(config, ["text_config", "attention_bias"]),
      "use_cache": nested_get(config, ["text_config", "use_cache"]),
      "tie_word_embeddings": nested_get(config, ["text_config", "tie_word_embeddings"]),
    },
    "audio_encoder_config": {
      "model_type": nested_get(config, ["audio_encoder_config", "model_type"]),
      "encoder_type": nested_get(config, ["audio_encoder_config", "encoder_type"]),
      "num_codebooks": nested_get(config, ["audio_encoder_config", "num_codebooks"]),
      "vocab_size": nested_get(config, ["audio_encoder_config", "vocab_size"]),
      "mel_per_sample": nested_get(config, ["audio_encoder_config", "mel_per_sample"]),
      "max_chunk_size": nested_get(config, ["audio_encoder_config", "max_chunk_size"]),
      "out_dim": nested_get(config, ["audio_encoder_config", "out_dim"]),
      "use_delay_pattern": nested_get(config, ["audio_encoder_config", "use_delay_pattern"]),
      "tie_word_embeddings": nested_get(config, ["audio_encoder_config", "tie_word_embeddings"]),
      "whisper_config": nested_get(config, ["audio_encoder_config", "whisper_config"]),
      "qwen3_aut_config": nested_get(config, ["audio_encoder_config", "qwen3_aut_config"]),
    },
    "tokenizer": {
      "model_type": nested_get(tokenizer, ["model", "type"]),
      "normalizer": nested_get(tokenizer, ["normalizer", "type"]),
      "pre_tokenizer": nested_get(tokenizer, ["pre_tokenizer", "type"]),
      "post_processor": nested_get(tokenizer, ["post_processor", "type"]),
      "added_token_count": len(tokenizer.get("added_tokens", [])),
      "interesting_added_tokens": extract_tokenizer_specials(tokenizer),
    },
    "prompting": extract_prompt_tags(files["PROMPTING.md"]),
    "chat_template": {
      "line_count": len(files["chat_template.jinja"].splitlines()),
      "uses_qwen_im_tokens": "<|im_start|>" in files["chat_template.jinja"],
    },
    "weight_index": {
      "metadata": model_index.get("metadata", {}),
      "weight_entry_count": len(weight_map),
      "prefixes": count_weight_prefixes(weight_map),
    },
  }


def build_source_inventory(repo: str, revision: str, paths: list[str]) -> dict[str, Any]:
  resolved_revision = resolve_github_revision(repo, revision)
  sources = [
    TextSource(
      label=path,
      url=github_raw_url(repo, revision, path),
      text=fetch_text(github_raw_url(repo, revision, path)),
    )
    for path in paths
  ]

  terms = [
    "audio",
    "codebook",
    "codec",
    "decode",
    "delay",
    "frame",
    "pcm",
    "prefill",
    "prompt",
    "sample",
    "stream",
    "tokenizer",
    "vocoder",
    "wav",
  ]

  return {
    "repo": repo,
    "requested_revision": revision,
    "resolved_revision": resolved_revision,
    "files": [
      {
        "path": source.label,
        "url": source.url,
        "line_count": len(source.text.splitlines()),
        "symbols": extract_symbol_lines(source),
        "runtime_constants": extract_runtime_constants(source),
        "key_lines": key_lines(source, terms),
      }
      for source in sources
    ],
  }


def build_component_map(report: dict[str, Any]) -> dict[str, Any]:
  return {
    "tokenizer": {
      "official_assets": ["tokenizer.json", "tokenizer_config.json", "chat_template.jinja"],
      "owner": "Swift-owned loader and prompt checks should match official Hugging Face tokenizer assets.",
      "known_constants": [
        "Qwen2Tokenizer tokenizer class",
        "BPE tokenizer with NFC normalizer and ByteLevel post-processor",
        "<|tts|>, <|ref_audio|>, <|text|>, and <|audio|> required by official serving prompts",
      ],
    },
    "prompt_builder": {
      "official_sources": [
        "PROMPTING.md",
        "SGLang HiggsTokenizerAdapter",
        "vLLM HiggsAudioV3TokenizerAdapter",
      ],
      "owner": "Swift should own prompt assembly and validate tags before graph execution.",
      "plain_tts_shape": "<|tts|> <|text|> text tokens <|audio|>",
      "reference_tts_shape": "<|tts|> optional <|ref_text|> text tokens <|ref_audio|> delayed reference placeholders <|text|> target tokens <|audio|>",
    },
    "decoder_prefill_decode": {
      "official_sources": [
        "HiggsMultimodalQwen3ForConditionalGeneration config",
        "SGLang HiggsTTSModel and HiggsTTSModelRunner",
        "vLLM HiggsAudioV3TalkerForConditionalGeneration",
      ],
      "core_ai_candidate": "Qwen3 decoder prefill/decode graph after tokenizer and prompt layout parity exists.",
      "swift_owned_state": "KV-cache lifecycle, request lifecycle, stream policy, and codebook feedback orchestration.",
    },
    "sampler": {
      "official_sources": [
        "SGLang sampler.py",
        "vLLM higgs_audio_v3_talker.py",
      ],
      "owner": "Swift or Accelerate should own policy and testable codebook rows unless a graph boundary clearly wins.",
      "known_constants": [
        "8 codebooks",
        "1026-code vocabulary per codebook",
        "BOC 1024 and EOC 1025 in official serving sources",
        "MusicGen-style delay pattern",
      ],
    },
    "codec_vocoder": {
      "official_sources": [
        "model.safetensors.index.json bundled codec prefix",
        "SGLang audio_codec.py and vocoder_scheduler.py",
        "vLLM higgs_audio_v3_code2wav.py",
      ],
      "highest_risk": "A port without the bundled codec/vocoder tensors is not a useful SpeakSwiftly backend.",
      "core_ai_candidate": "Codec decoder only after codebook-row parity and waveform metadata parity are available.",
    },
    "waveform_post_processing": {
      "official_sources": [
        "SGLang vocoder scheduler",
        "vLLM stage_input_processors/higgs_audio_v3.py",
        "Boson and SGLang serving docs for PCM/WAV output behavior",
      ],
      "apple_framework_owner": "Accelerate for small numeric work, CoreMedia/CoreAudio for timestamped PCM buffers, AVFoundation for files/playback.",
    },
    "output_container": {
      "official_sources": [
        "Boson create-speech API",
        "SGLang Higgs cookbook",
        "vLLM deploy YAML and OpenAI adapter",
      ],
      "known_conflict": "Some docs mention streaming WAV chunks, while current serving docs emphasize raw PCM for streaming.",
    },
  }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  report: dict[str, Any] = {
    "schema_version": 1,
    "created_at_utc": args.created_at_utc or utc_timestamp(),
    "mode": "higgs_audio_v3_official_source_inventory",
    "source_policy": {
      "no_model_weights_downloaded": True,
      "community_mlx_role": "comparison_only_after_official_sources_are_mapped",
    },
    "hugging_face": build_hf_inventory(args.model_id, args.hf_revision),
    "official_serving_sources": {
      "sglang_omni": build_source_inventory(
        args.sglang_repo,
        args.sglang_revision,
        SGLANG_SOURCE_FILES,
      ),
      "vllm_omni": build_source_inventory(
        args.vllm_repo,
        args.vllm_revision,
        VLLM_SOURCE_FILES,
      ),
    },
  }
  report["component_map"] = build_component_map(report)
  return report


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Fetch only official Higgs Audio v3 metadata/source files and emit a "
      "no-weight runtime-constant inventory for SpeakSwiftly maintainers."
    )
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--hf-revision", default=DEFAULT_HF_REVISION)
  parser.add_argument("--sglang-repo", default=DEFAULT_SGLANG_REPO)
  parser.add_argument("--sglang-revision", default=DEFAULT_SGLANG_REVISION)
  parser.add_argument("--vllm-repo", default=DEFAULT_VLLM_REPO)
  parser.add_argument("--vllm-revision", default=DEFAULT_VLLM_REVISION)
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
