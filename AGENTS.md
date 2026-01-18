## Project Overview

This project is a **local-only, reactive voice assistant** for macOS (Apple Silicon), designed for **push-to-talk interaction**, **low-latency speech recognition**, and **always in-character spoken responses**.

The assistant’s long-term purpose is **monitoring and alerting**, but **v1 scope is strictly audio capture + speech-to-text + speech output**, with robust turn handling and barge-in support.

This repository prioritizes:

- Deterministic behavior
    
- Testability
    
- Privacy (no data leaves the machine)
    
- Clear architectural boundaries
    

---

## Core Design Principles (Non-Negotiable)

1. **Local-only processing**
    
    - No audio, transcripts, or telemetry may leave the machine.
        
    - Cloud APIs are not permitted.
        
2. **Reactive only**
    
    - The assistant does not speak unless explicitly triggered.
        
    - Push-to-talk is the only interaction trigger in v1.
        
3. **Always in-character**
    
    - All spoken output must follow the defined persona.
        
    - No meta commentary, no “as an AI” phrasing, no breaks in tone.
        
4. **Latency-aware**
    
    - End-to-end responsiveness is a primary success metric.
        
    - Every component must expose timing hooks for measurement.
        
5. **Test-first architecture**
    
    - Audio capture and STT must be testable without a microphone.
        
    - All logic must be verifiable via deterministic tests.
        

---

## System Scope (v1)

### In Scope

- Push-to-talk input handling
    
- Audio capture with pre-roll buffering
    
- Voice activity detection (VAD)
    
- Pause-aware turn segmentation
    
- Speech-to-text (STT)
    
- Text-to-speech (TTS)
    
- Barge-in (interrupt TTS via PTT)
    
- Persona enforcement
    
- Local logging & metrics (opt-in)
    

### Explicitly Out of Scope

- Monitoring logic
    
- Alert generation
    
- Proactive or ambient speech
    
- Wake-word detection
    
- Cloud connectivity
    
- Multi-user or speaker identification
    
- GUI beyond minimal system integration
    

---

## Architectural Boundaries

Agents **must not blur these layers**:

`Input (PTT, audio)   ↓ Audio Capture   ↓ VAD + Segmentation   ↓ STT Engine (pluggable)   ↓ Response Engine (minimal in v1)   ↓ Persona Filter (mandatory)   ↓ TTS Engine (pluggable)   ↓ Audio Output`

Each stage must:

- Have a clear interface
    
- Be mockable
    
- Be independently testable
    

---

## Audio & STT Rules

- Microphones are **never** tested directly.
    
- All automated tests inject deterministic PCM audio.
    
- Audio timing must be preserved with explicit timestamps.
    
- Silence trimming and pause handling must be measurable, not heuristic-only.
    

Any change to:

- VAD thresholds
    
- Pause timing
    
- Segmentation logic  
    **must be accompanied by test updates**.
    

---

## Persona Enforcement

Persona is **not optional** and **not cosmetic**.

All output passes through a **Persona Filter** that:

- Shapes tone
    
- Limits verbosity
    
- Enforces response formats
    
- Handles failure cases consistently
    

Agents must not:

- Embed persona logic directly in STT or TTS
    
- Hardcode jokes or phrases outside the persona layer
    

Persona violations are considered **functional bugs**, not style issues.

---

## Testing Expectations

### Required Test Categories

- Control/state tests (PTT behavior)
    
- Signal integrity tests (no clipped phonemes)
    
- Pause & segmentation tests
    
- STT accuracy & confidence tests
    
- Latency budget tests
    
- Failure injection tests
    

### Test Philosophy

- Deterministic > subjective
    
- Numeric thresholds > “sounds right”
    
- CI-safe tests first, live-audio tests last
    

No feature is considered complete without automated verification.

---

## Privacy & Logging

Default behavior:

- No audio persisted
    
- No transcripts stored
    
- Minimal metrics only
    

Debug modes must be:

- Explicitly enabled
    
- Clearly labeled
    
- Fully local
    

Agents must never introduce “temporary” logging that violates privacy guarantees.

---

## Configuration

- Single configuration file (YAML or JSON)
    
- Restart required for changes
    
- Sensible defaults
    
- No environment-variable sprawl
    

Configuration must not be required for basic operation.

---

## Change Discipline

When modifying core behavior:

- Update tests first or alongside code
    
- Preserve interface contracts
    
- Do not expand scope without explicit approval
    

When in doubt:

- Prefer smaller, composable changes
    
- Leave clear TODOs rather than speculative features
    

---

## What Success Looks Like

A successful v1 assistant:

- Responds reliably within latency targets
    
- Handles pauses naturally
    
- Never talks unless asked
    
- Never breaks character
    
- Can be refactored without fear due to strong tests
    

If an agent is unsure whether a change aligns with this vision, **stop and ask**.

---

## Final Note to Agents

This project values **discipline over cleverness**.

If you find yourself:

- Adding features “because it’s easy”
    
- Bypassing tests for speed
    
- Making assumptions about future alerting logic
    

You are probably going in the wrong direction.

Proceed deliberately.