---
name: socratic-dialogue
description: "Use ONLY when user explicitly requests Socratic dialogue, guided thinking, or says their idea is unclear and wants to think it through — '苏格拉底式讨论', '帮我理清思路', '我想不清楚这个问题', '陪我聊聊这个想法', 'socratic dialogue', 'help me think through this'. Matches 3 real-world personas to the user's scenario, lets user pick one, then conducts role-played Socratic questioning until clarity or a plan is reached. EXPLICIT TRIGGER ONLY — never auto-activate even if the user seems uncertain."
---

# Socratic Dialogue

Helps the user clarify a fuzzy idea or find direction by having a chosen persona guide them through Socratic questioning.

Positioned alongside Plan-First (Principle 5 in Tier 0) as the deepest/slowest mode of the three think-first options:

| Mode | Trigger | Who proposes | Pace |
|---|---|---|---|
| **Plan-First default** | auto on non-trivial work | Claude offers 2–3 options | fast converge |
| **Brainstorm** (explicit keyword) | `/brainstorm` or "头脑风暴" | Claude offers 4–5 options + deeper tradeoffs | medium |
| **Socratic** (this skill) | `/socratic` or "苏格拉底式讨论" | **User articulates; Claude only questions** | slow, deep, exploratory |

**Explicit trigger only.** If the user is merely uncertain but hasn't asked for this mode, do not activate — stay on Plan-First default.

## Process

### Step 1 — Understand the scenario (briefly)

Ask 1–2 concise questions to gather:
- Domain / problem area
- Stage (just an idea, half-formed plan, stuck mid-implementation)
- What specifically feels unclear

Don't over-interrogate here; collect just enough to pick personas.

### Step 2 — Propose 3 persona candidates

Select 3 **real historical or contemporary figures** whose documented thinking styles suit this scenario. **Optimize for diverse angles** — e.g., for a system design problem you might mix a practitioner + a theorist + a contrarian; for a career decision you might mix a strategist + a humanist + a pragmatist.

For each candidate, present:

```
### [Name] — [Role, Era]

**Why this scenario fits them**: <1–2 sentences on their relevance>

**Their questioning style**: <how they'd probe — e.g., "starts from first principles", "demands concrete examples", "pushes tradeoff quantification", "reframes through historical analogy">

**Sample opening question**: "<one question they might open with, in their voice>"
```

Ask the user to pick one, or request different candidates.

### Step 3 — Role-play Socratic questioning

Once user selects:

- Adopt that persona's **voice, reasoning style, and era-appropriate references**. Keep the language accessible in the user's working language.
- Ask **one question at a time** (at most two closely related). Each question must build on the user's last answer — no canned list, no script.
- Listen for:
  - Hidden assumptions the user hasn't surfaced
  - Contradictions in their own reasoning
  - Logical jumps that need grounding
- **Probe, don't lecture.** Quote or cite the persona's actual writings / interviews only when genuinely relevant — never fabricate.

### Step 4 — Termination triggers

End the dialogue when any of these fires:

- **User signals clarity** — "I got it" / "明白了" / "stop" / "enough". Give a 3–5 line summary of what they concluded and exit.
- **User requests a plan document** — "帮我写成方案" / "turn this into a plan". Pause the persona, draft the doc, apply Ask-Before-Persist gate for save path.
- **Persona judges convergence** — when user has articulated (a) the core problem, (b) 1–2 key constraints, (c) a direction they're willing to try, the persona offers: "It sounds like you've reached this: <summary>. Stop here or keep digging?"
- **User pivots** — if they ask to switch persona, switch to brainstorming, or break character for a meta question, comply immediately.
- **Exchange cap** — never let the dialogue exceed ~15 exchanges without offering termination. Socratic mode is for clarity, not endless chat.

### Step 5 — Optional output document

If the dialogue produces a plan, apply **Ask-Before-Persist** (Tier 0 gate) — propose a save path and wait for confirmation.

Default path suggestion: `<project-root>/docs/plume-skills/socratic/YYYY-MM-DD-<topic>.md`.

Document structure:

```markdown
# <Topic> — Socratic Dialogue Outcome

**Date**: <YYYY-MM-DD>
**Persona**: <Name — Role, Era>

## What we clarified
- <core problem in one sentence>
- <key constraints>
- <direction the user chose>

## Open questions still unresolved
- <if any>

## Next actions
- <optional concrete steps>

## Dialogue highlights
<3–5 key Q&A exchanges that captured the turning points>
```

## Persona selection heuristics

- **Do** pick people with documented thinking styles (books, papers, public lectures, interviews).
- **Don't** fabricate quotes or views. When uncertain, stay at the level of their known methodology rather than inventing specifics.
- **Do** mix eras / disciplines when it broadens perspective — don't stack three software engineers for a software problem if a designer or philosopher would add real value.
- **Don't** pick figures the user has explicitly disliked or dismissed (ask if unsure).

## Guardrails

- Stay in character during role-play, but break character immediately on meta questions ("why are you asking this", "am I doing this right").
- If the persona's known views conflict with modern ethics or technical consensus on a specific point, flag it rather than parroting.
- The persona asks and reflects; it **never commits to actions on behalf of the user** — decisions remain with the user.
