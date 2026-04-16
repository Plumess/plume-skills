---
name: code-review
description: "Use when user asks to review code, audit quality, or evaluate an implementation — '代码审查', '审一下这段代码', 'review this', 'code review', '检查代码质量', 'audit', '看看这个实现'. Scans against Clean Code / Clean Architecture / The Pragmatic Programmer with P0/P1/P2 severity grading. Also handles receiving review feedback ('我收到了一个 review', 'how should I respond to this reviewer')."
---

# Code Review — Structured Audit

Structured code review based on three canonical sources:

- **Clean Code** (Robert C. Martin, 2008)
- **Clean Architecture** (Robert C. Martin, 2017)
- **The Pragmatic Programmer** (Hunt & Thomas, 20th Anniversary Ed., 2019)

Two modes:

- **AUDIT mode** (default) — review code against the principles.
- **FEEDBACK mode** — help evaluate review comments received from others (critical assessment, not blind agreement).

## Severity Rubric

| Grade | Alias | Meaning | Action |
|---|---|---|---|
| **P0** | Critical | Violates core architectural / safety / correctness principle | Block merge; fix first |
| **P1** | Important | Significantly harms maintainability or introduces latent risk | Fix before next release |
| **P2** | Minor | Style / preference / minor inconsistency | Opportunistic fix |

## AUDIT Mode Process

**Step 1 — Scope negotiation**

Ask the user:
- Target: specific files, directory, git diff, or whole project?
- Focus: full audit across all principles, or specific axes (e.g. "only architecture" / "only naming")?
- Style constraints: any project conventions that override book defaults?

**Step 2 — Read target code** with Glob + Read. Prefer `git diff` for PR reviews.

**Step 3 — Apply principles** (below). For each finding, produce:

```
### [P-rank] <book-abbrev>-<id>: <principle name>
- **Definition**: <one-line definition>
- **Source**: <book> <chapter/topic>
- **Location**: <file:line[-line]> [(`function_name`)]
- **Violation**:
  ```<lang>
  <code snippet, 3–10 lines>
  ```
- **Why it matters**: <1–2 sentences>
- **Fix**: <concrete suggested change; can include a code example>
```

**Step 4 — Present findings grouped by severity descending** (P0 first). Ask which P0/P1 items to fix now.

## Principles Checked

Non-exhaustive — pick relevant subset per review. Each entry: **Definition / Source / Scan cue**.

### Clean Code

- **CC-1 Meaningful Names** (Ch. 2) — Names reveal intent, avoid disinformation, make meaningful distinctions, pronounceable, searchable. Scan: single-letter identifiers outside short loops; cryptic abbreviations; misleading plurals; Hungarian notation in modern languages.

- **CC-2 Functions Do One Thing** (Ch. 3) — Small, single-purpose, single level of abstraction, few arguments (≤3 ideal), no side effects. Scan: functions > 30 lines; > 3 parameters; mixing IO + computation + validation; boolean flag arguments.

- **CC-3 Comments** (Ch. 4) — Good code is self-documenting; comments explain why, not what; no commented-out code; no misleading comments. Scan: redundant restatements; commented-out blocks; stale TODOs without tracking.

- **CC-4 Formatting** (Ch. 5) — Vertical openness between concepts; related code close together; dependent functions near each other. Scan: files > 500 lines; functions defined far from their only caller.

- **CC-5 Objects and Data Structures** (Ch. 6) — Objects hide data and expose behavior; data structures expose data with no behavior; don't mix. Scan: data classes with behavior methods that leak internals; getters/setters on hybrid objects.

- **CC-6 Error Handling** (Ch. 7) — Use exceptions not return codes; don't return null; don't pass null; write try-catch-finally first; don't wrap system exceptions without adding context. Scan: silent `except:` / `except Exception: pass`; null returns from non-Optional APIs; try-catch swallowing root cause.

- **CC-7 Boundaries** (Ch. 8) — Wrap third-party APIs at system boundary. Scan: direct use of external library types leaking into business logic.

- **CC-8 Unit Tests** (Ch. 9) — Tests should be Fast, Independent, Repeatable, Self-validating, Timely (FIRST). One assert per test ideal. Scan: tests with > 5 asserts; tests depending on external services; flaky time-sensitive assertions.

- **CC-9 Classes** (Ch. 10) — Small, cohesive, SRP. Scan: classes > 200 lines; classes with > 7 public methods; classes whose methods share only 1–2 fields.

### Clean Architecture

- **CA-1 Single Responsibility Principle** (Ch. 7) — A module has one, and only one, reason to change. Scan: classes changed in unrelated business contexts within git history; classes handling both persistence and business rules.

- **CA-2 Open/Closed Principle** (Ch. 8) — Open for extension, closed for modification. Scan: switch/if-elif chains growing with each new type; hardcoded type dispatch without polymorphism.

- **CA-3 Liskov Substitution** (Ch. 9) — Subtypes must be substitutable for base types. Scan: subclasses that raise `NotImplementedError` on base methods; subclasses that weaken preconditions.

- **CA-4 Interface Segregation** (Ch. 10) — Clients shouldn't depend on methods they don't use. Scan: fat interfaces; classes implementing methods with `pass` or raise.

- **CA-5 Dependency Inversion / Dependency Rule** (Ch. 11, Ch. 22) — High-level policy doesn't depend on low-level detail; both depend on abstractions. Source dependencies point inward toward higher-level policy. Scan: domain / business layer importing infrastructure (DB, HTTP, framework) concretely; business rules instantiating concrete driver classes.

- **CA-6 Boundaries** (Ch. 17) — Draw boundaries where volatility differs; keep stable inside. Scan: unstable concrete types leaking across module boundaries; no interface at layer seams.

- **CA-7 Entities vs Use Cases vs Interface Adapters vs Frameworks & Drivers** (Ch. 22 diagram) — Clean separation by concentric circles. Scan: HTTP decorators on business entities; database models used as domain entities.

### The Pragmatic Programmer (20th Anniversary Edition)

- **PP-1 DRY — Don't Repeat Yourself** (Topic 9) — Every piece of knowledge has one authoritative representation. Scan: repeated literal constants; copy-pasted logic blocks; duplicate validation regex; parallel "similar but not quite the same" branches.

- **PP-2 Orthogonality** (Topic 10) — Eliminate effects between unrelated things; changes in one component don't ripple. Scan: tight coupling; shared mutable global state; circular dependencies; modifying one module requires modifying five others.

- **PP-3 Reversibility** (Topic 11) — No final decisions; keep design flexible where it matters. Scan: hardcoded vendor choices in core logic (DB, queue, auth provider); single-path implementations for contested choices.

- **PP-4 Tracer Bullets** (Topic 12) — Get a minimal end-to-end path working, then fill in. Scan: branches with half-built layers blocking deployment; mocked-but-forgotten integration points.

- **PP-5 Design by Contract** (Topic 23) — State preconditions, postconditions, invariants. Scan: public APIs without documented input/output contracts; functions that silently accept invalid input.

- **PP-6 Crash Early** (Topic 24) — Fail fast at point of detection. Scan: bare `except`; silent fallback to defaults on error; continued execution after invariant violation; errors swallowed and logged without propagation.

- **PP-7 Assertive Programming** (Topic 25) — Use assertions to enforce invariants; keep for production selectively, never for business-critical checks that `-O` may strip. Scan: invariant checks written as comments instead of assertions; business validation done via `assert`.

- **PP-8 How to Balance Resources** (Topic 26) — Who allocates, deallocates. Scan: opened file handles / DB connections / locks without clear release point; missing `with` / `defer` / `try-finally`.

- **PP-9 Decoupling / Tell, Don't Ask** (Topic 28) — Don't query state then decide externally; tell objects what to do. Scan: long `getX().getY().doZ()` chains; "train-wreck" accessor chains; query-then-mutate idioms leaking invariants.

- **PP-10 Refactoring** (Topic 40) — Refactor early, often, surgically. Scan: large swaths of unclean code with no surgical refactor history; big-bang refactor PRs.

### Grading Heuristics

- A violation **confined to a helper function** used once → typically P2.
- A violation **in a public API, domain entity, or shared library** → typically P1.
- A violation **that enables a bug, data loss, or security hole** → P0 regardless of location.
- A violation **in a test file** → P2 unless it's test infrastructure everyone depends on.
- Project-specific style conventions **override book defaults** when user flags them up-front.

## FEEDBACK Mode Process

When the user pastes review comments received from others:

**Step 1 — Parse each comment** into: (a) claim, (b) justification (if given), (c) suggested change.

**Step 2 — Evaluate rigorously**. For each:
- Is the claim technically correct? Check the actual code.
- Is the reasoning sound? Don't accept appeals to authority.
- Is the suggested change better than the original? Compare against the principles above.

**Step 3 — Categorize**:
- **Agree & act** — correct, sound, better suggestion.
- **Agree with nuance** — correct but suggestion has tradeoffs to negotiate.
- **Disagree with evidence** — claim is wrong or suggestion is worse; cite principles / tests.
- **Defer to author preference** — style matter, reviewer is expressing preference not principle.

**Step 4 — Draft responses** for each comment. Evidence-based; not performative agreement, not blind defensiveness.

## Report Template (AUDIT mode)

```markdown
# Code Review — <target>

**Scope**: <files / diff>
**Date**: <YYYY-MM-DD>
**Principle coverage**: <books / axes applied>

## Summary

- Files: N
- Findings: P0 × a · P1 × b · P2 × c
- Compliance highlights: <brief>
- Overall verdict: <ready to merge / needs P0 fixes / needs architectural rework>

## Findings

<groups sorted by severity desc, within each sorted by file/line>

## Compliance highlights (brief)

<what the code does well>

## Recommended next steps

1. <P0 fix list>
2. <P1 fix list>
3. <optional P2 for this pass>
```

## Output Persistence

Apply **Ask Before Persist** (Tier 0 gate) before writing a review report to disk. For the default save path, see `using-plume` → Project output default paths. State the path and wait for user confirmation before writing. Inline report in chat is fine without a save step.
