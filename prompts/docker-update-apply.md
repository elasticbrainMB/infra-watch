# infra-watch — Docker Engine update apply (semi-automated handoff)

**Paste the block below into a Claude Code sitting.** This is the fourth
component and the first on the substrate itself — updating the engine
restarts the daemon, which bounces **every** tracked container at once
(`n8n`, `open-webui`, `openclaw`), so this sitting's Phase 0/2 checks cover
the whole running fleet, not one target. It also runs **before** OpenClaw
and n8n in the confirmed sequence (settled with Matt 2026-09-09): both of
those carry one-way migrations with a 7-day rollback window, and updating
the engine after either would re-bounce an already-migrated container
outside its own verification window. Read `records\runbooks\docker.md` in
full before running any of this — it is this sitting's runbook, Step Zero
included, and this prompt does not restate its detail.

**This is also the one component where rollback might not exist at all.**
The runbook's Phase 0.5 is a hard prerequisite: confirm from Docker's own
release notes whether `29.6.1` → `29.8.0` crosses any storage-format or
data-layout change before touching anything. If that can't be confirmed
clean, STOP and get Matt's explicit direction — do not proceed on an
assumed-safe downgrade.

**The concurrent-download/upload config wrinkle is already decided — don't
re-litigate it.** Matt reviewed the actual 29.7.0 changelog (not just the
assessment's summary) and confirmed: this is Docker fixing a bug where an
existing daemon-wide limit wasn't being enforced for containerd-image-store
installs, not a new restriction. Decision: accept the fixed/default
behavior, do not set `max-concurrent-downloads`/`-uploads` to `0`. Step Zero
still confirms whether this host even uses the containerd image store (if
not, this never mattered here), but that's a fact-check, not a decision
point — don't stop to ask Matt about it again.

---

infra-watch — Docker Engine update apply (semi-automated: read-only Step Zero + Phase 0/2 automated across the whole fleet, install/rollback stay Matt's).

BEFORE YOU ACT. Disk is authoritative. Read: CLAUDE.md, STATE.md,
PLAN-update-execution-v1.md (§4b, §5, §7 point 3 and 4, §8), and
records\runbooks\docker.md in full. Also skim records\runbooks\ollama.md
and scripts\ollama-update-check.ps1 for the proven capture/diff shape, but
don't force-fit a single-target script here — this one needs to snapshot
and diff an entire container fleet, not one component.

Discipline: run commands verbatim, show raw output. `pwsh -File`, never
`powershell`. You are READ-ONLY except for records\/config\ edits and one new
scripts\ file — you never touch the engine, restart/stop/start any
container, or run an installer yourself; every mutating command here is on
the deny-list and is Matt's hand action. Never widen the deny-list. Disk is
source of truth; Discord is a mirror.

CHUNK A — Step Zero + Phase 0 (automated, read-only). Do all of this, then STOP.

1. Determine whether this host runs Docker Desktop (and which backend —
   WSL2 or Hyper-V) or a bare engine package, and how each would actually
   be updated (in-app updater, downloaded installer, or a package command).
   Do not assume Desktop just because this is Windows — confirm it.
2. Confirm the current engine version live via `docker version` against
   `inventory.json`'s recorded `29.6.1`.
3. **Downgrade-safety research (do this before anything else matters):**
   read Docker's engine release notes for the `29.6.1`→`29.8.0` range for
   any storage-format or data-layout change. Report clearly whether a
   downgrade back to `29.6.1` is expected to be clean. If you cannot
   confirm it's clean, say so explicitly and STOP — do not present Matt an
   install command until this is resolved one way or the other.
4. Capture the full container fleet: `docker ps -a` (not just the three
   tracked components — anything else running on this engine bounces too),
   plus each of `n8n`, `open-webui`, and `openclaw`'s own health signal
   (health status, and whatever each container's own future runbook will
   use as its smoke test — n8n's health endpoints/workflow list,
   open-webui's reachability and reported backend version, openclaw's
   Control UI + Discord connection). Also confirm open-webui and openclaw
   currently reach Ollama via `host.docker.internal` — the baseline Phase 2
   diffs against.
5. Check via `docker info` whether this install uses the containerd image
   store — the concurrent-download/upload fix in 29.7.0 only applies there.
   Read the live `daemon.json` for the record. **No decision needed here:
   Matt already decided (2026-09-09) to accept the fixed/default behavior
   and not set `max-concurrent-downloads`/`-uploads` to `0`** — this isn't a
   new restriction, it's 29.7.0 fixing a bug where that daemon-wide limit
   wasn't being enforced. Just confirm the containerd-image-store fact and
   move on; don't re-ask Matt about it.
6. Check whether a `29.6.1`-era installer/package is already retained on
   the host for rollback. If not, STOP and ask Matt before fetching one —
   same approval pattern as Ollama's rollback artifact.
7. Write `scripts\docker-update-check.ps1` (new file → `ask`-gated) with
   `-Phase capture`/`-Phase verify`, but scoped to the **fleet**: engine
   version, full `docker ps -a` status diffed by container name, and each
   of the three tracked containers' own health-check result. This is
   structurally different from `node-update-check.ps1`/
   `ollama-update-check.ps1` (single-target) — don't just copy their shape,
   design the capture around "did everything come back," per the runbook.
8. Run Phase 0 capture. Show raw output.
9. Report all of the above — especially the downgrade-safety finding — then
   STOP. Hand Matt the exact install step for whatever mechanism Step Zero
   found. No `daemon.json` change is planned. Tell him to reply "installed"
   when done.

[MATT'S ACTION: update the engine/Desktop by hand (a scheduled window — everything bounces), then reply "installed".]

CHUNK B — verify and record (automated). On "installed":

10. Run Phase 2 verify: engine version exactly `29.8.0`; every container
    from the Phase 0 `docker ps -a` snapshot is `Up` again, none stuck
    restarting; each of the three tracked containers passes its own
    health/smoke check from Phase 0; open-webui and openclaw both still
    reach Ollama; `daemon.json` unchanged (no concurrency edit was planned —
    confirm the installer didn't silently write one in).
11. If PASS: update the `docker` entry's `deployment`/version info in
    `config\inventory.json`, update `STATE.md` and `SESSION-LOG.md` noting
    this is Docker's own first clean Tier-F run (per-component promotion,
    doesn't inherit from Node/Ollama), and commit (`ask`-gated), scoped to
    exactly the files this sitting changed.
12. If FAIL: triage per the runbook's Phase 3 first — pulls/pushes running
    slower than before is the *expected*, accepted effect of the
    concurrency-limit fix, not a failure to chase; a single container's own
    dependency link is the other named/expected cause. Fix only what's
    documented, don't improvise. For anything else, especially a container
    stuck restarting or an unknown regression: do NOT attempt a rollback
    unless Phase 0.5 already confirmed the downgrade is clean. If it did,
    present Matt the reinstall step and STOP; if it didn't, stop and
    escalate to Matt for a decision rather than guessing at a recovery path
    that might not exist.

STOP conditions (hard): downgrade-safety can't be confirmed in Step Zero;
any Step Zero row unconfirmable; target isn't pinned exact `29.8.0`; verify
FAIL where no confirmed-clean rollback path exists; any impulse to touch
the engine, restart/stop/start a container, or run an installer yourself,
or to widen the deny-list.
