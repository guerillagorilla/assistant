This folder contains a tiny deterministic WAV corpus for CI-safe tests.

- `manifest.json` defines expected VAD outcomes for each file.
- Files are 16-bit mono PCM WAV at 16 kHz.

To add new samples:
1. Add a WAV file here.
2. Add a manifest entry with expectedSegments and expectedTrimmedMs.
3. Keep files short (<2s) to keep tests fast.

For backend STT comparisons, add a `expectedTranscript` field and
run the optional STT corpus test (to be enabled via env var).

Whisper.cpp samples are included under `whisper_samples/` and converted
to 16 kHz mono WAV for deterministic VAD checks.

Long samples are marked with `"long": true` in `manifest.json` and are
skipped unless `VPA_LONG_CORPUS=1` is set.

Only items with `"stt": true` participate in STT corpus tests.

Current expected transcripts were generated with:

```
Scripts/generate_expected_transcripts.py \
  --cli whisper.cpp/build/bin/whisper-cli \
  --model whisper.cpp/models/ggml-base.en.bin \
  --language en --beam-size 5 --best-of 5 --temperature 0.0 \
  --include-long --overwrite --no-gpu
```

To run STT corpus tests (whisper-cli):

```
VPA_STT_CORPUS=1 \
VPA_STT_WHISPER_CLI=/path/to/whisper-cli \
VPA_STT_MODEL=/path/to/model.bin \
swift test
```

Optional tuning:

- `VPA_STT_LANGUAGE` (default: `en`)
- `VPA_STT_BEAM_SIZE`
- `VPA_STT_BEST_OF`
- `VPA_STT_TEMPERATURE`
- `VPA_STT_MAX_WER` (default: `0.20`)

To include long corpus in STT tests:

```
VPA_LONG_CORPUS=1 VPA_STT_CORPUS=1 ...
```
