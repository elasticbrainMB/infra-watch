# SESSION-LOG.md — recap log for future chat threads

**What this file is.** Append-only. One dated entry per session, written so
a new chat thread can get caught up fast without reading the full
transcript. `STATE.md` is the current-facts snapshot (what's true *now*,
overwritten as facts change); this file is the narrative history behind
it — what happened, in what order, and why. Newest entry at the top.

---

## 2026-09-04 — v1 built, all three sittings complete, weekly automation live

**Starting point:** a written handoff (`prompts\infra-watch.md`) with the
full v1 definition, pasted as the first message of the first Claude Code
sitting in this project. Repo was freshly initialized with `CLAUDE.md`,
`STATE.md`, `TIERS.md`, and the scripts/permissions copied over from the
caddy project — nothing else built yet.

**Sitting 1 — inventory and collection** (commit `b336544`):
- Wrote `PLAN-infra-watch-v1.md` as the project's own charter.
- Resolved all `[VERIFY]` items against the live host, not from memory or
  cached knowledge — every `releases_from` repo path checked against the
  GitHub API directly. OpenClaw's repo in particular came from the running
  container's own `org.opencontainers.image.source` label, per the plan's
  hard rule for that component (the project name collides with unrelated
  repos and SEO content, so guessing was never an option).
- Two decisions needed Matt's call and got asked rather than guessed:
  `node`/`pwsh` split into seven inventory entries instead of six (each
  needs its own GitHub repo for releases), and version comparisons stay
  within the installed version's own major line (n8n has a legacy 1.x tag
  line still being patched alongside 2.x; `moby/moby` mixes `client/vX`
  and `api/vX` tags in with `docker-vX` engine tags; Node has an official
  even-major-is-LTS model where the newest even major is "Current," not
  the safe upgrade target). Both confirmed with Matt before building
  further.
- Wrote and ran `read-installed.ps1` and `check-releases.ps1` cleanly.
- Two real bugs caught and fixed: an unquoted Go-template format string
  (`--format {{.Server.Version}}`) getting mis-parsed by PowerShell's
  `Invoke-Expression` as a script block, corrupting the arguments passed
  to `docker`; and confirming that invoking a script via `powershell`
  launches Windows PowerShell 5.1 instead of pwsh 7 on this host — always
  use `pwsh -File`.

**Sitting 2 — the judgment layer** (commit `353678e`):
- Wrote `assess-update.ps1` — one model call per component, never batched,
  with deterministic facts (installed/current version, releases behind,
  boundary crossed, `blast_radius`) supplied by the script itself so the
  model only judges the change, not the retrieval.
- GLM-5.2, referenced in Matt's own personal notes, no longer exists on
  OpenRouter — superseded by 5.3. Used `z-ai/glm-5.3-20260816`.
- Ran against all five non-zero-gap components. Verdicts discriminated
  correctly: node (smallest blast radius, `low`) got `do-now` on a
  concrete 12-CVE fix; n8n (largest gap, 40 releases, `high` blast radius)
  got `defer` because nothing in the notes was security-related or flagged
  as requiring action. Total spend $0.2137 against the $0.25/run cap.

**Sitting 3 — schedule and close** (commits `2a438d1`, `d82554e`):
- Wrote `run-check.ps1` — one command, end to end. Each stage
  (`read-installed`, `check-releases`, `assess-update`) is spawned as a
  real subprocess (`pwsh -File`), not called in-process via `&` — all
  three end with `exit N`, and an in-process call would take the
  orchestrator down with it. `invoke-model.ps1` avoids this deliberately
  by using `return` instead (see its own header comment).
- Two more bugs found running it live: PowerShell captures *everything*
  written inside a `foreach` used as an expression — a stray
  `Write-Output` meant only as console echo was getting swept into the
  result collection, corrupting the failure count (fixed with
  `Write-Host` instead); and the model wrote `WHAT_IT_WILL_TAKES:`
  (plural) once, which the strict parser correctly refused to guess at
  rather than silently mangling — the regex was relaxed to accept it.
- Real Discord posts went out during testing (two to `#runs`, two to
  `#decisions`) — the first `#runs` post has a garbled "FAILED" segment
  from the bug above (nothing actually failed), and the first
  `#decisions` post is missing ollama's line (resolved after a retry).
  Both are superseded by the first real scheduled run.
- Matt was asked before registering anything persistent. First choice was
  triggering via n8n instead of Task Scheduler, to keep n8n as the primary
  scheduling hub — but n8n runs in a Docker container isolated from the
  host tools this project reads (`docker inspect` on host containers,
  `ollama`, `node`, `pwsh`), so that would need a new host-side webhook
  listener with its own security surface. On seeing that tradeoff, Matt
  chose Task Scheduler for this one job.
- Verified the WindowsApps-packaged `pwsh.exe` (not the MSI install path)
  actually launches correctly under Task Scheduler using a zero-cost
  throwaway task, before trusting the real one against live spend.
- Registered `infra-watch-weekly`: Mondays 8:00 AM, runs as Matt's own
  account only when logged in (no stored password). Next run: 9/7/2026.

**End state:** v1 is fully built and committed. Weekly automation is live
and unattended. Total model spend for the whole build: **$0.2316** across
all testing (day-of numbers only — Sitting 2's run happened the prior
calendar day and isn't included in that figure), well under the $0.50/day
cap throughout.

**Not yet done / open for later** (see `PLAN-infra-watch-v1.md`'s roadmap
section for full detail): Notion board (v1.1), real OSV/NVD vulnerability
lookups, extending the inventory beyond six components, and a separate
model-version-review track (Qwen/GLM) that's explicitly out of scope for
this project and not being built toward.
