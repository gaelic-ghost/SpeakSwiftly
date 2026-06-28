#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "huggingface-hub>=0.36.0",
# ]
# ///
"""Probe Core ML conversion for the Qwen3-TTS 12 Hz speech-tokenizer decoder."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi


DEFAULT_MODEL_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
DEFAULT_UPSTREAM_COMMIT = "022e286b98fbec7e1e916cb940cdf532cd9f488e"
DEFAULT_FIXTURE_PATH = "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json"


def local_path_pattern(path: Path) -> re.Pattern[str]:
  return re.compile(re.escape(str(path)) + r"/[^\"'\n )]*")


LOCAL_PATH_PATTERNS = [
  (local_path_pattern(Path.home()), "<local-home-path>"),
  (local_path_pattern(Path("/" + "private") / "tmp"), "<local-temp-path>"),
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


def load_fixture(path: Path) -> dict[str, Any]:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception as error:
    raise RuntimeError(f"Unable to read decoder fixture JSON at '{path}'.") from error


def fixture_audio_codes(fixture: dict[str, Any]) -> list[list[int]]:
  try:
    return fixture["encoded"]["audio_codes"]
  except KeyError as error:
    raise RuntimeError("Decoder fixture does not contain encoded.audio_codes.") from error


def fixture_audio_codes_dtype(fixture: dict[str, Any]) -> str:
  return fixture.get("encoded", {}).get("audio_codes_dtype", "int64")


def padded_code_shape(args: argparse.Namespace, fixture: dict[str, Any]) -> list[int]:
  audio_codes = fixture_audio_codes(fixture)
  original_code_steps = len(audio_codes)
  quantizer_count = len(audio_codes[0]) if audio_codes else 0
  requested_code_steps = args.pad_code_steps or original_code_steps

  if requested_code_steps < original_code_steps:
    raise RuntimeError(
      f"--pad-code-steps {requested_code_steps} is shorter than the fixture's "
      f"{original_code_steps} code steps. Use a bucket that preserves the full fixture."
    )

  return [1, requested_code_steps, quantizer_count]


def samples_per_code_step(fixture: dict[str, Any]) -> int | None:
  audio_codes = fixture_audio_codes(fixture)
  original_code_steps = len(audio_codes)
  sample_count = fixture.get("decoded", {}).get("sample_count")
  if not original_code_steps or sample_count is None:
    return None

  if sample_count % original_code_steps != 0:
    return None

  return sample_count // original_code_steps


def expected_output_sample_count(args: argparse.Namespace, fixture: dict[str, Any]) -> int | None:
  step_samples = samples_per_code_step(fixture)
  if step_samples is None:
    return fixture.get("decoded", {}).get("sample_count")
  return padded_code_shape(args, fixture)[1] * step_samples


def padding_report(args: argparse.Namespace, fixture: dict[str, Any]) -> dict[str, Any]:
  audio_codes = fixture_audio_codes(fixture)
  requested_code_steps = padded_code_shape(args, fixture)[1]
  original_code_steps = len(audio_codes)
  return {
    "original_code_steps": original_code_steps,
    "requested_code_steps": requested_code_steps,
    "pad_value": -1,
    "padded_step_count": requested_code_steps - original_code_steps,
    "samples_per_code_step": samples_per_code_step(fixture),
    "valid_output_sample_count": fixture.get("decoded", {}).get("sample_count"),
    "padded_output_sample_count": expected_output_sample_count(args, fixture),
  }


def padded_audio_codes_array(args: argparse.Namespace, fixture: dict[str, Any], np: Any) -> Any:
  audio_codes = np.asarray(fixture_audio_codes(fixture), dtype=np.int64)
  requested_code_steps = padded_code_shape(args, fixture)[1]
  if audio_codes.shape[0] == requested_code_steps:
    return audio_codes[None, :, :]

  padded_codes = np.full(
    (requested_code_steps, audio_codes.shape[1]),
    -1,
    dtype=np.int64,
  )
  padded_codes[: audio_codes.shape[0], :] = audio_codes
  return padded_codes[None, :, :]


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


def ensure_model_download_allowed(args: argparse.Namespace, inventory: dict[str, Any]) -> None:
  total_mb = (inventory["total_size_bytes"] or 0) / 1_000_000
  if not args.allow_model_download:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because it may download about {total_mb:.1f} MB. "
      "Rerun with --allow-model-download when you intentionally want the conversion probe."
    )

  if total_mb > args.max_download_mb:
    raise RuntimeError(
      f"Refusing to load '{args.model_id}' because its file inventory is about {total_mb:.1f} MB, "
      f"which is above --max-download-mb {args.max_download_mb:.1f}."
    )


def qwen_source_from_args(args: argparse.Namespace) -> Path:
  source = args.qwen_source or os.environ.get("QWEN3_TTS_SOURCE")
  if not source:
    raise RuntimeError(
      "The Core ML decoder conversion probe needs Qwen3-TTS source code. "
      "Pass --qwen-source /path/to/Qwen3-TTS or set QWEN3_TTS_SOURCE."
    )

  source_path = Path(source).expanduser().resolve()
  tokenizer_file = source_path / "qwen_tts" / "inference" / "qwen3_tts_tokenizer.py"
  if not tokenizer_file.is_file():
    raise RuntimeError(
      f"The Qwen3-TTS source path '{source_path}' does not contain qwen_tts/inference/qwen3_tts_tokenizer.py."
    )

  return source_path


def sanitize_local_paths(value: Any) -> Any:
  if isinstance(value, dict):
    return {key: sanitize_local_paths(item) for key, item in value.items()}
  if isinstance(value, list):
    return [sanitize_local_paths(item) for item in value]
  if isinstance(value, str):
    sanitized = value
    for pattern, replacement in LOCAL_PATH_PATTERNS:
      sanitized = pattern.sub(replacement, sanitized)
    return sanitized
  return value


def build_preflight_report(args: argparse.Namespace, fixture: dict[str, Any], inventory: dict[str, Any]) -> dict[str, Any]:
  code_shape = padded_code_shape(args, fixture)

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
      "fixture_path": str(args.fixture),
    },
    "model_file_inventory": inventory,
    "conversion_target": {
      "stage": "speech_tokenizer_decoder",
      "wrapper_mode": args.wrapper_mode,
      "input_name": "audio_codes",
      "input_shape": code_shape,
      "input_dtype": fixture_audio_codes_dtype(fixture),
      "expected_output_shape": [1, expected_output_sample_count(args, fixture)],
      "expected_output_sample_rate": fixture.get("decoded", {}).get("sample_rate"),
      "minimum_deployment_target": args.minimum_deployment_target,
      "convert_to": "mlprogram",
      "padding": padding_report(args, fixture),
    },
    "next_command": (
      "uv run --python 3.12 "
      "--with 'numpy>=2.0.0' --with 'torch==2.7.0' --with 'torchaudio==2.7.0' "
      "--with 'transformers==4.57.3' "
      "--with 'librosa>=0.11.0' --with 'soundfile>=0.13.0' --with 'sox>=1.5.0' "
      "--with 'onnxruntime>=1.23.0' --with 'einops>=0.8.0' "
      "--with 'coremltools>=8.3.0,<10' "
      "scripts/repo-maintenance/coreml-qwen3tts/convert-speech-tokenizer-decoder-coreml.py "
      "--no-preflight-only --capture-mode export --export-decomposed --wrapper-mode fixed_16q_static_mask "
      "--verify-coreml-prediction --coreml-compute-units cpuOnly "
      "--qwen-source /path/to/Qwen3-TTS --allow-model-download "
      f"--pad-code-steps {code_shape[1]} "
      "--output .local/coreml-qwen3tts/qwen3tts-speech-tokenizer-decoder-conversion.json "
      "--mlpackage-output .local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder.mlpackage"
    ),
  }


def build_runtime_report(args: argparse.Namespace, fixture: dict[str, Any], inventory: dict[str, Any]) -> dict[str, Any]:
  try:
    import coremltools as ct
    import numpy as np
    import torch
  except Exception as error:
    raise RuntimeError(
      "Runtime Core ML conversion needs Python 3.11 or 3.12 plus numpy, torch, transformers, and coremltools. "
      "Use the preflight next_command or add those packages with uv --with."
    ) from error

  qwen_source = qwen_source_from_args(args)
  ensure_model_download_allowed(args, inventory)

  sys.path.insert(0, str(qwen_source))
  try:
    from qwen_tts import Qwen3TTSTokenizer
  except Exception as error:
    raise RuntimeError(
      f"Unable to import Qwen3TTSTokenizer from '{qwen_source}'. "
      f"Underlying import error: {error!r}"
    ) from error

  class UpstreamDecoderWrapper(torch.nn.Module):
    def __init__(self, decoder: torch.nn.Module):
      super().__init__()
      self.decoder = decoder

    def forward(self, audio_codes):
      clamped_codes = torch.clamp(audio_codes, min=0)
      wav = self.decoder(clamped_codes.transpose(1, 2)).squeeze(1)
      return wav

  class Fixed16QuantizerDecoderWrapper(torch.nn.Module):
    def __init__(self, decoder: torch.nn.Module):
      super().__init__()
      self.quantizer = decoder.quantizer
      self.pre_conv = decoder.pre_conv
      self.pre_transformer = decoder.pre_transformer
      self.upsample = decoder.upsample
      self.decoder = decoder.decoder

    def decode_rvq(self, rvq, codes):
      quantized = None
      for idx in range(rvq.n_q):
        layer = rvq.vq.layers[idx]
        layer_codes = codes[:, idx, :]
        layer_quantized = layer.decode(layer_codes)
        quantized = layer_quantized if quantized is None else quantized + layer_quantized
      return rvq.output_proj(quantized)

    def forward(self, audio_codes):
      codes = torch.clamp(audio_codes, min=0).transpose(1, 2)
      semantic = self.decode_rvq(self.quantizer.rvq_first, codes[:, :1, :])
      acoustic = self.decode_rvq(self.quantizer.rvq_rest, codes[:, 1:, :])
      hidden = semantic + acoustic
      hidden = self.pre_conv(hidden).transpose(1, 2)
      hidden = self.pre_transformer(inputs_embeds=hidden).last_hidden_state
      hidden = hidden.permute(0, 2, 1)
      for blocks in self.upsample:
        for block in blocks:
          hidden = block(hidden)
      wav = hidden
      for block in self.decoder:
        wav = block(wav)
      return wav.clamp(min=-1, max=1).squeeze(1)

  class Fixed16StaticMaskDecoderWrapper(Fixed16QuantizerDecoderWrapper):
    def run_pre_transformer(self, hidden):
      transformer = self.pre_transformer
      hidden = transformer.input_proj(hidden)
      batch_size = hidden.shape[0]
      sequence_length = hidden.shape[1]
      cache_position = torch.arange(sequence_length, device=hidden.device)
      position_ids = cache_position.unsqueeze(0).expand(batch_size, sequence_length)
      mask = torch.full(
        (1, 1, sequence_length, sequence_length),
        torch.finfo(hidden.dtype).min,
        dtype=hidden.dtype,
        device=hidden.device,
      )
      mask = torch.triu(mask, diagonal=1)
      position_embeddings = transformer.rotary_emb(hidden, position_ids)
      for decoder_layer in transformer.layers:
        hidden = decoder_layer(
          hidden,
          attention_mask=mask,
          position_ids=position_ids,
          past_key_values=None,
          use_cache=False,
          cache_position=cache_position,
          position_embeddings=position_embeddings,
        )
      hidden = transformer.norm(hidden)
      return transformer.output_proj(hidden)

    def forward(self, audio_codes):
      codes = torch.clamp(audio_codes, min=0).transpose(1, 2)
      semantic = self.decode_rvq(self.quantizer.rvq_first, codes[:, :1, :])
      acoustic = self.decode_rvq(self.quantizer.rvq_rest, codes[:, 1:, :])
      hidden = semantic + acoustic
      hidden = self.pre_conv(hidden).transpose(1, 2)
      hidden = self.run_pre_transformer(hidden)
      hidden = hidden.permute(0, 2, 1)
      for blocks in self.upsample:
        for block in blocks:
          hidden = block(hidden)
      wav = hidden
      for block in self.decoder:
        wav = block(wav)
      return wav.clamp(min=-1, max=1).squeeze(1)

  audio_codes = padded_audio_codes_array(args, fixture, np)
  torch_codes = torch.from_numpy(audio_codes)

  tokenizer = Qwen3TTSTokenizer.from_pretrained(args.model_id)
  upstream_decoder = UpstreamDecoderWrapper(tokenizer.model.decoder).eval()
  if args.wrapper_mode == "fixed_16q":
    decoder = Fixed16QuantizerDecoderWrapper(tokenizer.model.decoder).eval()
  elif args.wrapper_mode == "fixed_16q_static_mask":
    decoder = Fixed16StaticMaskDecoderWrapper(tokenizer.model.decoder).eval()
  else:
    decoder = upstream_decoder

  report: dict[str, Any] = {
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
      "coremltools_version": ct.__version__,
      "torch_version": torch.__version__,
    },
    "conversion_target": {
      "stage": "speech_tokenizer_decoder",
      "wrapper_mode": args.wrapper_mode,
      "input_name": "audio_codes",
      "input_shape": list(audio_codes.shape),
      "input_dtype": str(audio_codes.dtype),
      "minimum_deployment_target": args.minimum_deployment_target,
      "convert_to": "mlprogram",
      "compute_precision": args.compute_precision,
      "capture_mode": args.capture_mode,
      "export_decomposed": args.export_decomposed if args.capture_mode == "export" else False,
      "padding": padding_report(args, fixture),
    },
    "trace": {
      "status": "not_started",
      "capture_mode": args.capture_mode,
      "strict": args.export_strict if args.capture_mode == "export" else False,
      "check_trace": False,
    },
    "conversion": {
      "status": "not_started",
      "mlpackage_output": str(args.mlpackage_output) if args.mlpackage_output else None,
    },
    "output_match": {
      "status": "not_started",
      "compute_units": args.coreml_compute_units,
    } if args.verify_coreml_prediction else None,
  }

  with torch.inference_mode():
    upstream_output = upstream_decoder(torch_codes).detach().cpu().numpy()
    torch_output = decoder(torch_codes).detach().cpu().numpy()

  report["conversion_target"].update(
    {
      "torch_output_shape": list(torch_output.shape),
      "torch_output_min": float(torch_output.min()),
      "torch_output_max": float(torch_output.max()),
      "torch_output_mean": float(torch_output.mean()),
      "torch_output_rms": float(np.sqrt(np.mean(np.square(torch_output)))),
      "upstream_max_abs_diff": float(np.max(np.abs(torch_output - upstream_output))),
    }
  )

  try:
    with torch.inference_mode():
      if args.capture_mode == "export":
        captured_model = torch.export.export(decoder, (torch_codes,), strict=args.export_strict)
        if args.export_decomposed:
          captured_model = captured_model.run_decompositions({})
      else:
        captured_model = torch.jit.trace(decoder, torch_codes, strict=False, check_trace=False)
    report["trace"] = {
      "status": "succeeded",
      "capture_mode": args.capture_mode,
      "strict": args.export_strict if args.capture_mode == "export" else False,
      "export_decomposed": args.export_decomposed if args.capture_mode == "export" else False,
      "check_trace": False,
    }
  except Exception as error:
    report["trace"] = {
      "status": "failed",
      "capture_mode": args.capture_mode,
      "strict": args.export_strict if args.capture_mode == "export" else False,
      "export_decomposed": args.export_decomposed if args.capture_mode == "export" else False,
      "check_trace": False,
      "error_type": type(error).__name__,
      "error_message": str(error),
    }
    return report

  try:
    target = getattr(ct.target, args.minimum_deployment_target)
    compute_precision = ct.precision.FLOAT32 if args.compute_precision == "float32" else ct.precision.FLOAT16
    mlmodel = ct.convert(
      captured_model,
      convert_to="mlprogram",
      minimum_deployment_target=target,
      compute_precision=compute_precision,
      inputs=[
        ct.TensorType(
          name="audio_codes",
          shape=audio_codes.shape,
          dtype=np.int64,
        )
      ],
      outputs=[ct.TensorType(name="audio_values")],
    )
    if args.mlpackage_output:
      args.mlpackage_output.parent.mkdir(parents=True, exist_ok=True)
      mlmodel.save(str(args.mlpackage_output))
    report["conversion"] = {
      "status": "succeeded",
      "mlpackage_output": str(args.mlpackage_output) if args.mlpackage_output else None,
    }
    if args.verify_coreml_prediction:
      try:
        compute_units = {
          "all": ct.ComputeUnit.ALL,
          "cpuOnly": ct.ComputeUnit.CPU_ONLY,
          "cpuAndGPU": ct.ComputeUnit.CPU_AND_GPU,
          "cpuAndNeuralEngine": ct.ComputeUnit.CPU_AND_NE,
        }[args.coreml_compute_units]
        prediction_model = (
          ct.models.MLModel(str(args.mlpackage_output), compute_units=compute_units)
          if args.mlpackage_output
          else mlmodel
        )
        prediction = prediction_model.predict({"audio_codes": audio_codes.astype(np.int32)})
        coreml_output = np.asarray(prediction["audio_values"])
        delta = coreml_output - torch_output
        report["output_match"] = {
          "status": "succeeded",
          "compute_units": args.coreml_compute_units,
          "coreml_output_shape": list(coreml_output.shape),
          "coreml_output_dtype": str(coreml_output.dtype),
          "coreml_output_min": float(coreml_output.min()),
          "coreml_output_max": float(coreml_output.max()),
          "coreml_output_mean": float(coreml_output.mean()),
          "coreml_output_rms": float(np.sqrt(np.mean(np.square(coreml_output)))),
          "max_abs_diff": float(np.max(np.abs(delta))),
          "mean_abs_diff": float(np.mean(np.abs(delta))),
        }
      except Exception as error:
        report["output_match"] = {
          "status": "failed",
          "compute_units": args.coreml_compute_units,
          "error_type": type(error).__name__,
          "error_message": str(error),
        }
  except Exception as error:
    report["conversion"] = {
      "status": "failed",
      "error_type": type(error).__name__,
      "error_message": str(error),
      "mlpackage_output": str(args.mlpackage_output) if args.mlpackage_output else None,
    }

  return report


def build_report(args: argparse.Namespace) -> dict[str, Any]:
  fixture_path = args.fixture
  if not fixture_path.is_absolute():
    fixture_path = package_root() / fixture_path

  fixture = load_fixture(fixture_path)
  inventory = repo_file_inventory(args.model_id, args.revision)

  if args.preflight_only:
    return build_preflight_report(args, fixture, inventory)

  return build_runtime_report(args, fixture, inventory)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description=(
      "Probe Core ML conversion for the Qwen3-TTS 12 Hz speech-tokenizer decoder. "
      "Default preflight mode avoids model loading and conversion."
    )
  )
  parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
  parser.add_argument("--revision", default=None)
  parser.add_argument("--upstream-commit", default=DEFAULT_UPSTREAM_COMMIT)
  parser.add_argument("--fixture", type=Path, default=Path(DEFAULT_FIXTURE_PATH))
  parser.add_argument("--qwen-source", default=None)
  parser.add_argument(
    "--preflight-only",
    action=argparse.BooleanOptionalAction,
    default=True,
  )
  parser.add_argument("--allow-model-download", action="store_true")
  parser.add_argument("--max-download-mb", type=float, default=1_024.0)
  parser.add_argument(
    "--minimum-deployment-target",
    default="macOS15",
    choices=["macOS12", "macOS13", "macOS14", "macOS15"],
  )
  parser.add_argument(
    "--compute-precision",
    default="float32",
    choices=["float16", "float32"],
  )
  parser.add_argument(
    "--wrapper-mode",
    default="upstream",
    choices=["upstream", "fixed_16q", "fixed_16q_static_mask"],
  )
  parser.add_argument(
    "--capture-mode",
    default="trace",
    choices=["trace", "export"],
  )
  parser.add_argument(
    "--export-strict",
    action=argparse.BooleanOptionalAction,
    default=False,
  )
  parser.add_argument(
    "--export-decomposed",
    action=argparse.BooleanOptionalAction,
    default=False,
  )
  parser.add_argument("--verify-coreml-prediction", action="store_true")
  parser.add_argument(
    "--coreml-compute-units",
    default="cpuOnly",
    choices=["all", "cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine"],
  )
  parser.add_argument("--created-at-utc", default=None)
  parser.add_argument(
    "--pad-code-steps",
    type=int,
    default=None,
    help="Pad fixture audio_codes with -1 to this fixed code-step bucket before conversion.",
  )
  parser.add_argument("--output", type=Path, default=None)
  parser.add_argument("--mlpackage-output", type=Path, default=None)
  return parser.parse_args()


def write_report(report: dict[str, Any], output: Path | None) -> None:
  report = sanitize_local_paths(report)
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
