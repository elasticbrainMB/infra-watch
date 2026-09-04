# infra-watch — build rules

**Read before acting:** `STATE.md` — the fast orientation file for what's
true right now (what's tracked, what's running, open work, standing caps).
`PLAN-infra-watch-v1.md` (written Sitting 1) is authoritative on what this
project is and why. `SESSION-LOG.md` is the narrative history behind
`STATE.md`'s snapshot — one dated entry per session, newest first; read it
when a "why did we do it this way" question isn't answered by the other
two.

## Execution discipline

- Run commands verbatim. Show raw output, not summaries.
- STOP conditions are hard stops. Do not route around failures — failures are informative.
- Discovery before destructive action: read and audit first, capture concrete values second, make changes third.
- `[VERIFY]` means check current docs or source at build time. Do not trust cached knowledge for repository paths, release APIs, or installed versions.
- **Never infer a default from an absent environment variable.** An unset variable tells you only that the environment does not override the default — it says nothing about what the default is. Read the config source in the running image.
- End every chunk with a markdown chunk record and a status summary.

## Do not touch (hard boundary — human approval required to cross)

- **This project never applies an update.** Read-and-recommend only. It never pulls, restarts, recreates, or upgrades a component. The `deny` list in `.claude\settings.json` enforces this and is not to be widened.
- **Live n8n workflows** — this tool reads n8n's installed version only; it does not touch workflows, and recreating the n8n container is never in scope here.
- **OpenClaw config** — read version only, never edit.

## Environment

- **Windows 11.** Seven components tracked, one entry per component in `config\inventory.json` — hand-maintained, not auto-discovered. Full definition in `PLAN-infra-watch-v1.md`.
- **Disk is the source of truth; Discord is a mirror.** A run must succeed with Discord unreachable — `scripts\post-discord.ps1` already behaves this way; do not change that.

## Use the fact, not a proxy for it

The most common error this rule exists to catch: reading something next to a fact and treating it as the fact.

- A count or a position that another file owns goes stale — state the property, not the number.
- `Measure-Object -Line` is not a line count. Use `@(Get-Content <path>).Count`.
- Read a version from the host or the registry API, never from a document — a document can be stale the moment it's written.

## How a check is written

- A gate states a decidable condition. Not a count, and not an adjective.
- A check list frozen when written cannot see defects found later — build it from what is known wrong at the time it runs.
- Do not assume something exists because an earlier step was supposed to produce it.

**Calling the API — four hazards, each already paid for once, on the caddy:**

- Never `-s ... | Out-Null` on an API call — it hides a non-200.
- Inline JSON to `curl.exe` fails. Write the body to a file, no BOM, call `curl.exe ... -d "@body.json"`.
- A BOM breaks JSON parsing. Write UTF-8 without one:
  ```powershell
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
  ```
- PowerShell's `-eq` compares strings case-insensitively. Byte equality needs `-ceq`.

## What belongs in this file

Every session reads this file before it starts working, so its length is a cost paid every time. Anything added displaces something — if nothing here is worth removing, the addition is not worth making.

## Why the permission rules are not in this file

The enforced rules live in `.claude\settings.json`. This file is context — it shapes what gets attempted and changes nothing about what is allowed. Path rules there use `Edit(...)` deliberately, never `Write(...)` — only `Edit` and `Read` are checked against file permissions.
