#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def parse_whisper_stdout(raw: str) -> str:
    parts = []
    for line in raw.splitlines():
        if "]" in line:
            _, after = line.split("]", 1)
            trimmed = after.strip()
            if trimmed:
                parts.append(trimmed)
        else:
            trimmed = line.strip()
            if trimmed:
                parts.append(trimmed)
    return " ".join(parts).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate expected transcripts using whisper-cli.")
    parser.add_argument("--manifest", default="Tests/VPACoreTests/AudioCorpus/manifest.json")
    parser.add_argument("--cli", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--language", default="en")
    parser.add_argument("--beam-size", type=int)
    parser.add_argument("--best-of", type=int)
    parser.add_argument("--temperature", type=float)
    parser.add_argument("--include-long", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--no-gpu", action="store_true")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    base_dir = manifest_path.parent
    items = json.loads(manifest_path.read_text())

    for item in items:
        if item.get("long") and not args.include_long:
            continue
        if item.get("expectedTranscript") and not args.overwrite:
            continue

        wav_path = base_dir / item["file"]
        cmd = [args.cli, "-m", args.model, "-f", str(wav_path), "-l", args.language]
        if args.beam_size:
            cmd += ["--beam-size", str(args.beam_size)]
        if args.best_of:
            cmd += ["--best-of", str(args.best_of)]
        if args.temperature is not None:
            cmd += ["--temperature", str(args.temperature)]
        if args.no_gpu:
            cmd += ["-ng"]

        print(f"transcribing {item['id']}...")
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(proc.stderr.strip() or f"whisper-cli failed on {item['id']}")
        text = parse_whisper_stdout(proc.stdout)
        item["expectedTranscript"] = text

    manifest_path.write_text(json.dumps(items, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
