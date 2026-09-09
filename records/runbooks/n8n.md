# n8n runbook — 2.26.0 → n8n@2.37.11

> **STATUS: DRAFT RUNBOOK — do not execute until every `[VERIFY]` value in
> Step Zero is confirmed against the live host. Pending Matt's review;
> nothing here has been adopted or run.** Written 2026-09-09 in Cowork
> (design/review only — Cowork's shell cannot reach the host's `docker`).
> No script, config, or live component was touched producing it. infra-watch
> does not apply updates — **every mutating command below is run by Matt by
> hand**, one at a time, and only after Step Zero is filled in.

Seeded from `records\assessments\n8n.md` (run `20260907-080001` — confirmed
as the latest successful run for `n8n`; that run's own `summary.json` shows
`"id": "n8n", "ok": true, "verdict": "schedule"`). This is the third of the
three originally-named components through the update-execution flow, and it
runs last of them by design (`STATE.md`'s settled sequencing note,
2026-09-09): Docker Engine → OpenClaw → n8n. n8n has no `deployment` block
yet in `config\inventory.json` — like Ollama's first sitting, this one's
Step Zero is genuine discovery, not just closing out known facts.

**Why n8n is not first or second despite being named first in the original
ask.** n8n's own startup migrations are forward-only (see the hazard below),
same shape as OpenClaw's one-way SQLite migration. Running the Docker Engine
update after n8n would restart (bounce) an already-migrated container
outside its own 7-day verification window, stacking an unrelated substrate
change on top of an irreversible one. Doing the engine first, then OpenClaw,
means n8n lands last on an already-proven, stable substrate.

| Field | Value |
|---|---|
| Component | `n8n` (Docker container) |
| Version moving **from** | `2.26.0` |
| Version moving **to** (pinned) | **`n8n@2.37.11`** (42 releases behind; minor boundary crossed repeatedly; no newer major/track exists) |
| `blast_radius` | **high** (from `inventory.json`) — live workflows, encrypted credentials, and execution history all depend on this container |
| Migration named in the assessment? | **Yes** — jumping this many minor lines means n8n will run its automatic startup migrations, and per `PLAN-update-execution-v1.md` §4a those are **forward-only**: once the new container boots and upgrades the schema, the old image may refuse to start against the migrated DB |
| Gate | **Full Tier F** — `blast_radius: high` alone triggers it (§5), and independently reinforced by Decision E (a one-way migration promotes to full Tier F regardless of blast_radius) |
| Verdict (assessment) | `schedule` — nothing in the 42 releases is a named security fix; the real content is breaking API changes (2.36.7 removes the `offset` query param from the workflow-history endpoint and requires a JSON content type on decorator routes; 2.34.6/2.35.3 migrate the Google Ads node off its sunset v21 API) plus task-runner resilience fixes (2.33.4, 2.35.5). "Schedule" means a planned window, not urgent — but the window still needs the full backup discipline below because of the migration. |

---

## Step Zero — Verify deployment facts (do this first, before anything else)

Nothing here mutates anything; it is all read-only. Unlike Docker's and
Ollama's second-and-third sittings, **n8n has no `deployment` block on disk
yet** — this closes `PLAN-update-execution-v1.md` §7's prerequisite #2 for
n8n specifically (DB backend, `N8N_ENCRYPTION_KEY`) plus the general
container-recreate facts §7 prerequisite #1 asks for everywhere.

| Fact | How to confirm (read-only) | Recorded value |
|---|---|---|
| **Freshness of the target** | This runbook's target (`n8n@2.37.11`) was pinned from the `20260907-080001` run, confirmed above as still the latest successful run for `n8n`. Check n8n-io/n8n's GitHub releases directly for anything newer than `n8n@2.37.11` before proceeding — a few days will have passed by the time this actually runs. If something newer has shipped, note it and proceed on the pinned target anyway *unless* the new release is itself security-relevant (in which case STOP and flag it to Matt — a newer release changes the calculus a `schedule` verdict was built on) | `[VERIFY]` |
| **Image reference (tag and digest)** | `docker inspect n8n` → `Image`/`RepoDigests` — the rollback target | `[VERIFY]` |
| **DB backend** | `docker inspect n8n` → `.Config.Env` for `DB_TYPE`/`DB_SQLITE_*`/`DB_POSTGRESDB_*` vars, and `.Mounts` for the data volume. Confirm whether this is SQLite-in-volume (default, data lives in `/home/node/.n8n`) or an external Postgres — the backup step in Phase 0 differs completely depending on which | `[VERIFY]` |
| **State volume / mount path** | Volume name and in-container mount path from `.Mounts` — needed for both the backup command and the recreate command | `[VERIFY]` |
| **`N8N_ENCRYPTION_KEY` presence** | Confirm the env var **is set** on the live container. **Do not write its value to disk anywhere** — same no-secrets rule added to `PLAN-openclaw-2.0-update-v1.md` 2026-09-09, after Ollama's sitting incidentally surfaced a sibling container's live secrets in raw tool output. Record only that it is present and will be carried unchanged into the recreate command; if it is *missing* from the current container's env (i.e. n8n is relying on an auto-generated key file inside the volume instead), record that fact instead — it changes what "preserve the key" means for Phase 1 | `[VERIFY]` |
| **Container user, published port(s), restart policy** | `docker inspect n8n` — needed to reconstruct the exact recreate command | `[VERIFY]` |
| **Env var names (non-secret)** | Record names and non-secret values (e.g. `N8N_HOST`, `WEBHOOK_URL`, timezone) for the recreate reconstruction; redact anything that looks like a credential, same discipline as OpenClaw's and Ollama's sittings | `[VERIFY]` |
| **Current workflow count** | Via n8n's own UI or read-only API call (no state change) — a baseline to diff against post-update, proving the migration carried state rather than landing on an empty DB | `[VERIFY]` |
| **If Matt scripts against the n8n API** | Ask/flag rather than assume — if he has scripts calling the workflow-history endpoint with an `offset` param, or hitting decorator routes without an explicit JSON content type, those callers will break on `2.36.7`+ regardless of how clean this update runs. This is Matt's own code to check, not something this sitting can verify from the host, but it's worth surfacing again here since it's the concrete piece of "what it will take" from the assessment | `[VERIFY]` |

---

## Phase 0 — Pre-flight capture (read-only; capture before you change anything)

**0.1 — Confirm the target is pinned.** `n8n@2.37.11` (image tag
`n8nio/n8n:2.37.11` or whatever Step Zero's image reference confirms the
repo actually is) — exact, never `:latest` or `:next`.

**0.2 — Baseline health snapshot.**

```
docker ps --filter name=n8n
docker inspect --format '{{json .State.Health}}' n8n
docker logs --tail 100 n8n
```

Plus, from a normal session (no state change): `/healthz` and
`/healthz/readiness` both return 200; the workflow list loads and its count
matches Step Zero's baseline; note one safe, idempotent workflow to
re-execute in Phase 2 as the smoke test.

**0.3 — Mandatory state backup.** This is **not optional**, per §4a: because
the migration is forward-only, restoring this backup is the *only* real
rollback — re-pinning the old tag alone will not work once the new
container has upgraded the schema. Shape depends on Step Zero's DB-backend
finding:

- **If SQLite-in-volume:**
  ```
  docker run --rm -v <STATE_VOLUME>:/data -v <HOST_BACKUP_DIR>:/backup alpine tar czf /backup/n8n-2.26.0-<YYYYMMDD>.tgz -C /data .
  ```
- **If external Postgres:** use the DB's own dump tool (e.g. `pg_dump`)
  against the confirmed connection details from Step Zero, plus a separate
  backup of the volume for anything else n8n stores outside the DB
  (encryption-key file, if that's where it lives per Step Zero).

Either way, **prove it's non-empty** — archive size and a `tar tzf ... |
head` (or the dump file's size and a peek at its contents) before treating
it as real. If it's tiny, empty, or the dump fails, STOP — do not proceed to
Phase 1 on an unverified backup.

**0.4 — Confirm `N8N_ENCRYPTION_KEY` will carry over unchanged.** Whatever
Step Zero found (env var vs. key file in the volume), confirm the Phase 1
recreate command preserves it exactly. If the key changes or is dropped,
every stored credential becomes silently undecryptable — this is worse than
a failed migration because it may not surface immediately.

**0.5 — Record the prior image tag and digest** (Step Zero) — the rollback
reference, used together with the Phase 0.3 backup, never alone.

**0.6 — Flag the API-consumer check to Matt.** Note in the Phase 0 report
that if he scripts against n8n's API, he should check his own callers
against the `offset`-param removal and the JSON-content-type requirement
before or during this window — this project can't see his scripts from the
host-side facts alone.

---

## Phase 1 — Install (Matt runs; infra-watch never does)

This is a **scheduled window, not a quick swap** — treat it with the same
weight as Docker's window, not Ollama's single-installer swap. Do not bundle
this with any other component's update in the same window.

1. `docker pull` the confirmed image at the pinned tag (`n8n@2.37.11`) —
   never `:latest`.
2. Stop and remove the running `n8n` container.
3. Recreate it from the exact definition Step Zero reconstructed — same
   volume, mount path, env (including the **unchanged**
   `N8N_ENCRYPTION_KEY`), ports, restart policy; only the tag changes.
4. Let it come up on its own restart policy; watch the startup log for the
   migration to complete.

---

## Phase 2 — Verify (read-only; this phase decides go-forward vs. roll back)

Not "verified" until **all** of these pass:

- **Container is `Up` and healthy** — `docker ps`/`docker inspect` health
  status, not `starting`/`unhealthy`.
- **`/healthz` and `/healthz/readiness` both return 200.**
- **The startup log shows the migration completed without error** — this is
  the go/no-go signal for n8n specifically, same shape as OpenClaw's
  "manual repair" check. Look for the migration-complete line, not just
  absence of a crash.
- **Workflow list loads and its count matches Step Zero's baseline** — proves
  the migration carried real state, not an empty store.
- **The one safe, idempotent workflow (chosen in Phase 0.2) executes
  successfully** — the concrete smoke test.
- **If Matt has API scripts**, confirm with him that they still work against
  the new version — this project can report the API surface changed, but
  can't test his own callers for him.

If all pass, the update stands. If any fail, go to Phase 3.

---

## Phase 3 — Resolve (if verify fails)

1. **A wrinkle the assessment predicted** — the `offset`-param removal or the
   JSON-content-type requirement breaking a caller is exactly what the
   assessment named; the fix is in Matt's own script, not a regression in
   n8n. Same for the Google Ads node's v21-API sunset, if he has a Google
   Ads workflow depending on it.
2. **A dependency break, not an n8n break** — the container is healthy but
   can't reach an external Postgres, or a webhook URL is now wrong post-
   recreate. Fix that specific link.
3. **The migration itself failed, or an unknown regression** — do not fight
   it live. Go to Phase 4 immediately; the longer the new (possibly
   half-migrated) container runs, the messier a restore becomes.

---

## Phase 4 — Rollback (Matt runs)

**Re-pinning the old tag alone is not a rollback for n8n** (§4a) — the
migration is forward-only, so this is always a two-step restore:

1. Stop and remove the new container.
2. Restore the Phase 0.3 backup (the SQLite volume tarball, or the Postgres
   dump plus any separately-backed-up files) into the *verified* volume/DB —
   not a guess at the path.
3. Recreate the container from the old pinned tag (`2.26.0`) with the exact
   prior definition (same volume, mount path, env including the original
   `N8N_ENCRYPTION_KEY`, ports, restart policy).
4. Re-run Phase 2's verify against the restored container to confirm the
   rollback itself landed clean — workflow count matches the pre-update
   baseline, the smoke-test workflow still executes.

---

## Retention

7-day artifact window (Decision D) applies to the Phase 0 backup (tarball or
DB dump) and the Phase 0/Phase 2 capture files this project generates.

## Gate

`blast_radius: high`, plus a forward-only migration named in the assessment
→ **Tier F, always** (both paths in §5's table point here independently).
This is n8n's own first sitting under the update-execution flow, so per
`TIERS.md`'s promotion rule it runs at F regardless of how cleanly Docker's,
OpenClaw's, or any other component's run went — promotion is per-component,
never inherited.

## Source

Raw release notes this verdict was drawn from:
https://github.com/n8n-io/n8n/releases/tag/n8n%402.37.11

---

_This runbook is generated from a model's assessment and this project's own
read-only host discovery (once Step Zero is closed) — advisory input to
Matt's decision, not a substitute for it. Every install and rollback step
above is Matt's hand action; infra-watch performs only the read-only
capture and verify steps._
