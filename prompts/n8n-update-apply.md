# infra-watch — n8n update apply (semi-automated handoff)

**Paste the block below into a Claude Code sitting.** This is the last of
the three originally-named components in the update-execution sequence
(Docker Engine → OpenClaw → n8n), and — like OpenClaw's — the state backup
in Phase 0 is **mandatory, not optional**: n8n's startup migrations are
forward-only, so re-pinning the old image tag alone is not a rollback once
the new container has upgraded the schema. n8n also has no `deployment`
block on disk yet, so this prompt's first chunk is read-only *discovery*
(Step Zero from `records\runbooks\n8n.md`), same shape as Ollama's and
OpenClaw's first sittings — not just closing out known facts. Read
`records\runbooks\n8n.md` in full before running any of this; it is the
runbook, Step Zero included, and this prompt does not restate its detail.
Written 2026-09-09 in Cowork, after Node (F→E), Ollama (its own first clean
F run), and Docker Engine (29.6.1→29.7.2, target-miss surprise, stays at F)
all landed.

**Same no-secrets-to-disk rule as OpenClaw's sitting.** n8n's own
`.Config.Env` is where `N8N_ENCRYPTION_KEY` lives — if it's set as a
container env var rather than derived from a key file in the volume, do not
write its value anywhere. Record only that it's present and that Phase 1's
recreate command carries it over unchanged; redact anything that looks like
a credential in every artifact this sitting produces — `inventory.json`,
this project's `STATE.md`/`SESSION-LOG.md`, chunk reports, the commit.

---

infra-watch — n8n update apply (semi-automated: read-only Step Zero + Phase 0/2 automated, install/rollback stay Matt's).

BEFORE YOU ACT. Disk is authoritative. Read: CLAUDE.md, STATE.md,
PLAN-update-execution-v1.md (§4a's container class in full — it's written
around n8n specifically, §5 the gate, §7 prerequisite #2, §8 Decision E),
and `records\runbooks\n8n.md` in full — it **is** this sitting's runbook
(Step Zero, Phase 0-4), not just background. Also read
records\runbooks\docker.md and scripts\docker-update-check.ps1 as the most
recent proven shape for a mandatory-backup, migration-hazard sitting, though
n8n's flow has real differences (single container, not a whole-fleet bounce;
a DB migration, not a config wrinkle) — don't force-fit Docker's script
structure where it doesn't apply. `PLAN-openclaw-2.0-update-v1.md` is also
useful background: n8n's forward-only-migration hazard is the same shape as
OpenClaw's one-way SQLite migration, just for a different container.

Discipline: run commands verbatim, show raw output. `pwsh -File`, never
`powershell`. You are READ-ONLY except for records\/config\ edits and one new
scripts\ file — you never run `docker pull`, `docker run`, `docker stop`,
`docker rm`, or any n8n container command yourself; all of those are on the
deny-list and are Matt's hand actions, every one of them. Never widen the
deny-list. Disk is source of truth; Discord is a mirror. And: never write a
secret env-var value to disk (see above) — this rule applies to every
artifact this sitting produces, not just inventory.json.

CHUNK A — Step Zero + Phase 0 (automated, read-only). Do all of this, then STOP.

1. **Freshness check first, before anything else.** This runbook's target
   (`n8n@2.37.11`) was pinned from the `20260907-080001` run — confirmed as
   the latest successful run for `n8n` as of this writing, but several days
   may have passed by the time this actually runs. Check n8n-io/n8n's GitHub
   releases directly for anything newer than `n8n@2.37.11`. If nothing newer
   has shipped, proceed with the pinned target and note that you checked. If
   something newer has shipped, only STOP and report it to Matt if the new
   release is itself security-relevant — this update's `schedule` verdict
   was built on "no security content in these 42 releases," and a newer
   release changes that math. A routine bug-fix release beyond the target
   doesn't need to stop the sitting; note it and proceed on the pinned
   target, same discipline as reporting rather than silently retargeting.
2. Run `docker inspect n8n` and close every Step Zero row: image reference
   (tag **and** digest — the rollback target), DB backend (SQLite-in-volume
   vs external Postgres — read `.Config.Env` for `DB_TYPE`/`DB_SQLITE_*`/
   `DB_POSTGRESDB_*`, and `.Mounts` for the data volume), state volume name
   and in-container mount path, `N8N_ENCRYPTION_KEY` presence (**do not
   record its value** — see above; if it's absent from env, check whether
   it's instead derived from a file inside the volume and record that
   instead), container user, published port(s), restart policy, and env var
   **names** (redact secret values). Reconstruct the exact `docker run`/
   compose definition this container was created from. Write a `deployment`
   block onto the `n8n` entry in `config\inventory.json` (allow-listed),
   mirroring Ollama's and OpenClaw's shape — with credential values
   redacted.
3. Confirm the target `n8n@2.37.11` is what's actually being pulled — never
   `:latest` or `:next`. If anything says otherwise, STOP.
4. Run Phase 0.2's baseline health snapshot: `docker ps --filter name=n8n`,
   `docker inspect --format '{{json .State.Health}}' n8n`, `docker logs
   --tail 100 n8n`. Separately, from a normal session (no state change):
   confirm `/healthz` and `/healthz/readiness` both return 200, the workflow
   list loads, and record its current count. Pick one safe, idempotent
   workflow to re-execute in Phase 2 as the smoke test. These are Phase 2's
   pass criteria — write down what "good" looks like today.
5. Run Phase 0.3's **mandatory** state backup, shaped by whichever DB
   backend Step Zero found:
   - **SQLite-in-volume:**
     ```
     docker run --rm -v <STATE_VOLUME>:/data -v <HOST_BACKUP_DIR>:/backup alpine tar czf /backup/n8n-2.26.0-<YYYYMMDD>.tgz -C /data .
     ```
   - **External Postgres:** use the DB's own dump tool against the confirmed
     connection details, plus a volume backup for anything else n8n stores
     outside the DB.
   Then **prove it's non-empty** before treating it as a real backup — check
   archive/dump size and peek at its contents (`tar tzf ... | head`, or the
   dump file's head). If it's tiny, empty, or the dump fails, STOP — do not
   proceed to Chunk A step 6 or hand Matt an install command on an
   unverified backup.
6. Record the prior image tag and digest (Step Zero) alongside the backup —
   this is the rollback reference, used together with the backup, never
   alone (re-pinning the old tag by itself does not undo a forward-only
   migration).
7. Write `scripts\n8n-update-check.ps1` (new file → `ask`-gated) with
   `-Phase capture`/`-Phase verify` mirroring the shape of
   `docker-update-check.ps1`/`ollama-update-check.ps1`, but capturing this
   component's actual Phase 0/2 checks: container up/healthy, `/healthz`
   and `/healthz/readiness` status codes, log-tail content (for the
   migration-completed signal — this may need a substring check on the log
   text, not just an exit code), workflow-list count, and the chosen
   smoke-test workflow's execution result. Model the pass/fail definition on
   the migration-completion signal specifically, per the runbook's Phase 2 —
   a clean log with the migration-complete line present, not just
   "container is Up."
8. Report Step Zero's findings, the backup's proof-of-contents, the Phase 0
   capture, and a reminder to Matt about the API-consumer check (the
   removed `offset` param on the workflow-history endpoint, the JSON-
   content-type requirement on decorator routes, and the Google Ads v21-API
   sunset — all from the assessment; his own scripts/workflows are his to
   check, not something this sitting can verify from the host). Then STOP.
   Hand Matt the exact two commands for Phase 1 — `docker pull
   <IMAGE_REPO>:n8n@2.37.11` (or whatever tag format Step Zero's image
   reference confirms) and the full recreate command reconstructed from
   Step Zero (same volume, mount path, user, port, env including the
   unchanged `N8N_ENCRYPTION_KEY`, restart policy; only the tag changed) —
   for him to review and run himself. Tell him to reply "installed" when
   done.

[MATT'S ACTION: pull + recreate the container by hand, then reply "installed".]

CHUNK B — verify and record (automated). On "installed":

9. Run Phase 2 verify (`scripts\n8n-update-check.ps1 -Phase verify`):
   container up/healthy; `/healthz`/`/healthz/readiness` both 200; startup
   log shows the migration completed without error (the go/no-go signal —
   an error or a stalled/crash-looping container is the one condition that
   routes to Phase 3, not a routine outcome); workflow list count matches
   the Phase 0 baseline (proves the migration carried state, not an empty
   store); the chosen smoke-test workflow executes successfully.
10. If PASS: update the `n8n` deployment block (installed → `n8n@2.37.11`,
    new image digest, prior tag/digest kept as the rollback reference,
    backup archive/dump path and hash), update `STATE.md` and
    `SESSION-LOG.md` noting this is *n8n's own* first clean Tier-F run under
    this flow (promotion is per-component — it doesn't inherit Docker's,
    OpenClaw's, or Ollama's), and remind Matt in the report to check his own
    API scripts/workflows against the two breaking changes named in the
    assessment. Commit (`ask`-gated), scoped to exactly the files this
    sitting changed. Double-check the diff before committing that no secret
    value made it into any changed file.
11. If FAIL: triage per the runbook's Phase 3 — a wrinkle the assessment
    predicted (the API changes, or the Google Ads sunset) is Matt's own
    script to fix, not a regression here; a dependency break (e.g. an
    external Postgres unreachable, a webhook URL wrong post-recreate) means
    fix that specific link. For a failed or stalled migration, or any other
    unknown regression, do not fight it live — present Matt the Phase 4
    rollback: stop → remove the new container → restore the Phase 0.3
    backup into the *verified* volume/DB → recreate from the old pinned tag
    with the exact prior definition (including the original
    `N8N_ENCRYPTION_KEY`) → re-run Phase 2 against the restored container to
    confirm the rollback itself landed clean. All of Phase 4 is Matt's hand
    action.

STOP conditions (hard): any Step Zero row unconfirmable; the Phase 0.3
backup/dump is empty, tiny, or unverified; target isn't pinned exact
`n8n@2.37.11`; a secret value (especially `N8N_ENCRYPTION_KEY`) about to be
written to any file; verify FAIL for a reason the release notes didn't
predict (→ rollback guidance, don't fix live); any impulse to run `docker
pull/run/stop/rm` yourself, or to widen the deny-list.
