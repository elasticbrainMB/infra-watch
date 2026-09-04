# Review tiers — F, E and D

**Written 2026-08-07 at C3.7 sub-step 2.1.** Deliverable of `W-track-build-guide.md`'s **W1**.

> **PROVISIONAL. Read this before using the file.**
>
> **It was written against a rough pass, not a classification.** Matt tiered the existing
> sub-steps quickly and found the tiers workable. That is the whole evidence behind the
> definitions below.
>
> **It has not been applied to a real chunk.** No sub-step has yet been assigned a tier in a
> build guide and run under it. Nothing here has been tested by use.
>
> **It is expected to move.** `records\W2-cursory-pass.md` records that some items are expected
> to change tier on a closer look, and a definition that mis-sorts a real sub-step is the
> definition that is wrong, not the sub-step.

---

## What a tier is

**A tier says how much of the loop a sub-step needs.** Today every sub-step gets the same full
round trip; most do not need it.

**Assignment is a property of the sub-step, not the chunk.** A single chunk carries all three.

---

## Tier F — full gate

**You read raw output and decide before the next step runs.**

- Chunk boundaries, and every stop condition
- **Any judgment about what a measured number means.** This is the C1 grounding-test lesson: the
  model retrieved the timer value correctly and drew the wrong tactical conclusion from it.
  **Retrieval is checkable; meaning is not**
- Any first-time operation whose failure mode is unknown
- Anything destructive or hard to reverse
- Anything marked `[VERIFY]`

## Tier E — evidence-only

**The step runs to completion. You review the evidence afterward, out of the loop.**

- Scripted steps with a known-good expected output
- Any operation already run once cleanly at Tier F
- File authoring against an existing template
- Recording operations — byte counts, SHAs, baselines

## Tier D — delegated

**Runs and self-verifies. You read a summary line unless it flags.**

- Read-only discovery
- Idempotent checks
- Formatting and mechanical transforms

---

## The two rules that make tiering safe

**Promotion rule.** A step moves **F → E only after it has run cleanly once at F.** Nothing
starts at E on the strength of an argument that it should be fine.

**Demotion rule.** Any step that produced a **surprise — any surprise, including a benign one —
returns to F for its next run.** Cheap to apply, and it is the thing that stops tier drift.

---

## The three-state review outcome

**Taken from W7 as drafted in `W-track-build-guide.md`. W7 has not run**, and these three states
have not been used to review anything. They are here because W1's deliverable names them, not
because they are settled.

One question, asked of what the step produced:

> **Does what changed match what the step authorized?**

| Outcome | Meaning |
|---|---|
| **Matches** | Scope and change agree |
| **Exceeds scope** | Something changed that the step did not name |
| **Cannot tell from the evidence** | What was produced is too thin to answer |

**The third state is the one that does the work.** It catches a weak evidence trail instead of
rubber-stamping it, and it is the state a reviewer working from a summary will never produce.

---

## What this file does not carry

**Tier E depends on an evidence bundle that does not exist yet.** W5 defines the bundle and W6
makes it automatic; neither has run, and `evidence\` is not on disk. **Until then Tier E has no
artefact to review**, so assigning a sub-step to E today would mean reviewing whatever happened
to get written down — which is the arrangement tiering exists to replace.

**Nothing here changes what is permitted.** The enforced rules are in `caddy\.claude\settings.json`.
A tier says how closely a step is watched, never what it may touch.
