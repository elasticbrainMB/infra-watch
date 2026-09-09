# infra-watch — update-execution flow (design proposal)

> **STATUS: DECISIONS LOCKED 2026-09-08 — plan settled, not yet built.**
> Written 2026-09-08 as a design exploration; the seven open forks were
> answered by Matt the same day and are recorded as settled in §8. It
> defines a companion to v1's decision queue: a disciplined
> *install → verify → resolve → rollback* flow for updates infra-watch has
> flagged. No script, config, guardrail, or live component has been changed —
> the next step (§9) is a read-only Node-first proof, and that has not run.
> Building anything writes to `scripts\` (an `ask`-gate) and executes on the
> host in Claude Code, not in this Cowork session.

This document assumes `PLAN-infra-watch-v1.md` (the charter) and `STATE.md`
(current facts) as read. It does not restate them. Where it says `[VERIFY]`
it means a fact that is *not currently recorded on disk* and must be captured
from the live host before the flow can be trusted — see §7.

---

## 1. The problem, and the one hard constraint

v1 answers *which updates should I care about this week* and stops. It writes
a verdict (`do-now` / `schedule` / `defer`), a one-line "what it will take,"
and a link to the release notes, then posts the ones that need Matt to
`#decisions`. What it deliberately does **not** do is help Matt actually
apply an update once he's decided to — installing it, checking whether it
broke anything, fixing it if it did, and getting back to a known-good state
if it can't be fixed.

That gap is what this proposal fills. Matt's ask: lightweight but
disciplined — more than "click update and cross my fingers," less than
enterprise change-management.

**The hard constraint that shapes everything below.** infra-watch's
`.claude\settings.json` `deny` list blocks *every* mutating docker verb
(`restart`, `stop`, `start`, `rm`, `pull`, `run`, `update`, `compose`) for
both Bash and PowerShell, and "this project never applies an update" is a
stated hard boundary. The plan calls a tool that could `docker pull` "one
bad assessment away from being an auto-updater you didn't ask for." That
boundary is not to be widened, and this design does not widen it.

The consequence is structural: **infra-watch itself must never perform an
install or a rollback.** Every mutating step in the flow below is run by Matt
by hand. infra-watch's role is limited to the three things it *can* do
within its read-only guardrails:

1. **Generate the runbook** — the per-component checklist of exactly what to
   do, seeded from the assessment it already wrote.
2. **Snapshot state read-only, before** — so a rollback target and a
   verification baseline exist.
3. **Verify read-only, after** — re-run the same checks and report
   pass/fail.

The muscle (pull, recreate, reinstall, re-pin, restore) stays in Matt's
hands. That is the whole point of keeping the tool read-and-recommend, and
it is how this works *within* the guardrails rather than around them.
**Settled (Decision A): infra-watch stays strictly read-only** — the apply
muscle does not move into a separate tool for now; Matt runs every mutating
step by hand.

---

## 2. How the four platforms are actually deployed (discovery)

Grounded in `config\inventory.json`, the run records, and the assessments —
not assumed. The four Matt named split cleanly into two deployment classes,
which is what lets the flow be two templates rather than four:

| Platform | Class | Read from | blast_radius | State that an update can damage |
|---|---|---|---|---|
| **n8n** | Docker container (`n8n`) | image label `org.opencontainers.image.version` | **high** | Its database — workflows, **encrypted credentials**, execution history. Lives in the container's data volume (SQLite in `/home/node/.n8n`) or an external DB. `[VERIFY]` |
| **Docker Engine** | Native host | `docker version --format` | **high** | All containers/images/volumes it manages; `daemon.json`. Substrate — every tracked container runs inside it. |
| **Ollama** | Native host | `ollama --version` | **high** | Pulled models + manifests (`%USERPROFILE%\.ollama\models` or `OLLAMA_MODELS`). Large; survive a binary swap. |
| **Node.js** | Native host | `node --version` | **low** | Effectively none — stateless build-time tool. Global npm packages are re-installable. |

The dependency graph, from the inventory `notes`, is the reason blast_radius
lands where it does:

- **Docker Engine is the substrate.** Updating it restarts the daemon, which
  bounces n8n, open-webui, and openclaw *simultaneously*. Highest real-world
  blast radius of the four.
- **Ollama is the model backend.** open-webui and (likely) openclaw call it
  through `host.docker.internal`. An Ollama outage degrades those two, not
  just Ollama.
- **n8n is the automation hub.** Live workflows depend on it. Note it does
  **not** run infra-watch's own weekly trigger — that's Windows Task
  Scheduler (`infra-watch-weekly`), deliberately, because n8n is container-
  isolated from the host tools this project reads. So updating n8n cannot
  break infra-watch itself.
- **Node** is a build-time tool with no running service depending on it —
  hence `low`.

The same two classes cover the other three tracked components not named in
the ask: open-webui and openclaw are containers (like n8n); pwsh is a native
host app (like the others, and it runs infra-watch's own scripts). Nothing
below is specific to the four — it generalizes to all seven by class.

### What is NOT determinable from disk (must be closed before build)

The tool records only the *version* of each component. It does not record
*how each is deployed or updated*, and that information is exactly what a
correct install/rollback runbook needs:

- **`read-installed.ps1` runs `docker inspect` but keeps only the version
  label** — it discards volume mounts, bind mounts, env, ports, restart
  policy, and image digest. So the containers' data locations and their
  `docker run`/compose definitions are **not on disk**.
- **The native apps' install/update mechanism is unrecorded.** Is Docker
  Engine here Docker Desktop on a WSL2 backend, or an engine package? Is
  Ollama the vendor installer? Is Node via nvm-windows, winget, or an MSI?
  The only such clue anywhere is `STATE.md` noting pwsh is the
  WindowsApps-packaged build — and even the model hedged "if Node runs in
  containers" in its own assessment. Unknown from these files.
- **Where n8n's DB actually lives** (SQLite-in-volume vs external Postgres)
  and **the value/preservation of `N8N_ENCRYPTION_KEY`** — unrecorded, and
  both are load-bearing for n8n rollback (§4).

These are marked `[VERIFY]` throughout and collected in §7 as prerequisites.
None can be safely guessed; a rollback runbook built on a guessed volume path
is worse than no runbook.

---

## 3. The flow, in five phases

The same shape for every component; the per-platform specifics are §4. The
order is deliberate: **capture before change, change one thing, verify
against the capture, and keep the door open backward until verify passes.**

**Phase 0 — Pre-flight capture (read-only, infra-watch can do this).**
Nothing is touched. Record:
- the exact version being moved *from* and *to* (from the run's
  `installed.json` and the assessment);
- a **baseline health snapshot** — the very checks Phase 3 will re-run, taken
  now while things are known-good, so "did it break" is measured against a
  real baseline and not a memory;
- **rollback material**: for a container, the current pinned image *tag and
  digest* (`docker inspect` → `RepoDigests`) plus a **backup of the data
  volume**; for a native app, the current version *and* a retained copy of
  the prior installer (or a recorded exact-version download source);
- confirmation the target is a **pinned, explicit version** (no `:latest`) —
  otherwise the rollback target is undefined and the flow stops here.

**Phase 1 — Install (Matt runs; infra-watch never does).** One component at
a time. Never bundle an engine update with a container update in the same
window. Details per platform in §4.

**Phase 2 — Verify (read-only, infra-watch can do this).** Re-run the Phase-0
baseline checks and diff. Concrete definition of "didn't break anything" per
platform in §4. This is the phase that decides go-forward vs. resolve/roll
back.

**Phase 3 — Resolve (if verify fails).** A three-way triage:
1. *A wrinkle the release notes predicted* → apply the documented fix (e.g.
   Docker's `max-concurrent-downloads` config, or OpenClaw's
   `openclaw doctor --fix`). The assessment's "what it will take" line
   already names most of these.
2. *A dependency break* → e.g. Ollama came back but open-webui/openclaw can't
   reach it; fix the link, not the component.
3. *An unknown regression* → do not fight it live. Go to Phase 4.

**Phase 4 — Rollback (Matt runs).** Restore from the Phase-0 artifacts. The
per-platform cost of this varies enormously (Node: trivial; n8n: must restore
the DB, not just re-pin the tag — §4) and that variance is most of why the
gate is heavier for some than others.

A run isn't "done" until either verify passed, or a rollback was itself
verified back to the Phase-0 baseline.

---

## 4. Per-platform specifics

### 4a. Docker containers — n8n (and, by class, open-webui, openclaw)

**Install.** Pull the new *explicit* tag, then recreate the container from an
identical definition with only the tag changed — same volumes, env, ports,
restart policy. (These commands are all on infra-watch's deny-list, by
design; Matt runs them.)

**The n8n-specific hazard: forward-only DB migrations.** The assessment flags
that jumping minor lines makes n8n "run its automatic startup migrations."
Those migrations are **forward-only**: once the new container boots and
upgrades the schema, the *old* image may refuse to start against the migrated
DB. So for n8n, **re-pinning the old tag is not a rollback** — the rollback is
*restore the Phase-0 volume/DB backup **and** re-pin the old tag.* This is why
the volume backup is **mandatory, not optional**, for n8n, and why n8n gets a
scheduled window even on a lighter verdict.

Also: credentials are encrypted with `N8N_ENCRYPTION_KEY`. If the recreate
doesn't carry the same key, every stored credential becomes undecryptable —
capture and confirm the key in Phase 0.

**Verify "didn't break anything" (read-only, all allowed commands):**
- `docker ps` shows the container `Up`, and `docker inspect` shows its
  healthcheck `healthy` (not `starting`/`unhealthy`);
- its HTTP health endpoint returns 200 (n8n exposes `/healthz` and
  `/healthz/readiness`);
- the startup log shows migrations **completed without error** — this is the
  go/no-go signal for n8n specifically;
- a **smoke test**: the workflow list loads (DB intact) and one safe,
  idempotent workflow executes; if Matt scripts the public API, confirm the
  removed workflow-history `offset` param and the JSON-content-type
  decorator-route change (both from the assessment) haven't broken his
  callers.

**Rollback.** Stop the new container → restore the Phase-0 volume/DB backup →
recreate the old pinned tag → re-run the verify smoke test to confirm the
restore is itself good.

### 4b. Docker Engine (native host — the substrate)

**Install.** Update the engine/Docker Desktop to the target (29.8.0). The
daemon restarts, so **all** containers bounce at once — this is a scheduled
window, not a quick swap. The assessment's one config wrinkle: 29.7.0 now
honors daemon-wide concurrent download/upload limits; set
`max-concurrent-downloads`/`-uploads` to `0` in `daemon.json` if the old
unlimited behavior is wanted.

**Verify:**
- daemon is up — `docker version` returns a Server section;
- **every container that was `Up` in the Phase-0 snapshot is `Up` again** —
  diff `docker ps` against the capture; none stuck restarting;
- then run each affected container's own app health check from §4a (the
  engine restart bounced them, so the engine update isn't verified until the
  things running on it are).

**Rollback hazard specific to the engine.** A version *downgrade* is usually
fine for volumes/images, but a downgrade across a storage-format bump can be
one-way. Before applying, confirm the target is downgrade-safe; retain the
prior engine/Docker Desktop installer in Phase 0. This is the one platform
where rollback may not be clean, which argues for the heaviest gate.

### 4c. Ollama (native host — model backend)

**Install.** Run the Ollama installer for the target (0.33.3). Go **straight
to 0.33.3** — the 0.33.0 note flags default packaging broken on Windows by
macOS-specific assumptions, so don't step through it. An update is a binary
swap; the models directory is untouched, so **models are not backed up** —
they persist by default. (Confirm the models path in Phase 0 anyway, so the
verify diff is meaningful.)

**Verify:**
- `ollama --version` equals the target;
- `ollama list` shows **all** models still present (diff against Phase 0);
- **a known-good query against the caddy model** returns sane output within
  normal latency (`ollama ps` shows it loaded) — this is the concrete
  smoke test Matt asked for;
- open-webui and openclaw can still reach it via `host.docker.internal` (a
  chat round-trips) — because they're the dependents.

**Rollback.** Reinstall the prior version from the retained installer; the
models directory is unaffected, so this is the fastest, cleanest rollback of
the four.

### 4d. Node.js (native host — build tool)

**Install.** Install the target within the same major (24.20.0) via whatever
mechanism it's already on `[VERIFY]`.

**Verify:** `node --version` equals target; `npm --version` sane; whatever
depends on it (e.g. the caddy's build) still builds and runs.

**Rollback.** Reinstall 24.18.0. Trivial — no state, `low` blast radius.
Node is the one where in-place with a version-check is genuinely enough, and
it's the natural first component to prove the whole loop on (mirroring v1's
"smallest gap first" discipline).

---

## 5. How the gate ties into the verdict and blast_radius

The two existing fields already carry the right information; the flow just
reads them differently:

- **The verdict sets *when*.** `do-now` → runbook goes to the top of the
  apply queue; `schedule` → a planned window; `defer` → no runbook is
  generated (nothing to apply).
- **blast_radius sets *how heavy the gate is*** — and this maps directly onto
  the project's own `TIERS.md` vocabulary, which already says anything
  "destructive or hard to reverse" is Tier F (full gate: read the raw output
  and decide before the next step runs). Applying an update is destructive by
  that definition, so:

| blast_radius | Gate | What that means concretely |
|---|---|---|
| **high** (docker, n8n, ollama) | Tier **F**, always | Mandatory Phase-0 data backup + a rollback path confirmed *before* applying; scheduled window; full smoke test in verify. A `do-now` here means "deliberately and soon," **not** "unattended at 8am." |
| **medium** (open-webui, openclaw, pwsh) | Tier F first time, then E | Backup still taken; lighter smoke test where no dependents exist. **Consequence of Decision E (blast_radius alone):** a migration such as openclaw's `doctor --fix` does *not* auto-promote to full-F — a medium item with a migration is run under the medium gate, deliberately. |
| **low** (node) | Tier E / near-checklist | Version-pin + verify version, in place, rollback = reinstall prior. |

`TIERS.md`'s promotion/demotion rules fit this exactly: a component's apply
step moves F→E only *after one clean F run*, and **any surprise — even a
benign one — sends it back to F** for the next update. That is the mechanism
that keeps "lightweight" from drifting into "careless."

**Where infra-watch plugs in.** It already emits the assessment and posts
`do-now` / high-`schedule` items to `#decisions`. The apply flow is the
downstream of that post: when Matt acts on a `#decisions` item, the runbook
for that component is generated — the §4 template for its class, plus the
specific wrinkles the assessment *already surfaced* (n8n's API `offset` param,
Docker's concurrent-download config, OpenClaw's `doctor --fix`). **Settled
(Decision B): the tool auto-runs** the read-only Phase-0 snapshot and Phase-2
verify and posts a pass/fail diff to `#decisions`, rather than only printing a
checklist. Runbooks can be **largely template-driven and need no new model
call**, which matters:
last week's run (`20260907-080001`) already spent **$0.268 against the
$0.25/run cap** and openclaw's assessment failed as a result — so adding model
calls into the unattended weekly path is the wrong direction. Runbook
generation is on-demand and separate from the weekly run.

**One integrity rule, borrowed from "use the fact, not a proxy":** a runbook
must be seeded only from a *current* assessment. `records\assessments\
openclaw.md` on disk is from the `20260904` run, not the latest `20260907`
one (which failed on the cap), so it is stale. The generator must refuse to
build a runbook from an assessment whose `run_id` isn't the latest successful
one for that component.

---

## 6. What stays out (v1 discipline preserved)

- infra-watch does not gain any apply/rollback capability. No deny-list entry
  is added or relaxed. (Decision A may put that capability in a *different*
  tool; it never goes here.)
- No new unattended action. Everything mutating is Matt-initiated and
  Tier-F-gated for high-blast components.
- No auto-scheduling of updates. The weekly run still only *recommends*.

---

## 7. Prerequisites — `[VERIFY]` items to close before any build

A one-time, **read-only** deployment-discovery pass (using only allowed
commands: `docker ps`, `docker inspect`, `ollama list/show`, the version
reads) to record, per component, facts the tool doesn't currently keep:

1. Each container's **volume/bind mounts, env, ports, restart policy, and
   image digest** (`docker inspect`) — the recreate definition and the data
   locations.
2. n8n's **DB backend** (SQLite-in-volume vs external) and confirmation
   `N8N_ENCRYPTION_KEY` is set and preserved across recreate.
3. Each native app's **install/update mechanism**: Docker Engine (Docker
   Desktop + WSL2 backend, or engine package?), Ollama (vendor installer?),
   Node (nvm-windows / winget / MSI?). pwsh is already known to be the
   WindowsApps build.
4. Whether the engine target version is **downgrade-safe** (§4b).

**Settled (Decision F): these are recorded by extending `config\inventory.json`
with a per-component `deployment` block** (volume/mount paths, DB backend,
install/update mechanism, image digest, downgrade-safety) — the hand-maintained
inventory grows rather than introducing a new record type. `inventory.json` is
on the `Edit(config/**)` allow-list, so this is writable without touching the
`ask`-gate. Until the block is filled, the runbooks in §4 are shaped correctly
but not yet *fillable* with real paths.

---

## 8. Decisions — settled 2026-09-08

| # | Fork | Matt's call | What it means here |
|---|---|---|---|
| **A** | Where the apply muscle lives | **Read-only** | infra-watch generates runbooks, snapshots, and verifies; it never applies or rolls back. Deny-list unchanged. No separate apply-tool for now. |
| **B** | Automated vs guided | **Auto-run** | The tool auto-runs the read-only Phase-0 snapshot and Phase-2 verify and posts a pass/fail diff to `#decisions`. Not a print-and-tick checklist. |
| **C** | In-place vs staged | **In place with backup** | Update where it sits after a mandatory Phase-0 data backup; no staging a parallel copy. |
| **D** | Rollback-artifact retention | **7-day window** | Volume backups and retained prior installers/images are kept 7 days, then pruned. (Ollama models are never backed up — they persist.) |
| **E** | Gate driver | **blast_radius alone** | The gate is set purely by blast_radius. A migration does *not* promote the gate — openclaw's `doctor --fix` runs under its medium gate. |
| **F** | Where §7 deployment facts live | **Extend `inventory.json`** | A per-component `deployment` block in the existing hand-maintained inventory; no new record type. |
| **G** | Build scope / first step | **Prove on Node first** | Build and run the read-only loop on Node (lowest blast, trivial rollback) before touching anything else — mirrors v1's "smallest gap first." |

Two consequences worth stating plainly, both accepted by these calls:

- **D (7-day window)** means a rollback attempted more than a week after an
  update may find its artifacts already pruned. For high-blast items that's a
  real edge; the mitigation is that verify runs *immediately* after install,
  so a bad update is normally caught inside the window, not weeks later.
- **E (blast_radius alone)** keeps the gate model simple but means a
  medium-blast component carrying a breaking migration is run under the
  lighter medium gate. Matt has accepted running such a migration
  deliberately rather than auto-escalating it.

---

## 9. First build — Node, read-only proof (Decision G)

The next increment, in order. It writes only to `config\` and `records\`
(both allow-listed) and to a new `scripts\` file (the one `ask`-gated step),
and — critically — **the discovery and verify commands execute on the Windows
host in Claude Code, not in this Cowork session**, whose shell is an isolated
Linux sandbox that cannot reach the host's `node`, `docker`, or `ollama`.

1. **Close Node's `[VERIFY]` facts, read-only.** Determine Node's actual
   install/update mechanism on the host (nvm-windows / winget / MSI) and write
   a `deployment` block for the `node` entry in `inventory.json` (Decision F).
   Nothing else in the inventory is touched.
2. **Write the Node runbook** from the §4d template — target within-major
   (currently 24.20.0), in-place, rollback = reinstall prior (§4d), 7-day
   artifact window (Decision D).
3. **Write the read-only snapshot + verify step** (Decision B, auto-run):
   Phase-0 captures `node --version` / `npm --version` and any build baseline;
   Phase-2 re-runs them post-install and diffs; result posts to `#decisions`.
   This is a new `scripts\` file → `ask`-gated; expect the permission prompt.
4. **Dry-run the read-only halves on the host** (Phase 0 and Phase 2) *without*
   applying anything, to confirm they capture and diff correctly against a
   known-good Node — a genuine Tier-F first run per `TIERS.md`.
5. **Only then**, on Matt's go, does Matt apply the real Node update by hand
   and let the verify step grade it. If that whole loop runs clean once,
   Node's apply step earns promotion F→E and the same shape is templated out
   to the higher-blast components.

Nothing beyond step 1's read-only inventory edit is built until Matt gives the
explicit go for step 3 (it crosses into `scripts\`).
