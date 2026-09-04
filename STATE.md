# STATE.md — current state, fast orientation

**What this file is.** A short, current-facts-only summary — not a design
document and not a history. Nothing here overrides or restates *why*
something became true; `PLAN-infra-watch-v1.md` remains authoritative on
*how* and *why*, and stays archive, read on demand. Read this file first;
go to the full plan only when a provenance question actually requires it.

_Last updated: 2026-09-03 — Sitting 1 (inventory and collection) complete._

## 1. What's tracked

Seven entries in `config\inventory.json`, not six — `node` and `pwsh` were
split into separate entries (each has its own GitHub repo for releases;
one entry can't point `releases_from` at two repos). Confirmed with Matt
2026-09-03.

| id | blast_radius | installed (as of last run) |
|---|---|---|
| n8n | high | 2.26.0 |
| ollama | high | 0.32.6 |
| docker | high | 29.6.1 |
| openclaw | medium | 2026.7.1 |
| open-webui | medium | 0.11.3 |
| pwsh | medium | 7.6.5 |
| node | low | 24.18.0 |

All seven repo paths for `releases_from` were verified against the GitHub
API directly (n8n-io/n8n, open-webui/open-webui, openclaw/openclaw,
ollama/ollama, moby/moby, nodejs/node, PowerShell/PowerShell) — none
accepted from memory. `openclaw`'s repo came from the running container's
own `org.opencontainers.image.source` label, per the hard rule for that
component.

**Version comparison stays within the installed version's own major line**,
confirmed with Matt 2026-09-03 — several tracked repos mix unrelated tags in
one releases feed (n8n's legacy 1.x patch line under the same `n8n@` tag
prefix; `moby/moby`'s `client/vX` and `api/vX` package tags alongside
`docker-vX` engine tags; Node's official even-major-is-LTS /
newest-even-major-is-Current model). A newer major/track existing outside
the installed line is recorded as an informational flag, never folded into
"releases behind." See `tag_pattern` and the `notes` field per component in
`config\inventory.json`.

## 2. In progress

**Sitting 1 complete.** `read-installed.ps1` and `check-releases.ps1` both
written and run cleanly end-to-end (run `20260903-222833`,
`records\runs\20260903-222833\`). `TEMPLATE-assessment.md` written.

Bug found and fixed during Sitting 1: an unquoted Go-template format string
(`--format {{.Server.Version}}`) gets mis-parsed by PowerShell's
`Invoke-Expression` as a script block, corrupting the arguments passed to
`docker`. Fixed by quoting the template in `inventory.json`'s stored
command. Also confirmed mid-sitting: invoking a script via `powershell`
launches Windows PowerShell 5.1, not pwsh 7 — always use `pwsh -File`, per
`CLAUDE.md`'s two-host warning.

**Sitting 2 (the judgment layer) not yet started.** Next: write
`assess-update.ps1`, run it against the smallest gap first (`open-webui` or
`pwsh` — both currently 0 releases behind, so `openclaw` at 3 is the
smallest real gap to exercise).

## 3. Blocked, and on whom

Nothing blocked. Sitting 2 spends against the model-call caps
(`config\model-caps.json`) and hasn't started pending confirmation to
proceed.

## 4. Governance items open

None open. Two decisions raised and resolved with Matt during Sitting 1 are
recorded in §1 above (the node/pwsh split; same-major-line comparison).

## 5. Standing rules in force

- **This project never applies an update** — read-and-recommend only. Enforced in `.claude\settings.json`.
- **Model-call caps**, read fresh from `config\model-caps.json`: `per_call_max_tokens` 16000, `per_run_dollar_cap` $0.25, `per_day_dollar_cap` $0.50.
- **Write-permission split** — confirmed fresh against `.claude\settings.json`: free `Edit` access to `records\` and `config\`; `scripts\` is an explicit `ask`-gate entry.

## 6. Maintenance rule for this file

Update this file at the close of any sitting that changes one of the facts
above — a component gets tracked, a verdict lands, a cap changes. Not on a
schedule, and not for anything outside those categories.
