# infra-watch — update-execution, Sitting 1 handoff (Node read-only proof)

**Paste the block below as the first message of a Claude Code sitting in the
infra-watch project.** It executes §9 of `PLAN-update-execution-v1.md` — the
Node-first, read-only proof of the update → verify → resolve → rollback flow —
on the Windows host, which the Cowork session that wrote the design cannot
reach. Written 2026-09-08, after the design's seven forks were settled (§8).

---

infra-watch — update-execution, Sitting 1 (Node read-only proof).

BEFORE YOU ACT. Disk is authoritative; this prompt is not. Read, in order:
CLAUDE.md, STATE.md, PLAN-infra-watch-v1.md, PLAN-update-execution-v1.md
(the settled design — §9 is your task list, §8 the locked decisions), TIERS.md,
config\inventory.json, and scripts\post-discord.ps1 (inherited — do NOT rewrite).

Standing discipline (from CLAUDE.md): run commands verbatim and show raw output,
not summaries. STOP conditions are hard stops — do not route around a failure.
Discovery before any change. [VERIFY] means read the live host, never cached
knowledge or a document. Use `pwsh -File`, never `powershell` (that launches 5.1).
Write every file UTF-8 without a BOM.

Guardrails you must not cross: this project never applies an update — you generate
and verify only; every install/rollback step stays Matt's to run by hand. Never
widen the deny-list. scripts\ edits are ask-gated; only records\ and config\ are
Edit-allowed. No new model call in anything you build — last run (20260907-080001)
already tripped the $0.25/run cap.

Work through the chunks below. End each with a markdown chunk record + status
summary. Stop at the marked gates.

CHUNK 1 — close Node's [VERIFY] facts (read-only).
- From the live host, determine Node's actual install/update mechanism
  (nvm-windows / winget / MSI / other) and binary path. Read it off the host; do
  not guess or lift it from any doc. Confirm the running version with
  `node --version` and `npm --version`.
- If the mechanism cannot be established read-only, STOP and report — do not
  assume one.
- Add a `deployment` block to ONLY the `node` entry in config\inventory.json
  (Edit-allowed) recording: mechanism, binary path, whether an in-place update
  replaces vs side-installs, and the rollback source for the prior 24.x. Touch no
  other entry. Show the diff. Gate: pause for Matt if anything was ambiguous.

CHUNK 2 — write the Node runbook (records\, allow-listed).
- From §4d, write a Node runbook: in-place update within the installed major
  (read the current target from the latest successful run's records, not from
  memory), the verify steps, rollback = reinstall prior 24.x, 7-day artifact
  retention (Decision D). Seed it ONLY from a current assessment — if
  records\assessments\node.md's run_id isn't the latest successful run for node,
  refuse and say so ("use the fact, not a proxy"). Save per repo convention
  (e.g. records\runbooks\node.md). Report it.

CHUNK 3 — read-only snapshot + verify step (scripts\ — ask-gated; expect the prompt).
- Write one script: Phase 0 captures node/npm versions and any build baseline;
  Phase 2 re-captures and diffs. Template-driven, NO model call, strictly
  read-only (no install, no mutating command).
- Pass/fail posts to #decisions via the inherited post-discord.ps1 (do not
  rewrite it; disk is source of truth, Discord a mirror — the step must succeed
  even if Discord is unreachable). For this dry run, gate posting behind an
  explicit flag that is OFF, so no live traffic hits Matt's real channels.
- Report the script; confirm before any live run if the ask-gate requires it.

CHUNK 4 — dry-run the read-only halves (Tier-F first run).
- Run Phase 0 then Phase 2 against the current, unchanged Node — nothing applied —
  and confirm they capture and diff correctly (a no-op diff). Show raw output.
- STOP here. Do NOT apply the real Node update — that is Matt's hand action
  (§9 step 5) and needs his explicit go. Report readiness.

CLOSE. If a tracked fact changed (the node deployment block), update STATE.md per
its §6 rule and add a SESSION-LOG.md entry (newest first). Commit (git commit is
ask-gated) with a message naming the sitting.

STOP conditions (hard, report and wait): Node's mechanism unresolvable read-only;
any command that would mutate a live component; any impulse to widen the deny-list;
any model-cap trip; a stale assessment seeding the runbook.
