# infra-watch — OpenClaw 2.0 update runbook (v2026.7.1 → v2026.8.2)

> **STATUS: DRAFT RUNBOOK — do not execute until every `[VERIFY]` value in
> Step Zero is confirmed against the live host. Pending Matt's review; nothing
> here has been adopted or run.** Written 2026-09-08 as a review draft only. No
> script, config, container, or live component was touched producing it.
> infra-watch does not apply updates — **every mutating command below is run by
> Matt by hand**, one at a time, and only after Step Zero is filled in. This
> file is read-and-recommend output, exactly like the rest of the project.

This is the first concrete instance of the five-phase apply loop proposed in
`PLAN-update-execution-v1.md` (**capture → install → verify → resolve →
rollback**), applied to a single Docker container: `openclaw`. It assumes that
plan and `STATE.md` as read and does not restate them.

**Why so many placeholders.** infra-watch's `read-installed.ps1` keeps only
version strings — it runs `docker inspect` but discards the volume name, mount
path, container user, published port, image reference, and env vars. Those
facts are therefore **not on disk**, and a runbook built on guessed values is
worse than no runbook (a guessed volume name silently backs up nothing — see
Phase 0). So every deployment-specific value below is a `[VERIFY]` placeholder
that Step Zero fills in from the running container. Follow the project rule:
*use the fact, not a proxy for it* — read each value from `docker inspect` on
the live host, never from this document or any other document.

| Field | Value |
|---|---|
| Component | `openclaw` (Docker container) |
| Version moving **from** | `[VERIFY]` — assessment `20260904-053532` recorded `2026.7.1`; confirm against the running image, do not trust this line |
| Version moving **to** (pinned) | **`v2026.8.2`** — the OpenClaw 2.0 line at its current patch (2.0 == `v2026.8.1`; `.2` is the patch). Pin this exact tag; **never `:latest`** |
| `blast_radius` | `medium` (from `inventory.json`) — **but** this update carries a one-way state migration, so treat the window as Tier **F** (full gate), per `PLAN-update-execution-v1.md` §8 Decision E |
| What 2.0 changes about state | Migrates sessions/transcripts into a **SQLite** store under the container's OpenClaw home dir (`[VERIFY]` mount — official default `/home/node/.openclaw`). The migration is **forward-only**; the pre-migration originals are retained until an explicit cleanup step (see Phase 4) |

---

## Step Zero — Verify deployment facts (do this first, before anything else)

Nothing here mutates anything; it is all read-only and Matt can run it now.
**Every later command in this runbook references the values recorded here, not
guesses.** If any row cannot be filled in, stop — the rest of the runbook is
not yet safe to run.

Run, on the live host:

```
docker inspect openclaw
```

From that output, record the **real** values (the JSON paths shown are where
to look):

| Fact | Where in `docker inspect` | Recorded value |
|---|---|---|
| **Image reference (current / prior)** — tag **and** digest | `.[0].Config.Image` and `.[0].Image` / `.[0].RepoDigests` | `[VERIFY]` ⟵ this is the rollback target; record it exactly |
| **State volume name(s)** | `.[0].Mounts[]` → `Name` (type `volume`) or `Source` (type `bind`) | `[VERIFY]` |
| **State mount path (in-container)** | `.[0].Mounts[]` → `Destination` | `[VERIFY]` — official default is `/home/node/.openclaw` (see note below) |
| **Container user** | `.[0].Config.User` | `[VERIFY]` — official default is `node`, not `root` (see note below) |
| **Published port(s)** | `.[0].NetworkSettings.Ports` / `.[0].HostConfig.PortBindings` | `[VERIFY]` |
| **Env vars** (esp. any `OPENCLAW_*`, bind/gateway, model backend) | `.[0].Config.Env` | `[VERIFY]` — note any `OPENCLAW_GATEWAY_BIND`; see Security posture |
| **Restart policy** | `.[0].HostConfig.RestartPolicy` | `[VERIFY]` |
| **`docker run`/compose definition** it was created from | your compose file, or reconstruct from the above | `[VERIFY]` |

**Container user / state path — a correction that matters.** OpenClaw's
official Docker docs run the container as the **`node`** user with state at
**`/home/node/.openclaw`**. A popular third-party procedure instead runs
`-u root` with state at `/root/.openclaw`. These are different locations. If
your recreate mounts the state volume at the wrong path for the user the image
actually runs as, **2.0 can boot into an empty home dir, find no prior state,
and migrate nothing** — a silent data-skip, not an error. Do **not** infer the
user or path from the image name or from this doc: read `.Config.User` and the
mount `Destination` from *your* `docker inspect` output and match them exactly
in every command below. Record the official defaults (`node`,
`/home/node/.openclaw`) only as a sanity check against what you see.

---

## Phase 0 — Pre-flight capture (read-only; capture before you change anything)

The goal of this phase is that a rollback target and a verification baseline
both exist *before* the first mutating command. Nothing here changes the
running container.

**0.1 — Confirm the target is a pinned, explicit version.** The pull in
Phase 1 must reference `v2026.8.2` exactly. If anything in the plan says
`:latest`, stop and fix it — an unpinned target leaves the rollback version
undefined and defeats this whole runbook.

**0.2 — Baseline health snapshot (the same checks Phase 2 re-runs).** Capture
now, while things are known-good, so "did it break" is measured against a real
baseline and not a memory:

```
docker ps --filter name=openclaw                 # is it Up? note status/health
docker inspect --format '{{json .State.Health}}' openclaw   # if a healthcheck exists
docker logs --tail 100 openclaw                   # save a copy of a clean log tail
```

Also record, from a normal working session: the Control UI loads at the
`[VERIFY]` published port; a known-good query to the local model returns sane
output; Discord is connected. These are the Phase 2 pass criteria — write down
what "good" looks like today.

**0.3 — Back up the state volume (mandatory, and verify it is non-empty).**
Because the 2.0 migration is forward-only, this backup is the independent
rollback floor. Using the **verified** volume name from Step Zero:

```
docker run --rm ^
  -v <STATE_VOLUME>:/data ^
  -v <HOST_BACKUP_DIR>:/backup ^
  alpine tar czf /backup/openclaw-<FROM_VERSION>-<YYYYMMDD>.tgz -C /data .
```

> **The silent-empty-backup trap.** If `<STATE_VOLUME>` is misspelled or does
> not exist, `docker run -v <name>:/data` **creates a brand-new empty volume**
> and the `tar` happily archives **zero bytes** — you get a valid-looking
> `.tgz` that contains nothing. So this step is not done until you have
> confirmed **both**: (1) the volume name came from Step Zero's `docker inspect`
> output, and (2) the resulting archive is a non-trivial size and actually
> contains the state:
>
> ```
> dir <HOST_BACKUP_DIR>\openclaw-<FROM_VERSION>-<YYYYMMDD>.tgz   # size, not a few hundred bytes
> docker run --rm -v <HOST_BACKUP_DIR>:/backup alpine ^
>   tar tzf /backup/openclaw-<FROM_VERSION>-<YYYYMMDD>.tgz | head   # real files listed
> ```
>
> If the archive is tiny or lists nothing, **stop** — the volume name is wrong.
> Do not proceed to Phase 1 on an empty backup.

**0.4 — Record the prior image tag and digest** (from Step Zero) alongside the
backup. Rollback re-pins *this exact reference*; if it isn't written down now,
rollback later is guesswork.

---

## Phase 1 — Install (Matt runs; infra-watch never does)

One component, one window. All commands here are on infra-watch's deny-list by
design — Matt runs each one by hand.

**1.1 — Pull the pinned target.** Use the exact tag; **do not `docker pull`
`:latest`**:

```
docker pull <IMAGE_REPO>:v2026.8.2        # <IMAGE_REPO> from Step Zero, tag pinned
```

**1.2 — Recreate the container from an identical definition, changing only the
tag.** Same volume(s), same mount path, same user, same port, same env,
same restart policy — all the `[VERIFY]` values from Step Zero. The only delta
from the running definition is the image tag → `v2026.8.2`. Mounting the state
volume at the same path the recorded `.Config.User` expects is what lets 2.0
find the existing state and migrate it (Step Zero note).

**1.3 — Let the gateway do its own startup migration.** On first boot of 2.0
the gateway performs a **startup-safe** migration of sessions/transcripts into
SQLite by itself. Watch the startup log (Phase 2) rather than reaching for
`doctor --fix` reflexively — see Phase 3 for when that is and isn't needed.

**Security posture — confirm before using either of these:**

- **`--accept-capabilities`.** If any step installs or updates a plugin with
  `openclaw plugins install ... --accept-capabilities`, that flag
  **auto-accepts the plugin's capability grants** with no prompt. Do not carry
  it over blindly; review what capabilities are being granted first.
- **`OPENCLAW_GATEWAY_BIND=lan`.** Setting the gateway bind to `lan` **broadens
  network exposure** and cuts directly against the **tailnet-only** posture you
  set up for open-webui. Do not introduce it as part of this update. If Step
  Zero shows it already set, flag it for a deliberate decision rather than
  silently preserving or changing it — read the actual value from
  `.Config.Env`, don't assume a default from its absence.

---

## Phase 2 — Verify (read-only; this phase decides go-forward vs. roll back)

Re-run the Phase 0 baseline checks and diff against them. The container update
is not "verified" until all of these pass:

- **Container up and healthy.** `docker ps --filter name=openclaw` shows `Up`;
  if a healthcheck exists, `docker inspect` shows `healthy`, not `starting` /
  `unhealthy`.
- **Startup log is clean, migration completed.**
  ```
  docker logs --tail 200 openclaw
  ```
  The log shows the SQLite migration **completed without error** and the
  gateway listening. This is the go/no-go signal. If the gateway instead
  **exits asking for manual repair**, that is the one condition that sends you
  to Phase 3 — not a routine expectation.
- **Control UI reachable.** The UI loads at the `[VERIFY]` published port and
  shows the prior sessions/transcripts (confirming the migration carried state,
  not an empty store).
- **Known-good query to the local model.** Run the same query you baselined in
  Phase 0 against the local model backend; it returns sane output within normal
  latency.
- **Discord reconnect test.** OpenClaw reconnects to Discord and a round-trip
  message works, matching the Phase 0 baseline.

If all pass, the update stands. **Do not run any cleanup step yet** (Phase 4
explains why). If any fail, go to Phase 3.

---

## Phase 3 — Resolve (only if Phase 2 failed)

`doctor --fix` is **conditional, not a mandatory second pass.** Per the
official docs, routine upgrades usually do **not** need a separate doctor pass
— the gateway performs the startup-safe migration itself and only exits asking
for manual repair when the state actually needs it. So:

- **If Phase 2's log showed a clean migration and the gateway is up** — you are
  done. Do not run `doctor --fix` "just in case."
- **If, and only if, the gateway exited asking for manual repair** (flagged
  conflicts from the 2.0 breaking migrations that need manual completion), run
  the official one-shot repair against the **verified** state volume:

  ```
  docker run --rm -v <STATE_VOLUME>:/home/node/.openclaw <IMAGE_REPO>:v2026.8.2 openclaw doctor --fix
  ```

  Use the **recorded** mount path for the user the image runs as (Step Zero);
  `/home/node/.openclaw` shown here is the official default, not an assumption
  to carry blindly. This is a **one-shot `docker run --rm`**, **not**
  `docker exec -it`. Claims that a TTY (`-it`) is required, or that two doctor
  passes are needed, are **unverified third-party claims** — treat them as such
  and prefer the documented one-shot form.

After a repair, **re-run all of Phase 2**. If it still fails, or the failure is
an unknown regression rather than a documented migration conflict, do not fight
it live — go to Phase 4.

---

## Phase 4 — Rollback (Matt runs)

There are **two independent rollback layers.** Understand both before you touch
the first one.

**Layer (a) — OpenClaw's own retained originals.** OpenClaw 2.0 **retains the
pre-migration originals** after migrating. They stay in place until an
explicit, separate cleanup step deletes them — at which point rollback via this
layer is permanently surrendered. Therefore:

- **Do NOT run `openclaw update cleanup` until 2.0 is proven stable** in normal
  use over your chosen soak period. That command is a one-way door.
- To see what cleanup *would* remove without removing it:
  ```
  docker run --rm -v <STATE_VOLUME>:/home/node/.openclaw <IMAGE_REPO>:v2026.8.2 openclaw update cleanup --dry-run
  ```
  Keep this as a preview only. Running the non-`--dry-run` form is out of scope
  for this update window.

**Layer (b) — the manual volume tarball (concrete restore below).** This is the
self-sufficient floor from Phase 0.3 and does not depend on layer (a). Restore
procedure, in order:

1. **Stop the new container:**
   ```
   docker stop openclaw
   ```
2. **Remove it:**
   ```
   docker rm openclaw
   ```
3. **Restore the Phase 0 tarball into the verified volume** (this overwrites
   the migrated state with the pre-migration originals):
   ```
   docker run --rm ^
     -v <STATE_VOLUME>:/data ^
     -v <HOST_BACKUP_DIR>:/backup ^
     alpine sh -c "rm -rf /data/* && tar xzf /backup/openclaw-<FROM_VERSION>-<YYYYMMDD>.tgz -C /data"
   ```
   Use the **same verified volume name** as the backup — the empty-volume trap
   applies in reverse: a wrong name restores into nothing.
4. **Re-pin and run the PRIOR image** — the exact tag/digest recorded in
   Step Zero / Phase 0.4 — with the **same** volume, mount path, user, port,
   env, and restart policy as before:
   ```
   docker run ... <IMAGE_REPO>:<PRIOR_TAG_OR_DIGEST> ...
   ```
5. **Restart and verify the restore is itself good** — re-run **all of
   Phase 2** against the old version. A rollback isn't done until it has been
   verified back to the Phase 0 baseline.

A run of this whole loop is not "done" until **either** Phase 2 passed on
`v2026.8.2`, **or** a rollback was performed and itself verified back to the
Phase 0 baseline.

---

## Post-update health checks (summary — the concrete pass set)

The gate to declare success (and only then, later, consider `update cleanup`):

- `docker logs --tail 200 openclaw` — SQLite migration completed, gateway
  listening, no errors.
- **Control UI reachable** at the `[VERIFY]` port, with prior sessions present.
- **Known-good query to the local model** returns sane output at normal
  latency.
- **Discord reconnect test** — reconnects and round-trips a message.
- `docker ps` / healthcheck — `Up` and `healthy`, not restarting.

---

## Sources

Official OpenClaw documentation this runbook is grounded in:

- https://docs.openclaw.ai/install/updating
- https://docs.openclaw.ai/install/docker
- https://docs.openclaw.ai/cli/doctor
- https://docs.openclaw.ai/releases/2026.8.2
- https://docs.openclaw.ai/releases/2026.8.1
