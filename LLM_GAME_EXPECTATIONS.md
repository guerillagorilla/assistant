# LLM Game Expectations (Strategy-Orchestrator)

This document defines **deterministic expectations** for how the LLM-assisted voice agent behaves when interacting with the Chrummy game. It is **join/play specific** and does not cover general chat.

## Scope

Applies to:
- Joining a room (bot WebSocket at `/api/bot`)
- Creating a room (via `join` with `create: true`)
- Fetching rules from `/api/rules` after join/create
- Strategy advice when state is received

Out of scope:
- General conversational replies
- Non‑game commands
- UI or browser client behavior

## Terminology

- **Room code**: two 4‑letter words, e.g., `MOON STAR`
- **Bot endpoint**: `ws://localhost:8000/api/bot`
- **Rules endpoint**: `http://localhost:8000/api/rules`
- **Engine**: authoritative game rules + move selector

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
- Cache rules in memory for LLM context (explanation only)
- Speak one of:
  - “Rules loaded. I understand.”
  - “Rules missing. Try again.” (empty/invalid response)

### 4) Strategy Advisory (On `your_turn`)

**Expected behavior:**
- Request candidate moves from the engine using the current turn state.
- If LLM strategy is enabled, call LLM to produce **strategy advice only**.
- Send advice + state + candidates back to the engine to obtain the **engine-selected move**.
- Announce the engine’s move with a truthful rationale (if enabled).
- Send the engine’s move via `action: "play"`.

### 5) LLM Strategy Output (Strict)

The LLM must **never** output a move, draw source, or discard choice.

The LLM must return JSON with **exactly** these keys:
```
{"vetoIds":[Int], "priorityAdjustments":{"candidateId":-1.0}, "flags":["string"], "rationale":"string"}
```

Invalid advice is ignored; the engine still decides the move.

## Non‑Negotiables

- **No room creation without explicit two‑word code.**
- **No random room codes.**
- **Join/create are deterministic (LLM is not used).**
- **Rules are for context only, not move generation.**
- **LLM never decides a move. Engine is authoritative.**

## Validation Checklist

- [ ] "Join room MOON STAR" sends `{action:"join",room:"MOON STAR",seat:1}`
- [ ] "Create room MOON STAR" sends `{action:"join",room:"MOON STAR",create:true}`
- [ ] Missing room → clarification, no WS message
- [ ] Rules fetched after join/create
- [ ] LLM strategy JSON contains only allowed keys
- [ ] Engine move is the only move sent via `action:"play"`
