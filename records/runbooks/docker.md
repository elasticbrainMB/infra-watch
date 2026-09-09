# Docker Engine runbook — 29.6.1 → docker-v29.8.0

> **STATUS: DRAFT RUNBOOK — do not execute until every `[VERIFY]` value in
> Step Zero is confirmed against the live host. Pending Matt's review;
> nothing here has been adopted or run.** Written 2026-09-09 in Cowork
> (design/review only — Cowork's shell cannot reach the host's `docker`,
> `ollama`, or `node`). No script, config, or live component was touched
> producing it. infra-watch does not apply updates — **every mutating
> command below is run by Matt by hand**, one at a time, and only after
> Step Zero is filled in.

Seeded from `records\assessments\docker.md` (run `20260907-080001` —
confirmed as the latest successful run for `docker`; its own `summary.json`
shows `"id": "docker", "ok": true`). This is the fourth instance of the
five-phase apply loop, and the first on the **substrate** rather than a
single component — per `PLAN-update-execution-v1.md` §4b, updating the
engine restarts the daemon, which bounces **every** tracked container at
once (`n8n`, `open-webui`, `openclaw`), so this runbook's Phase 0/2 checks
cover the whole running fleet, not just Docker itself.

**Sequencing note (settled with Matt, 2026-09-09).** This runs **before**
OpenClaw and n8n, not after, even though it was drafted third. Reasoning:
OpenClaw's upcoming 2.0 migration and n8n's own forward-only migrations are
each one-way, with a 7-day rollback window (Decision D). If the engine were
updated *after* either of those, its restart would re-bounce an already-
migrated container outside the original update's own verification window —
stacking an unrelated substrate change on top of an irreversible one.
Doing the engine first means OpenClaw and n8n each get their own update
on an already-proven, stable substrate.

| Field | Value |
|---|---|
| Component | `docker` (Docker Engine — the substrate) |
| Version moving **from** | `29.6.1` |
| Version moving **to** (pinned) | **`docker-v29.8.0`** (5 releases behind; minor boundary crossed; no newer major/track exists) |
| `blast_radius` | **high** (from `inventory.json`) — and structurally the highest of the four: every tracked container depends on this engine |
| Migration named in the assessment? | No database/state migration in the *engine* itself, but see the config wrinkle below and the storage-format caveat in Step Zero |
| Gate | **Full Tier F** — high blast_radius alone triggers it (§5), and this is also flagged in `PLAN-update-execution-v1.md` §4b as "the one platform where rollback may not be clean, which argues for the heaviest gate" |
| Verdict (assessment) | `do-now` — 29.6.2 patches 5 CVEs (incl. command injection via Git source checkout, and an LLB file op that can wipe `/tmp`), 29.7.0 fixes another CVE in go-archive, 29.8.0 adds hardening (configurable default AppArmor profile, a world-writable container-root fix under btrfs) |
| Config wrinkle | **29.7.0 changes concurrent-download/upload behavior** — daemon-wide `max-concurrent-downloads`/`max-concurrent-uploads` limits are now honored. Since the jump from `29.6.1` crosses this boundary, decide *before* installing whether to set both to `0` in `daemon.json` to keep the old unlimited pull/push behavior, or accept the new default. |

---

## Step Zero — Verify deployment facts (do this first, before anything else)

Nothing here mutates anything; it is all read-only. This is the one
`[VERIFY]` set `PLAN-update-execution-v1.md` §7 calls out by name as still
open for Docker: *is this Docker Desktop (WSL2 or Hyper-V backend) or a
bare engine package?* Do not assume either — Windows hosts commonly run
Docker Desktop, but this project has not confirmed it, and the update
mechanism (an in-app "Check for updates," a downloaded installer, or a
package-manager command inside WSL) differs by which it is.

| Fact | How to confirm (read-only) | Recorded value |
|---|---|---|
| **Install mechanism** | Check for a Docker Desktop installation (Start Menu entry, `C:\Program Files\Docker\Docker`, a running `Docker Desktop.exe` process) vs. a bare engine service; if Desktop, confirm WSL2 vs. Hyper-V backend (`docker info` → `OSType`/`Server Version` section, or Desktop's own Settings) | `[VERIFY]` |
| **Current engine version, confirmed live** | `docker version` (Server section) — cross-check against `inventory.json`'s last-recorded `29.6.1` | `[VERIFY]` |
| **Update mechanism for the target** | If Docker Desktop: in-app updater, or a downloaded installer `Docker Desktop Installer.exe`? If a bare engine: what package source? | `[VERIFY]` |
| **Downgrade-safety of 29.6.1 → 29.8.0 → back to 29.6.1** | Read Docker's own release notes/engine release notes (docs.docker.com/engine/release-notes) for any storage-format or data-layout change across this range before assuming a downgrade is clean. **Do not assume "usually fine" without checking this specific range** — §4b is explicit that a storage-format bump can make a downgrade one-way. | `[VERIFY]` |
| **Full current container fleet + their health baseline** | `docker ps -a` (every container, not just the three tracked ones — anything else running on this engine bounces too) | `[VERIFY]` |
| **Retained installer for a prior-version rollback** | Check whether a `29.6.1`-era Docker Desktop/engine installer is already on the host; if not, note that one may need to be sourced with Matt's approval, same pattern as Ollama's rollback artifact | `[VERIFY]` |
| **daemon.json's current concurrent-download/upload settings** | Read the live `daemon.json` (not assumed absent-default — confirm what's actually configured today) so the config wrinkle above is a deliberate choice, not a surprise post-update | `[VERIFY]` |

---

## Phase 0 — Pre-flight capture (read-only; capture before you change anything)

**0.1 — Confirm the target is pinned.** `docker-v29.8.0` (engine version
`29.8.0`), exact — not `latest`, not whatever the updater defaults to
without confirmation.

**0.2 — Engine and fleet-wide baseline.** This is the one runbook in the
sequence where Phase 0 must cover more than the component being updated,
because the restart bounces everything:

```
docker version                                   # Server section — current engine version
docker ps -a                                     # every container and its current status
docker inspect --format '{{json .State.Health}}' n8n
docker inspect --format '{{json .State.Health}}' open-webui
docker inspect --format '{{json .State.Health}}' openclaw
```

For each of `n8n`, `open-webui`, and `openclaw`, also record its own
component-specific "known good" signal — the same ones their own future
runbooks use: n8n's `/healthz`/`/healthz/readiness` and workflow-list load;
open-webui reachable and reporting the expected Ollama backend version;
openclaw's Control UI reachable and Discord connected. Write down what
"good" looks like for **all three** today, before the engine changes.

**0.3 — Dependent-of-a-dependent check.** Ollama itself is native-host, not
a container, so the engine restart doesn't touch it directly — but
open-webui's and openclaw's connection *to* Ollama depends on their own
containers coming back up cleanly. Confirm both can currently reach Ollama
via `host.docker.internal` (baseline), so Phase 2 has something to diff
against if that link breaks post-restart.

**0.4 — Retain the prior engine/Desktop installer.** Using Step Zero's
findings, retain (or, with Matt's approval, fetch and hash-verify) an
installer for `29.6.1` before applying anything — same discipline as
Node's and Ollama's rollback artifacts, adapted to whatever Step Zero found
the actual install mechanism to be.

**0.5 — Confirm downgrade-safety in writing before proceeding.** If Step
Zero's research finds any storage-format or data-layout change across
`29.6.1`→`29.8.0`, stop and flag it to Matt explicitly — don't proceed
under an assumed-clean rollback. This is the one component where the
runbook itself says rollback might not be available at all.

**0.6 — Decide the `daemon.json` config wrinkle now, not after.** Record
Matt's choice on `max-concurrent-downloads`/`-uploads` (keep unlimited via
`0`, or accept the new default) before Phase 1, so it's applied
deliberately in the same window rather than discovered as a behavior change
afterward.

---

## Phase 1 — Install (Matt runs; infra-watch never does)

This is a **scheduled window, not a quick swap** — every tracked container
(and anything else on this engine) goes down and back up. Do not bundle
this with an OpenClaw or n8n version change in the same window (their own
updates come after, on the now-stable engine, per the sequencing note
above).

1. Apply the `daemon.json` change decided in Phase 0.6, if any, before or
   as part of the engine update per the mechanism Step Zero found.
2. Update the engine/Docker Desktop to `29.8.0` via whatever mechanism Step
   Zero confirmed. All commands here are on infra-watch's deny-list by
   design — Matt runs each one by hand.
3. Let every container restart on its own via its recorded restart policy;
   don't manually `docker start` them unless one fails to come back
   (that's a Phase 3 case, not routine).

---

## Phase 2 — Verify (read-only; this phase decides go-forward vs. roll back)

Not "verified" until **all** of these pass — engine-level first, then the
whole fleet, per §4b ("the engine update isn't verified until the things
running on it are"):

- **Daemon is up.** `docker version` returns a Server section, version
  exactly `29.8.0`.
- **Every container that was `Up` in the Phase 0 snapshot is `Up` again.**
  Diff `docker ps -a` against the Phase 0 capture — none stuck restarting,
  none missing.
- **Each of the three tracked containers passes its own health check** from
  Phase 0.2's baseline: n8n's health endpoints + workflow list; open-webui
  reachable and reporting the expected backend; openclaw's Control UI +
  Discord connection.
- **open-webui and openclaw both still reach Ollama** via
  `host.docker.internal` (Phase 0.3's baseline) — a broken link here is a
  dependency break, not necessarily an engine problem.
- **`daemon.json`'s concurrent-download/upload setting matches what was
  decided in Phase 0.6**, not a silently-applied new default.

If all pass, the update stands. If any fail, go to Phase 3.

---

## Phase 3 — Resolve (if verify fails)

1. **A wrinkle the release notes predicted** — the concurrent-download/
   upload default change is the one named in the assessment; if pulls/pushes
   behave differently than expected, apply the documented `daemon.json` fix
   rather than treating it as a regression.
2. **A dependency break, not an engine break** — the daemon itself is
   healthy and every container is `Up`, but one container's *own* health
   check fails (e.g., open-webui can't reach Ollama). Fix that specific
   link — don't treat it as an engine failure.
3. **A container stuck restarting, or an unknown regression** — do not
   fight it live. Go to Phase 4.

---

## Phase 4 — Rollback (Matt runs)

**This is the one component in the sequence where rollback may not be
clean** (§4b) — which is exactly why Step Zero/Phase 0.5's downgrade-safety
check happens *before* Phase 1, not after something breaks.

1. If Phase 0.5 confirmed the downgrade is safe: reinstall the retained
   `29.6.1` engine/Desktop installer.
2. Re-verify all of Phase 2 against `29.6.1` — daemon up, every container
   back to its Phase-0-baseline health, dependents reconnected.
3. If Phase 0.5 found the downgrade path is **not** clean (a storage-format
   change in the range), the rollback plan has to be something other than
   "just reinstall the old version" — this is exactly the scenario the
   heaviest gate exists to catch *before* Phase 1, not resolve after. If
   this sitting reaches Phase 4 without a confirmed-safe downgrade path
   already in hand from Phase 0.5, stop and get Matt's explicit direction
   rather than guessing at a recovery.

---

## Retention

7-day artifact window (Decision D) applies to the Phase 0/Phase 2 capture
files this project generates. Whatever installer Step Zero finds or fetches
for the `29.6.1` rollback follows the same pattern as Node's and Ollama's —
outside this project's retention control if it's a pre-existing file, or
tracked with an explicit retention note if freshly sourced.

## Gate

`blast_radius: high`, and structurally the substrate for every other
tracked component → **Tier F, always**, and per `TIERS.md`'s promotion rule
this is Docker's own first sitting under the update-execution flow, so it
runs at F regardless of how cleanly Node's, Ollama's, or any other
component's run went — promotion is per-component, never inherited.

## Source

Raw release notes this verdict was drawn from:
https://github.com/moby/moby/releases/tag/docker-v29.8.0

---

_This runbook is generated from a model's assessment and this project's own
read-only host discovery (once Step Zero is closed) — advisory input to
Matt's decision, not a substitute for it. Every install and rollback step
above is Matt's hand action; infra-watch performs only the read-only
capture and verify steps._
