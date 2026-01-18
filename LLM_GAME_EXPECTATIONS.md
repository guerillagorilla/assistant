# LLM Game Expectations (Chrummy Join/Play)

This document defines **deterministic expectations** for how the LLM-assisted voice agent should behave when interacting with the Chrummy game. It is **join/play specific** and does not cover general chat.

## Scope

Applies to:
- Joining a room (bot WebSocket at `/api/bot`)
- Creating a room (via `join` with `create: true`)
- Fetching rules from `/api/rules` after join/create
- LLM use for gameplay decisions when state is received

Out of scope:
- General conversational replies
- Non‑game commands
- UI or browser client behavior

## Terminology

- **Room code**: two 4‑letter words, e.g., `MOON STAR`
- **Bot endpoint**: `ws://localhost:8000/api/bot`
- **Rules endpoint**: `http://localhost:8000/api/rules`

## Required Behavioral Expectations

### 1) Join Room (User‑Provided)

**Trigger phrases (examples):**
- “Join room MOON STAR”
- “Let’s play a game MOON STAR”

**Expected behavior:**
- Parse **two 4‑letter words** from the transcript.
- Send to bot WS:
  ```json
  {"action":"join","room":"MOON STAR","seat":1}
  ```
- Fetch rules from `/api/rules` immediately after sending join.
- Speak a deterministic confirmation, e.g.:
  - “Joining room MOON STAR. Try not to embarrass me.”

**If missing/invalid code:**
- Speak clarification:
  - “Room code missing. Say two four-letter words.”
- Do **not** send WS join.
- Do **not** fetch rules.

### 2) Create Room (User‑Provided)

**Trigger phrases (examples):**
- “Create room MOON STAR”
- “Make room MOON STAR”

**Expected behavior:**
- Parse **two 4‑letter words** from the transcript.
- Send to bot WS:
  ```json
  {"action":"join","room":"MOON STAR","create":true}
  ```
- Fetch rules from `/api/rules` immediately after sending create.
- Speak a deterministic confirmation, e.g.:
  - “Creating room MOON STAR. Try not to fumble.”

**If missing/invalid code:**
- Speak clarification:
  - “Room code missing. Say two four-letter words.”
- Do **not** send WS create.
- Do **not** fetch rules.

### 3) Rules Fetch

**When:** After join or create.

**Expected behavior:**
- Fetch `http://localhost:8000/api/rules`
- Cache rules in memory for the LLM prompt.
- Speak one of:
  - “Rules loaded. I understand.”
  - “Rules missing. Try again.” (empty/invalid response)

### 4) LLM Prompt Injection (Gameplay)

When gameplay decisions are made (e.g., on `your_turn` events), the LLM prompt **must include**:
- The cached rules JSON (or an empty string if not available)
- Current state data (hand, round, discard top, etc.)
- Explicit instruction to return a JSON action

Example requirement:
```
RULES_JSON=<cached rules json>
STATE=<current turn state>
Return JSON: {"draw":"deck|discard","meld":true|false,"discard":"7H"}
```

## Non‑Negotiables

- **No room creation without explicit two‑word code.**
- **No random room codes.**
- **Join/create are deterministic (LLM is not used).**
- **Rules fetch is always attempted after join/create.**

## Validation Checklist

- [ ] "Join room MOON STAR" sends `{action:"join",room:"MOON STAR",seat:1}`
- [ ] "Create room MOON STAR" sends `{action:"join",room:"MOON STAR",create:true}`
- [ ] Missing room → clarification, no WS message
- [ ] Rules fetched after join/create
- [ ] Rules cache injected into LLM prompt for gameplay

