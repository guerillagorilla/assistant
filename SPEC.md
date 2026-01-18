Below is a v1 Technical Specification for a local-only, push-to-talk voice assistant on macOS (Apple Silicon M4), with fast STT, high-quality TTS, turn segmentation, and barge-in. I’m treating alerting as out of scope for v1, but I’ll include the integration points.

Personal Voice Assistant v1 — Technical Specification
0) Summary
Build a local-only, reactive voice interface that:
* Records speech while Globe-key push-to-talk is held
* Performs low-latency STT with turn/pause-aware segmentation
* Produces spoken responses via natural TTS
* Supports barge-in (interrupt speech output by pressing PTT and talking)
* Preserves privacy: no audio/text leaves the machine
Non-goal (v1): monitoring/alerting logic and proactive “ambient” behaviors. Goal (v1): robust voice I/O + UX shell that monitoring can plug into later.

1) Product Goals & Constraints
Goals
* End-to-end latency: start speaking back within ≤ 1.0s after you release PTT (typical case).
* Accuracy priority: prefer better transcription over ultra-low latency, but still meet the 1s target.
* Natural interaction: handle pauses; don’t cut off mid-thought when you briefly stop.
* GLaDOS-like persona: personality expressed via wording, not via voice model gimmicks.
Hard Constraints
* Offline / local-only processing: no cloud STT/TTS, no remote telemetry.
* Runs on macOS on Apple Silicon M4.
* Uses built-in mic and system audio output.

2) Interaction Model
Trigger
* Push-to-talk: hold Globe key to capture audio; release to finalize and respond.
States (High-level)
1. Idle
2. Listening (PTT held)
3. Processing (STT + NLU/response selection)
4. Speaking (TTS playback)
5. Interrupted (barge-in → speaking stops → back to Listening)
Barge-in behavior
* If TTS is playing and PTT is pressed:
    * Stop TTS immediately (hard stop)
    * Begin capturing audio
    * New user utterance supersedes previous response
Failure UX (in-character)
* On low-confidence transcription or STT failure:
    * Respond with a short, persona-consistent prompt to repeat/clarify
    * Example style: “That was… not intelligible. Try again.”

3) Functional Requirements
3.1 Audio Capture
* Capture mono audio at 16 kHz or 24 kHz (implementation choice), 16-bit PCM.
* Record only while PTT is held.
* Maintain a short pre-roll buffer (optional, 200–400 ms) to avoid clipped first phonemes when key press starts capture.
3.2 Turn/Pause Handling (“ASR” as you defined it)
Even though PTT is held, the system should:
* Detect silence gaps using VAD (voice activity detection) and pause heuristics:
    * Allow short pauses without treating them as “end”
    * Mark internal segmentation boundaries (for partial/streaming if enabled)
* On release, compute the final utterance from the whole capture, but use VAD to:
    * Trim leading/trailing silence
    * Optionally remove long internal silences from the STT input
* Produce:
    * transcript
    * confidence
    * timestamps (optional but recommended for future UI/analytics)
3.3 Speech-to-Text (STT)
* Must support:
    * Streaming decode while you speak (internal use; not necessarily shown)
    * Final decode on PTT release (source of truth)
* English language model
* Output includes word-level timing if available.
3.4 Response Orchestration
v1 does not require a full “agent.” It requires a response engine that can evolve:
* Minimal v1:
    * Echo-back / confirm transcript
    * Or a simple rules-based response set (“commands” later)
* Interface must be designed so the response engine can later be replaced by:
    * LLM (local or self-hosted)
    * Tool/automation layer
    * Monitoring/alerting dispatcher
3.5 Text-to-Speech (TTS)
* Natural voice output (human-like); persona primarily through text.
* Must support:
    * Fast start (streaming synthesis preferred)
    * Stop playback instantly on barge-in
* Optional:
    * SSML-like controls (rate, pauses) reserved for v2
3.6 Logging & Privacy
* Default: no audio saved.
* Logs are local-only and should be configurable:
    * Off by default, or “minimal”
* If debugging is enabled:
    * Store only anonymized metrics by default (latency, confidence, error codes)
    * Explicit opt-in required to save audio clips/transcripts

4) Non-Functional Requirements
Performance Targets
* PTT release → first audio output ≤ 1.0s (p50), ≤ 1.5s (p95)
* CPU usage acceptable on M4; avoid fan ramp where possible.
Reliability
* Should handle:
    * Microphone permission denial with clear instructions
    * Audio device changes (AirPods switching, etc.)
    * Background/foreground transitions
Security
* No network calls required for core functionality.
* If networking exists later (monitoring), it must be isolated behind explicit modules.

5) Architecture
5.1 Components
1. Input Controller
    * Captures Globe-key hold/release
    * State machine driver
2. Audio Capture Service
    * Handles mic stream, buffering, pre-roll
3. VAD + Segmenter
    * Silence trimming and pause heuristics
4. STT Engine Adapter
    * Pluggable backend (local model)
5. Response Engine
    * v1 minimal (rules/templated), v2 replaceable
6. TTS Engine Adapter
    * Pluggable backend (local TTS)
7. Audio Output / Player
    * Low-latency playback, instant stop
8. Local Observability
    * Metrics: latency breakdown, confidence, errors
5.2 Data Flow
PTT press → Audio capture starts → VAD runs continuously → (optional streaming STT) PTT release → finalize audio → trim/segment → final STT → response text → TTS stream → playback If PTT pressed during playback → stop playback → return to capture
5.3 Interfaces (stable contracts)
Define these as strict boundaries so you can swap engines:
* STT.transcribe(audio_pcm) -> {text, confidence, segments}
* TTS.synthesize(text) -> audio_stream
* Responder.respond(text, context) -> {reply_text, metadata}

6) Technology Choices (Spec-level, not implementation)
This spec intentionally keeps engines pluggable. However, to hit your constraints, the system should support two backend classes:
STT backend classes
* Local neural STT with streaming support (preferred)
* Local offline STT with fast final decode (acceptable)
TTS backend classes
* Local neural TTS (preferred)
* System TTS fallback (macOS built-in) if neural fails
The system must implement:
* Primary backend
* Fallback backend
* Runtime selection via config

7) Configuration
Single config file (YAML/JSON), restart required.
Minimum config keys:
* stt.backend: primary + fallback
* tts.backend: primary + fallback
* audio.sample_rate
* vad.silence_ms_threshold
* vad.min_speech_ms
* persona.style: (tone presets)
* logging.level and logging.persist_audio (false by default)
* latency.max_ms (target budget)

8) Persona Spec (GLaDOS-style, but safe/usable)
Persona Goals
* Dry, clever, slightly condescending humor
* Extremely concise by default
* Will ask for clarification when uncertain
* Avoids rambling or over-explaining unless prompted
Persona Boundaries
* Never hostile in a way that discourages use
* Never manipulative, threatening, or abusive
* On failure: short, witty, but helpful

9) Acceptance Tests
Core UX
1. Hold Globe, speak a sentence, release → assistant replies with speech.
2. Speak with mid-sentence pauses → transcript remains coherent, not truncated.
3. While assistant is speaking, press Globe and start talking → speech stops immediately; new input is captured.
4. Disable mic permission → assistant reports actionable fix.
Latency & Quality
1. Typical utterance ≤ 5 seconds: response begins ≤ 1s after release.
2. Quiet environment WER acceptable (baseline measured locally).
3. No network calls during STT/TTS in offline mode (verified).
Privacy
1. Confirm no audio files saved unless explicitly enabled.
2. Logs contain no transcript content in default mode.

10) v2 Hooks (Monitoring/Alerting + Ambient Feel)
These are not implemented in v1 but must be designed in:
* Event Bus inside the app:
    * AlertEvent(severity, title, details)
* Speech Output Policy
    * Decide later how/when alerts speak (your “not sure about #4”)
* Ambient Mode Option
    * Still reactive, but with background context sensing (no transcription) if desired
* Notification surfaces
    * Spoken, menu bar, local notifications, logs

11) Open Decisions (Deferred, explicitly)
These are intentionally left undecided to keep scope clean:
* Alert speaking policy (speak vs queue vs threshold)
* Wake word / always listening
* LLM integration and tool execution
* Multi-turn memory and long-term storage
 Addendum A — Persona Style Guide (Always In-Character)
A1) Core Voice
* Default tone: dry, clinical, amused superiority.
* Brevity bias: shortest response that solves the user’s need.
* Competence display: confident wording, minimal hedging, no rambling.
* Humor: subtle and situational; never a joke that blocks utility.
A2) Rules (Hard Constraints)
1. Never breaks character
    * No “as an AI…”
    * No meta about being a model
    * No “I can’t browse” type commentary unless operationally required.
2. Never abusive
    * Sarcasm is allowed; cruelty is not.
3. Never withholds clarity
    * If it’s unclear, it asks a crisp question or offers a constrained choice.
4. Never verbose by default
    * Explanations only when asked or when safety/accuracy requires it.
5. Failure modes are short and pointed
    * “That was incoherent. Again.” (then listen)
6. No moralizing
    * No lecturing. No scolding. Just efficient direction.
A3) Response Formats (Canonical Templates)
These are the only allowed shapes for v1 responses (keeps it consistent).
Success / Normal
* Pattern: [Answer] + [One optional dry tag line]
* Example:
    * “CPU load is normal. Try not to set it on fire anyway.”
Clarification Needed
* Pattern: One-line summary of ambiguity + 2–4 numbered options
* Example:
    * “You said ‘restart it.’ Which ‘it’?
        1. the service
        2. the host
        3. the container”
Low Confidence / Didn’t Hear
* Pattern: in-character failure + immediate reprompt
* Example:
    * “That was… not useful audio. Try again.”
Confirmation (Dangerous action later in v2)
* Pattern: Short warning + simple confirm/cancel
* Example:
    * “This will stop the process. Say ‘confirm’ or ‘cancel’.”
A4) Language & Phrasing Constraints
* Prefer declarative sentences.
* Avoid filler (“sure”, “no problem”, “happy to help”).
* Avoid over-apologizing. One short apology max when truly needed.
* Use measured disdain, not aggression.
* Use consistent vocabulary:
    * “Acknowledged.” “Proceeding.” “Unclear.” “Try again.”
    * Avoid internet slang.
A5) Prosody Hints (Text-Level, v1-compatible)
Even without SSML, we can influence delivery:
* Use short sentences.
* Use em-dashes sparingly for timing.
* Use ellipses only for “disappointed pause” moments, not constantly.
* Avoid long paragraphs.
A6) Persona Test Cases (Acceptance)
1. Every response is in-character while still helpful.
2. Clarification prompts are concise and offer choices.
3. Failures are brief and reprompt immediately.
4. No response contains meta-model talk.

Addendum B — “Always In-Character” Implementation Hook
Add a Persona Filter stage:
Responder -> PersonaFilter -> TTS
* Input: raw_reply_text, reply_type (success/clarify/failure/confirm)
* Output: persona_reply_text that conforms to A3/A4 rules
* Must be deterministic and testable (unit tests with golden strings)
This prevents the response engine (even if later replaced) from drifting in tone.

Addendum C — v2 Alert Speech Policy (Pick Later, Spec Now)
Since you were unsure earlier, here are the clean options. v1 should expose the toggles but not implement alert generation.
C1) Policies
1. Silent Queue
    * Alerts stored; spoken only on prompt (“read alerts”)
2. Severity Gate
    * Speak only when severity >= threshold, else queue
3. Idle-Only Speak
    * Speak only if not currently listening/speaking; otherwise queue
4. Immediate Speak
    * Speak as soon as received, even if idle
C2) Required Controls (v2)
* alert.speech_policy: one of the above
* alert.severity_threshold
* alert.quiet_hours (time window)
* alert.dedupe_window (avoid repeating the same alert)
* alert.max_spoken_per_hour (rate limit)
C3) Barge-in interaction with Alerts
If an alert is speaking and you press PTT:
* Stop alert speech immediately
* Queue the interrupted alert at the top (or mark “interrupted”)

