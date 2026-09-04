# STATE.md — current state, fast orientation

**What this file is.** A short, current-facts-only summary — not a design
document and not a history. Nothing here overrides or restates *why*
something became true; `PLAN-infra-watch-v1.md` remains authoritative on
*how* and *why*, and stays archive, read on demand. Read this file first;
go to the full plan only when a provenance question actually requires it.

_Last updated: 2026-09-04 — v1 built. All three sittings complete and
committed; weekly automation is live._

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

Nothing in progress — v1 is built. `run-check.ps1` runs weekly, Mondays
8am, via Task Scheduler (`infra-watch-weekly`). Next scheduled run:
9/7/2026. All three sittings below are committed (`b336544`, `353678e`,
`2a438d1`).

**Sitting 1 complete.** `read-installed.ps1` and
`check-releases.ps1` both written and run cleanly end-to-end.

Bug found and fixed during Sitting 1: an unquoted Go-template format string
(`--format {{.Server.Version}}`) gets mis-parsed by PowerShell's
`Invoke-Expression` as a script block, corrupting the arguments passed to
`docker`. Fixed by quoting the template in `inventory.json`'s stored
command. Also confirmed mid-sitting: invoking a script via `powershell`
launches Windows PowerShell 5.1, not pwsh 7 — always use `pwsh -File`, per
`CLAUDE.md`'s two-host warning.

**Sitting 2 (the judgment layer) complete.** `assess-update.ps1` written and
run once per component with a non-zero gap, against run `20260903-222833`,
using
`z-ai/glm-5.3-20260816` on OpenRouter (GLM-5.2, referenced in Matt's
personal notes, no longer exists on OpenRouter as of 2026-09-03 — superseded
by 5.3). Total spend for the run: **$0.2137** against the $0.25/run cap —
none capped, none malformed.

| Component | Verdict | Why (one line) |
|---|---|---|
| openclaw | `do-now` | named Sharp CVE fix + two breaking migrations |
| node | `do-now` | v24.18.1 fixes 12 CVEs, 3 rated High |
| docker | `do-now` | multiple named CVEs across the gap (29.6.2–29.8.0) |
| ollama | `schedule` | no security content, but real stability/perf fixes |
| n8n | `defer` | 40 releases behind, but no security content and nothing the notes flag as requiring action |

`open-webui` and `pwsh` are already current (0 behind) — `assess-update.ps1`
exits early with a one-line message for those, no model call made.

Five files in `records\assessments\*.md`.

**Sitting 3 complete.** `run-check.ps1` written and run live twice (runs
`20260904-053218`, `20260904-053532`), Discord posting confirmed working
against real webhooks. Weekly Task Scheduler entry registered and verified
(see §5).

Two bugs found and fixed:
- `$assessments = foreach (...) { ...; Write-Output $stage.Output; ... }` —
  PowerShell captures *everything* written inside a `foreach` used as an
  expression, `Write-Output` included, into the result collection. Every
  component's console echo was being swept into `$assessments` alongside
  its real result object, corrupting the failure count. Fixed by using
  `Write-Host` for the console echo instead (run `20260904-053218` shows
  the corrupted output; its Discord post to `#runs` has a garbled "FAILED"
  segment as a result — nothing actually failed).
- `assess-update.ps1`'s strict response parser required
  `WHAT_IT_WILL_TAKE:` exactly; the model wrote `WHAT_IT_WILL_TAKES:` for
  ollama in run `20260904-053532`, so the run correctly flagged it as
  failed (parser worked as designed — refused to guess) rather than
  writing a bad file. Regex relaxed to accept the plural. Retried
  successfully afterward; `records\runs\20260904-053532\summary.json` was
  hand-reconciled to reflect the final state rather than the transient
  failure (its own `note` field documents this).

**Real Discord posts went out during this testing** — two to the `runs`
webhook, two to the `decisions` webhook (the second `decisions` post
predates ollama's successful retry, so it's missing ollama's
schedule/high-blast-radius line). No further posts were sent once the
summary was reconciled, to avoid piling more test traffic onto Matt's real
channels.

Today's total model spend: **$0.2316** across all testing, well under the
$0.50/day cap.

## 3. Blocked, and on whom

Nothing blocked.

## 4. Governance items open

None open. Three decisions raised and resolved with Matt during the build
are recorded in §1 above (the node/pwsh split; same-major-line comparison)
and §5 below (Task Scheduler over n8n for the weekly trigger — n8n runs in
a container isolated from the host tools this project reads, so routing
through it would need a new host-side webhook listener; Matt chose to keep
Task Scheduler for this one job rather than build that).

## 5. Standing rules in force

- **This project never applies an update** — read-and-recommend only. Enforced in `.claude\settings.json`.
- **Model-call caps**, read fresh from `config\model-caps.json`: `per_call_max_tokens` 16000, `per_run_dollar_cap` $0.25, `per_day_dollar_cap` $0.50.
- **Write-permission split** — confirmed fresh against `.claude\settings.json`: free `Edit` access to `records\` and `config\`; `scripts\` is an explicit `ask`-gate entry.
- **Weekly trigger**: Windows Task Scheduler, task `infra-watch-weekly`,
  Mondays 8:00 AM, runs `pwsh.exe -NoProfile -File
  scripts\run-check.ps1`. Logon mode "Interactive only" — runs as Matt's
  own account, only when he's logged in, no stored password. Verified the
  WindowsApps-packaged `pwsh.exe` (not the MSI install path) actually
  launches correctly under Task Scheduler before trusting the real task.

## 6. Maintenance rule for this file

Update this file at the close of any sitting that changes one of the facts
above — a component gets tracked, a verdict lands, a cap changes. Not on a
schedule, and not for anything outside those categories.
