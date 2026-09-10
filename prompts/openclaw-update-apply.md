# infra-watch — OpenClaw 2.0 update apply (semi-automated handoff)

**Paste the block below into a Claude Code sitting.** This is the third
component in the update-execution sequence and the first Docker container
(Node and Ollama were both native-host). It's also meaningfully heavier than
either: `medium` blast_radius promoted to full Tier F by the one-way SQLite
migration (`PLAN-update-execution-v1.md` §8 Decision E), and — unlike
Ollama — the state backup in Phase 0 is **mandatory, not optional**, because
the migration cannot be undone by re-pinning the old tag alone. Read
`PLAN-openclaw-2.0-update-v1.md` in full before running any of this; it is
the runbook, Step Zero included, and this prompt does not restate its detail.
Written 2026-09-09 in Cowork, after Node (F→E) and Ollama (its own first
clean F run) both landed clean.

**Before you paste this: re-read `PLAN-openclaw-2.0-update-v1.md`'s Step
Zero table one more time.** It was amended today (2026-09-09) to add a rule
that didn't exist when it was first drafted: **never write a secret env-var
value to disk.** Ollama's sitting this week checked a *sibling* container's
env for a base-URL setting and incidentally surfaced that container's live
Telegram bot token and gateway password in raw tool output — harmless only
because nothing was recorded. Here you are reading `openclaw`'s **own**
`.Config.Env`, which is exactly where its Telegram bot token, gateway
password, and any API keys live. Record variable names and non-secret
values (bind mode, port, backend URL) into `inventory.json`; redact anything
that looks like a credential everywhere — the deployment block, this
project's `STATE.md`/`SESSION-LOG.md`, your own chunk reports, the commit.

**Retargeted 2026-09-09, same sitting as the freshness check below actually
ran.** The freshness check found `v2026.9.1`/`.2`/`.3` all shipped after
`v2026.8.2` was pinned; none named a security fix, and `v2026.9.3`'s
breaking changes are plugin-SDK/non-Docker-install-facing only, not a
change to the 2.0 migration itself. Matt reviewed this and approved
retargeting to the newest release — every `v2026.8.2` reference below and
in the runbook now means the `v2026.9.3` release. Step Zero also picked up
one new row from this: confirm whether `openclaw` has any plugin installed,
since the SDK breaking changes could affect one (closed via the baseline
log tail, without crossing the OpenClaw-config boundary — see the runbook).

**Tag-format correction, same sitting.** GitHub's release tag is
`v2026.9.3`; Docker Hub's actual image tag is `2026.9.3`, no `v` — checked
against the Hub API directly rather than assumed, matching how the
currently-running image is tagged `2026.7.1`, also without a `v`. Every
command below naming the Docker image tag uses `2026.9.3`.

**Backup-step correction, same sitting.** Step 6 below originally read as
if this sitting runs the Phase 0.3 backup command itself. It can't: that
command is `docker run --rm -v ... alpine tar czf ...`, and `docker run` is
unconditionally on this project's deny-list — no carve-out for backups,
per this very prompt's own Discipline paragraph below and CLAUDE.md. The
backup is Matt's hand action, handed to him *before* the Phase 1 pull/
recreate commands, not bundled with them. Verifying it afterward (size,
`tar tzf`-equivalent contents) is done with Windows' own `tar.exe` — no
Docker needed for that half.

---

infra-watch — OpenClaw 2.0 update apply (semi-automated: read-only Step Zero + Phase 0/2 automated, install/rollback stay Matt's).

BEFORE YOU ACT. Disk is authoritative. Read: CLAUDE.md, STATE.md,
PLAN-update-execution-v1.md (§4a's container class, §5 the gate, §8 Decision
E), and `PLAN-openclaw-2.0-update-v1.md` in full — it **is** this sitting's
runbook (Step Zero, Phase 0-4), not just background. Also read
records\runbooks\ollama.md and scripts\ollama-update-check.ps1 as the most
recent proven shape, though openclaw's flow has real differences (container,
not host binary; mandatory backup; migration) — don't force-fit Ollama's
script structure where it doesn't apply.

Discipline: run commands verbatim, show raw output. `pwsh -File`, never
`powershell`. You are READ-ONLY except for records\/config\ edits and one new
scripts\ file — you never run `docker pull`, `docker run`, `docker stop`,
`docker rm`, or the `doctor --fix`/`update cleanup` containers yourself; all
of those are on the deny-list and are Matt's hand actions, every one of them.
Never widen the deny-list. Disk is source of truth; Discord is a mirror. And:
never write a secret env-var value to disk (see above) — this rule applies to
every artifact this sitting produces, not just inventory.json.

CHUNK A — Step Zero + Phase 0 (automated, read-only). Do all of this, then STOP.

1. **Freshness check first, before anything else.** This runbook's original
   target (`v2026.8.2`) was pinned from an assessment written 2026-09-04 —
   the 2026-09-07 weekly run's attempt to reassess `openclaw` failed (hit
   the spend cap), so it was several days old and never refreshed.
   **Done, 2026-09-09:** checked openclaw/openclaw's GitHub releases
   directly (not a summary) and found `v2026.9.1` (2026-09-03), `v2026.9.2`
   (2026-09-05), and `v2026.9.3` (2026-09-08) had all shipped since. Per
   this step's own rule, stopped and reported to Matt rather than silently
   retargeting or proceeding stale. None of the three names a security fix;
   `v2026.9.3` lists several breaking changes, all plugin-SDK or
   non-Docker-install-facing, not a change to the 2.0 migration itself.
   Matt reviewed and explicitly approved moving to the newest release —
   **the target for the rest of this sitting is `2026.9.3`** (Docker image
   tag; GitHub calls the release `v2026.9.3` — see the tag-format note
   above), not `v2026.8.2`. The runbook has been updated to match
   throughout.
2. Run `docker inspect openclaw` and close every Step Zero row: image
   reference (tag **and** digest — the rollback target), state volume name,
   in-container mount path, container user (confirm `node`/`/home/node/
   .openclaw` vs. a `-u root`/`/root/.openclaw` mismatch — this is the
   silent-data-skip trap the runbook calls out), published port(s),
   restart policy, and env var **names** (redact secret values per the note
   above). Reconstruct the exact `docker run`/compose definition this
   container was created from. Write a `deployment` block onto the
   `openclaw` entry in `config\inventory.json` (allow-listed), mirroring
   Node's and Ollama's shape — with credential values redacted.
3. Flag, don't silently resolve, either security item from the runbook's
   Phase 1.3 "Security posture" section if Step Zero finds it already set:
   `OPENCLAW_GATEWAY_BIND=lan`, or any indication `--accept-capabilities`
   was used for a plugin. Report these to Matt explicitly rather than
   deciding for him.
4. Confirm the target `2026.9.3` (Docker image tag, no `v`) is what's
   actually being pulled — never `:latest`. If anything says otherwise,
   STOP.
5. Run Phase 0.2's baseline health snapshot: `docker ps --filter
   name=openclaw`, `docker inspect --format '{{json .State.Health}}'
   openclaw`, `docker logs --tail 100 openclaw`. Separately, from a normal
   session, confirm and record: Control UI loads at the verified port, a
   known-good query to the local model returns sane output, Discord is
   connected. These are Phase 2's pass criteria — write down what "good"
   looks like today.
6. Phase 0.3's **mandatory** state volume backup is Matt's hand action, not
   this sitting's — the command is a `docker run`, unconditionally
   deny-listed here. Construct it using the *verified* volume name — not a
   guess — and hand it to Matt before anything else in Phase 1:
   ```
   docker run --rm -v <STATE_VOLUME>:/data -v <HOST_BACKUP_DIR>:/backup alpine tar czf /backup/openclaw-<FROM_VERSION>-<YYYYMMDD>.tgz -C /data .
   ```
   Once he confirms he's run it, **prove it's non-empty** before treating it
   as a real backup — this half *can* be done without Docker: check the
   archive size and list its contents with Windows' own `tar.exe -tzf`
   (bsdtar, ships with Windows 10/11) to confirm real files are listed. If
   it's tiny or empty, STOP — do not proceed to Chunk A step 7 or hand Matt
   an install command on an empty backup.
7. Record the prior image tag and digest (Step Zero) alongside the backup —
   this is the rollback reference.
8. Write `scripts\openclaw-update-check.ps1` (new file → `ask`-gated) with
   `-Phase capture`/`-Phase verify` mirroring the shape of
   `node-update-check.ps1`/`ollama-update-check.ps1`, but capturing this
   component's actual Phase 0/2 checks: container up/healthy, log-tail
   content (for the migration-completed / gateway-listening signal — this
   may need a substring check on the log text, not just an exit code),
   Control UI reachability, the known-good local-model query, and a Discord
   round-trip. Model the pass/fail definition on the migration-completion
   signal specifically, per the runbook's Phase 2 — a clean log with no
   "manual repair" text, not just "container is Up."
9. Report Step Zero's findings, the backup's proof-of-contents, and the
   Phase 0 capture, then STOP. Hand Matt the exact two commands for Phase
   1 — `docker pull <IMAGE_REPO>:2026.9.3` and the full recreate command
   reconstructed from Step Zero (same volume, mount path, user, port, env,
   restart policy; only the tag changed) — for him to review and run
   himself. Tell him to reply "installed" when done.

[MATT'S ACTION: pull + recreate the container by hand, then reply "installed".]

CHUNK B — verify and record (automated). On "installed":

10. Run Phase 2 verify (`scripts\openclaw-update-check.ps1 -Phase verify`):
    container up/healthy; startup log shows the migration completed without
    error and the gateway listening (the go/no-go signal — a "manual repair"
    message is the one condition that routes to Phase 3, not a routine
    outcome); Control UI reachable with prior sessions visible (proves the
    migration carried state, not an empty store); known-good query to the
    local model; Discord reconnect round-trip.
11. If PASS: **do not run `openclaw update cleanup`** — that's a one-way
    door and Phase 4 is explicit that it waits for a soak period Matt
    chooses, not this sitting. Update the `openclaw` deployment block
    (installed → `2026.9.3`, new image digest, prior tag/digest kept as
    the rollback reference, backup archive path/hash), update `STATE.md`
    and `SESSION-LOG.md` noting this is *openclaw's own* first clean
    Tier-F run under this flow (promotion is per-component — it doesn't
    inherit Node's or Ollama's) and that the target was moved to the
    `v2026.9.3` release mid-sitting per Matt's approval, and commit
    (`ask`-gated), scoped to exactly the files this sitting changed.
    Double-check the diff before committing that no secret value made it
    into any changed file.
12. If FAIL: triage per the runbook's Phase 3 — **only** if the gateway
    exited asking for manual repair, present Matt the one-shot `doctor
    --fix` command (`docker run --rm -v <STATE_VOLUME>:...`, **not**
    `docker exec -it`) for him to run; for any other failure, or if repair
    doesn't resolve it, do not fight it live — present the Phase 4 rollback
    commands (stop → rm → restore the Phase 0 tarball into the *verified*
    volume → re-pin the prior image tag/digest) and STOP. All of Phase 3's
    repair and all of Phase 4 are Matt's hand actions; re-run Phase 2 after
    either to confirm it actually landed.

STOP conditions (hard): any Step Zero row unconfirmable; the Phase 0.3
backup archive is empty, tiny, or unverified; target isn't pinned exact
`2026.9.3`; `OPENCLAW_GATEWAY_BIND=lan` or `--accept-capabilities` found
and not explicitly flagged to Matt; a secret value about to be written to
any file; verify FAIL for a reason the release notes didn't predict (→
rollback guidance, don't fix live); any impulse to run `docker pull/run/
stop/rm`, `doctor --fix`, or `update cleanup` yourself, or to widen the
deny-list.
