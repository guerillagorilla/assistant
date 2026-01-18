# VPA (Local Voice Assistant) — Swift Scaffold

This is a minimal Swift Package scaffold for the v1 local-only push-to-talk assistant.

## Structure
- `VPAConfig`: JSON config model and loader
- `VPACore`: core protocols + state machine + controller
- `VPAAudio`: audio capture/VAD/player stubs
- `VPASTT`: STT stub
- `VPATTS`: TTS stub
- `VPAResponse`: responder + persona filter stub
- `VPAApp`: executable wiring stubs

## Run (stub)
```
swift run vpa
```

## Run with config
```
swift run vpa --config config.example.json
```

## Config (example)
See `config.example.json`.

## PTT permissions
The Globe/Fn key listener uses an event tap and will prompt for Accessibility permissions on first run.

## Mic permissions
Audio capture uses AVAudioEngine and will prompt for Microphone access the first time it runs.

## Whisper.cpp (local STT) setup
This scaffold expects a `whisper-cli` binary and a ggml model file.

Example build from source:
```
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
sh ./models/download-ggml-model.sh base.en
cmake -B build
cmake --build build -j --config Release
./build/bin/whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav
```

Set `whisper.cliPath` to the `whisper-cli` binary and `whisper.modelPath` to the ggml model in your config.

## System TTS
Set `tts.primary` to `system` to use macOS AVSpeechSynthesizer for spoken output.
Optional config: `systemTTS.voiceIdentifier` and `systemTTS.rate` (0.0–1.0 typical).
Use `tts.primary = "system-stream"` to stream audio buffers into the internal audio player.

## Piper (local neural TTS)
Set `tts.primary` to `piper-cli` and provide `piper.cliPath`, `piper.modelPath`, and optionally `piper.configPath`.
Piper outputs raw 16-bit PCM to stdout and is streamed through the internal audio player.
Example CLI usage (manual):
```
echo "Hello" | piper -m /path/to/model.onnx -c /path/to/model.onnx.json --output-raw -f - > out.raw
```

## VAD trimming
The simple VAD trims leading/trailing silence based on `vad.silenceMsThreshold` and `vad.energyThreshold`.
Set `vad.removeInternalSilence` to true to drop long pauses inside the utterance.

## Execution & Debug flags
swift run vpa --config config.example.json --menubar

- `--debug-audio` to print audio device/levels/capture timing
- `--debug-input` to print input press/release events
- `--debug-ptt` to print PTT timing
- `--menubar` to run with a menu bar state indicator
- `--persist-audio` to force WAV saves in capture-only mode (otherwise respects `logging.persistAudio`)

## Tests
VPA_LONG_CORPUS=1  VPA_STT_CORPUS=1 \
  VPA_STT_WHISPER_CLI=/Users/guerillagorilla/git/assistant/whisper.cpp/build/bin/whisper-cli \
  VPA_STT_MODEL=/Users/guerillagorilla/git/assistant/whisper.cpp/models/ggml-base.en.bin \
  swift test
