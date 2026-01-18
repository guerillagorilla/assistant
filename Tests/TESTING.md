## Purpose

This document defines the **full automated testing strategy** for the voice assistant.

The goal is to ensure that:

- Audio capture is correct and deterministic
    
- Pause and turn handling behave as designed
    
- Speech-to-text accuracy and confidence thresholds are enforced
    
- Latency budgets are met
    
- Failures are handled audibly and in-character
    
- Changes are safe, measurable, and regression-proof
    

Manual listening tests are **not** sufficient and are explicitly non-authoritative.

---

## Core Testing Philosophy

1. **Audio is data**
    
    - Tests inject PCM buffers, not microphones
        
2. **Timing is explicit**
    
    - Every audio frame is timestamped
        
3. **Persona failures are functional failures**
    
4. **Latency is a first-class test signal**
    
5. **If it cannot be tested deterministically, it is not v1-ready**
    

---

## Test Harness Architecture

### Audio Injection Boundary

All audio enters the system through an abstract interface:

`AudioSource  ├── LiveMicSource  └── TestAudioSource`

**TestAudioSource**:

- Accepts PCM buffers
    
- Preserves sample-accurate timestamps
    
- Simulates real-time frame delivery
    
- Supports silence injection and jitter
    

No test depends on OS audio devices.

---

## Test Execution Modes

|Mode|Purpose|CI-Safe|
|---|---|---|
|Unit|Logic & segmentation|Yes|
|Integration|STT + VAD|Yes|
|Regression|Full pipeline|Yes|
|Live Smoke|Human sanity check|No|

CI must never require audio hardware.

---

## Test Categories

---

## 1. Control & State Tests

### CTRL-01 — Push-to-Talk Boundaries

**Input**

- PTT_DOWN at t=0
    
- PTT_UP at t=3000ms
    
- Inject speech audio between
    

**Assertions**

- Audio captured only during hold window
    
- Capture duration ≈ hold duration (±100ms)
    
- STT invoked exactly once
    

---

### CTRL-02 — No Capture Without PTT

**Input**

- Inject speech audio
    
- No PTT events
    

**Assertions**

- No audio frames captured
    
- No STT invocation
    

---

### CTRL-03 — Barge-In Interrupt

**Input**

- Trigger TTS playback
    
- PTT_DOWN at t=500ms
    

**Assertions**

- TTS stops ≤100ms after PTT_DOWN
    
- New audio capture begins immediately
    
- Previous response discarded
    

---

## 2. Signal Integrity Tests

### SIG-01 — Leading Phoneme Preservation

**Input**

- PCM file: `"Test.wav"`
    
- PTT_DOWN at sample 0
    

**Assertions**

- First non-zero sample occurs within pre-roll window
    
- RMS energy in first 50ms > threshold
    

---

### SIG-02 — Trailing Silence Trim

**Input**

- Speech + 2000ms silence
    

**Assertions**

- Trailing silence removed before STT
    
- Final audio length excludes silence
    

---

### SIG-03 — Sample Rate & Format

**Assertions**

- Captured audio matches configured sample rate
    
- No resampling drift or frame loss
    

---

## 3. Pause & Turn Segmentation (ASR Logic)

### SEG-01 — Short Pause Tolerance

**Input**

`"Restart" + 400ms silence + "the service"`

**Assertions**

- Single utterance
    
- Internal pause detected
    
- Final transcript intact
    

---

### SEG-02 — Long Pause, Same Turn

**Input**

`"Restart the" + 1500ms silence + "service"`

**Assertions**

- Still one utterance
    
- No premature finalization
    

---

### SEG-03 — Silence Only

**Input**

- 3000ms zero PCM
    

**Assertions**

- VAD speech duration = 0
    
- STT skipped or empty result
    
- Persona failure response triggered
    

---

## 4. Speech-to-Text Accuracy & Confidence

### STT-01 — Golden Transcript Tests

Each test includes:

- `audio.wav`
    
- `expected.txt`
    

**Assertions**

- Word Error Rate ≤ threshold
    
- Confidence ≥ minimum
    

---

### STT-02 — Confidence Gating

**Input**

- Intentionally unclear speech
    

**Assertions**

- Confidence < threshold
    
- Clarification persona response used
    

---

### STT-03 — Structured Speech

**Input**

- Numbers, identifiers, commands
    

**Assertions**

- Numeric tokens transcribed correctly
    
- Token confidence recorded
    

---

## 5. Latency Budget Tests

### LAT-01 — End-to-End STT Latency

**Measure**

`PTT_UP → STT_FINAL`

**Assertions**

- p50 ≤ 1000ms
    
- p95 ≤ 1500ms
    

---

### LAT-02 — Short Utterance Fast Path

**Input**

- Single-word command
    

**Assertions**

- Latency significantly below average
    
- No artificial buffering delay
    

---

## 6. Failure Injection Tests

### FAIL-01 — Mic Permission Denied

**Simulation**

- Audio source throws permission error
    

**Assertions**

- Spoken error message
    
- Clear remediation guidance
    
- System returns to idle
    

---

### FAIL-02 — STT Engine Crash

**Simulation**

- STT backend throws exception
    

**Assertions**

- Persona failure response
    
- No deadlock
    
- Clean recovery
    

---

### FAIL-03 — Audio Stream Corruption

**Simulation**

- Invalid PCM frames
    

**Assertions**

- Error detected
    
- Capture stopped safely
    
- No undefined behavior
    

---

## 7. Persona Verification Tests

### PER-01 — Persona Filter Enforcement

**Input**

- Raw neutral response text
    

**Assertions**

- Output matches persona rules
    
- No meta language
    
- Verbosity constraints enforced
    

Persona violations are **test failures**.

---

## 8. Deterministic Audio Corpus

Repository structure:

`tests/audio/  ├── clean/  ├── pauses/  ├── silence/  ├── noise/  ├── edge_cases/  └── expected/`

Each audio file includes:

- Expected transcript
    
- Confidence range
    
- Expected segmentation metadata
    

---

### Current Corpus (Implemented)

`Tests/VPACoreTests/AudioCorpus/` includes a tiny WAV corpus and manifest used by `AudioCorpusTests`:

- `manifest.json` with expected VAD trim results
- `silence_1s.wav`, `tone_0p5s.wav`, `tone_0p2s_trailing_silence_1s.wav`
- `whisper_samples/jfk.wav`, `whisper_samples/mm1_16k.wav` (converted from whisper.cpp samples)
- `whisper_samples/gb0_16k.wav`, `whisper_samples/hp0_16k.wav` (long corpus, gated by `VPA_LONG_CORPUS=1`)

Optional STT golden test (whisper-cli):

```
VPA_STT_CORPUS=1 \
VPA_STT_WHISPER_CLI=/path/to/whisper-cli \
VPA_STT_MODEL=/path/to/model.bin \
swift test
```

Use `VPA_LONG_CORPUS=1` to include long samples in both VAD and STT corpus tests.

This is CI-safe and deterministic. It can be expanded with speech samples and
`expectedTranscript` fields when adding backend comparison tests.

## 9. Metrics & Instrumentation

Every test run collects:

- Capture duration
    
- Trimmed silence duration
    
- STT latency
    
- Confidence scores
    
- Failure counts
    

Metrics are local-only and never transmitted.

---

## 10. CI Policy

CI must:

- Run all deterministic tests
    
- Fail on latency regressions
    
- Fail on persona violations
    
- Fail on WER increases
    

Live audio tests are excluded from CI.

---

## 11. Definition of “Passing”

Audio & STT are considered verified when:

- All automated tests pass
    
- Latency budgets are met
    
- No persona regressions occur
    
- No privacy violations are detected
    

---

## 12. What Is Explicitly Not Tested

- Subjective voice appeal
    
- Humor quality
    
- Personal preference tuning
    
- Accent adaptation (future work)
    

---

## Final Note

If a change:

- Cannot be tested deterministically
    
- Weakens latency guarantees
    
- Breaks persona consistency
    

It does **not** belong in v1.

---

## Current Test Scaffold (Implemented)

- `Tests/VPACoreTests/TestSupport.swift` provides deterministic stubs for `AudioCaptureService`, `STTEngine`, `Responder`, `TTSEngine`, `AudioPlayer`, and helpers to build PCM buffers.
- `Tests/VPACoreTests/ControlStateTests.swift` covers PTT boundaries and barge-in stop behavior without live audio.
- `Tests/VPACoreTests/SignalVADTests.swift` validates leading/trailing silence trimming and silence-only handling using `SimpleVADSegmenter`.

To extend:

- **STT backends**: add tests that swap in a backend-specific stub or CLI wrapper that reads canned WAVs in `tests/audio/` and compares to golden transcripts.
- **Latency metrics**: add a controllable clock or metric stub and assert `MetricsSink.record(latency:)` values with injected timestamps.
- **Audio corpus**: place canonical WAVs + expected transcripts under `tests/audio/` and feed them through `TestAudioCaptureService`.
