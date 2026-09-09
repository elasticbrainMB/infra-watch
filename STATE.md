# STATE.md — current state, fast orientation

**What this file is.** A short, current-facts-only summary — not a design
document and not a history. Nothing here overrides or restates *why*
something became true; `PLAN-infra-watch-v1.md` remains authoritative on
*how* and *why*, and stays archive, read on demand. Read this file first;
go to the full plan only when a provenance question actually requires it.

_Last updated: 2026-09-09 — Ollama updated 0.32.6 → 0.33.3 via the
update-execution flow, Ollama's own first clean Tier-F run (see §1 and §2
below)._

## 1. What's tracked

Seven entries in `config\inventory.json`, not six — `node` and `pwsh` were
split into separate entries (each has its own GitHub repo for releases;
one entry can't point `releases_from` at two repos). Confirmed with Matt
2026-09-03.

| id | blast_radius | installed (as of last run) |
|---|---|---|
| n8n | high | 2.26.0 |
| ollama | high | 0.33.3 |
| docker | high | 29.6.1 |
| openclaw | medium | 2026.7.1 |
| open-webui | medium | 0.11.3 |
| pwsh | medium | 7.6.5 |
| node | low | 24.20.0 |

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

**Notion board (v1.1) added 2026-09-08.** A mirror database, "Infra-Watch
— Component Assessments," now exists in the "AI development" Notion
workspace: https://app.notion.com/p/dca7751313d8462b9ddd0e4bb1525ce3 — one
page per tracked component, built against run `20260907-080001`. All 5
files in `records\assessments\` were mirrored, per Matt's instruction,
including `openclaw.md`'s stale 2026-09-04 assessment (the 09-07 run's
attempt for it failed; see that page's own staleness callout). Not yet
wired into `run-check.ps1`'s weekly automation — this was a one-time
manual build; a future sitting adds the upsert-on-Component API calls to
the weekly script.

One deviation from `PLAN-notion-board-v1.1.md`: Verdict is a **Select**
property, not **Status** — Notion's create-database/update-data-source
tools have no way to set custom-labeled options on a Status property
(`STATUS('do-now', ...)` was rejected outright), so Select was substituted.
Board view grouped by Verdict still gives the same do-now/schedule/defer
columns.

**Wired into weekly automation 2026-09-09.** `scripts\post-notion.ps1` mirrors
one component's `records\assessments\<id>.md` to its Notion row (upserting
on Component: update properties + replace the page body if the row exists,
create it otherwise). `run-check.ps1` calls it once per successfully
assessed component, right after the assess-update loop, and never gates on
its exit code — same principle as the Discord posts: a run must succeed
with Notion unreachable. Calls Notion's REST API directly via `curl.exe`
(no MCP dependency at runtime), pinned to `Notion-Version: 2022-06-28`
(config in `config\notion.json`).

**Live and confirmed working, 2026-09-09.** Matt created a Notion internal
integration (`infra-watch`) via the Developer portal (`app.notion.com/
developers/connections` — not the Settings → Connections hub, which is for
installing prebuilt connectors, not creating one), shared the "Infra-Watch
— Component Assessments" database with it, and added `NOTION_API_KEY=...`
to `C:\automation\secrets\infra-watch.env`. Manually ran
`post-notion.ps1 -ComponentId docker` as a live test: it reported "Updated
existing Notion page for 'docker'", and the page's last-edited timestamp
moved to that exact moment with properties and body content intact —
confirmed independently via the Notion API, not just the script's own
success message. The full pipeline (auth, upsert lookup, property update,
body delete-and-rewrite) is verified end to end. Next Monday's scheduled
`run-check.ps1` run will exercise it for real for the first time.

**Reconcile-current fix added 2026-09-09.** A component that resolves from
"behind" to "current" (its `releases_behind` drops to 0 in a later run) no
longer sits with its last stale do-now/schedule/defer verdict indefinitely.
`run-check.ps1` now also loops over every `current` component that already
has a `records\assessments\<id>.md` file (i.e. it was behind at some
point) and calls a new `scripts\reconcile-current.ps1` — no model call,
purely mechanical — which overwrites that file with a short "current, no
action needed" note and feeds it through the same `post-notion.ps1` upsert
as a real assessment, so the Notion row updates too. Added a 4th Notion
Select option, `current` (green), to the "Verdict" property to receive it.
A component that has never been behind (never had an assessment file,
never had a Notion row) is left alone either way — reconciliation only
touches rows that already exist. Verified offline only: a synthetic
fixture test, a regression test against all 5 real assessment files
(unchanged output, confirming no breakage), and an isolated test of the
new array-merging logic in `run-check.ps1` — no tracked component is
actually at 0-behind this week, so there's been no live run through this
path yet. It will get its first real exercise whenever a component
naturally resolves in a future scheduled run.

**Ollama updated 0.32.6 → 0.33.3, 2026-09-09**, via the same
update-execution flow proven on Node. Step Zero closed the runbook's
`[VERIFY]` rows read-only against the live host: install mechanism is an
Inno Setup installer (`OllamaSetup.exe`, per-user, HKCU registry entry, no
`WindowsInstaller` property) — not an MSI, so Node's ProductCode/UpgradeCode
check doesn't apply; models path confirmed as `C:\Users\Matt
Becker\.ollama\models` from Ollama's own server-config log line (the env
var is unset — the absent-default rule was followed, not assumed); the
caddy model confirmed live as `qwen3.5-caddy:latest` (a custom-derived tag,
read directly out of `caddy-server.js`'s `MODEL` constant — not the stale
`qwen3:14b` name from old notes, and not the base `qwen3.5:9b-q8_0` tag);
open-webui's dependent path confirmed (`OLLAMA_BASE_URL=http://
host.docker.internal:11434`). Openclaw's live reachability was **not**
independently probed — doing so would have meant reading its provider
config beyond version, which crosses CLAUDE.md's OpenClaw hard boundary
("read version only, never edit"); its documented `host.docker.internal`
baseUrl comes only from `caddy\openclaw-environment-spec-v1.md`'s plan, not
a live check. One side finding: the read-only `docker inspect openclaw`
call used to check for an `OLLAMA_BASE_URL` env var also surfaced
openclaw's live Telegram bot token and gateway password in tool output —
neither was written to disk anywhere in this project; flagging it here as
something Matt should know happened, not treating it as this project's to
fix.

No `0.32.6` installer was retained anywhere on the host — a hard STOP per
the runbook. Matt approved fetching both the `0.32.6` rollback artifact and
the `v0.33.3` target from Ollama's official GitHub releases; both were
hash-verified (the target's checksum cross-checked two independent ways —
GitHub's own asset digest and Ollama's published `sha256sum.txt` agreed)
before being trusted. New `scripts\ollama-update-check.ps1` written
(`-Phase capture`/`-Phase verify`, mirrors `node-update-check.ps1`'s shape)
capturing `ollama --version`, the full model list (diffed by name **and**
size), a known-good chat-API query against the caddy model, and
open-webui's live round-trip to Ollama — openclaw's round-trip is
deliberately not probed, same boundary as above. Phase 0 ran clean (run
`20260909-054429`); Matt ran the verified installer by hand (the one
mutating step, same shape as Node); Phase 2 verified **PASS**: version
exact match, model list unchanged (0 missing, 0 added, 0 size changes),
known-good query still answers correctly (cold-load latency rose from
17.9s to 64.0s post-install — not a pass/fail criterion, plausibly just a
fresh process reloading the model from disk, noted rather than alarmed
over), open-webui's round-trip now reports 0.33.3 too. Deployment block
and both installer records updated in `inventory.json`; the `0.32.6`
installer is now the rollback artifact for the 7-day window (through
2026-09-16).

**Per `TIERS.md`'s promotion rule, this is Ollama's own first clean Tier-F
run**, which promotes *Ollama's own* apply step F→E for its next update —
distinct from and not inherited from Node's earlier F→E promotion, per the
runbook's own note that promotion is per-component.

## 2. In progress

**`PLAN-update-execution-v1.md`'s Sitting 1 (Node read-only proof) ran
2026-09-08.** Decisions A–G there are locked; this sitting executed §9 step
1 (close Node's `[VERIFY]` deployment facts), step 2 (write the runbook),
step 3 (write the read-only snapshot/verify script), and step 4 (dry-run
it) — all read-only, nothing applied.

- Node's install mechanism is confirmed off the live host: a manual MSI
  install (nodejs.org's official Windows x64 installer, downloaded to
  Matt's own `Downloads` and run by hand) — not nvm-windows, not
  winget-managed. Recorded as a `deployment` block on the `node` entry in
  `config\inventory.json`: binary/npm paths, ProductCode/UpgradeCode,
  update-behavior (in-place replace, confirmed read-only via the retained
  installer's own Property table), and a rollback source (the retained
  `node-v24.18.0-x64.msi`, hashed). One residual gap, flagged in the block
  itself: the UpgradeCode match is confirmed only against the *installed*
  24.18.0 MSI — re-check it against the real v24.20.0 installer before
  applying.
- Runbook written: `records\runbooks\node.md`, seeded from
  `records\assessments\node.md` (run `20260907-080001`, confirmed as the
  latest successful run for `node` before seeding).
- New script `scripts\node-update-check.ps1` — one script, `-Phase capture`
  (Phase 0) / `-Phase verify` (Phase 2), diffs against the same `-RunId`'s
  capture. Posting to `#decisions` is gated behind `-PostToDiscord` (off by
  default).
- **Dry run complete, clean:** run `20260908-193732` — Phase 0 captured
  `node v24.18.0` / `npm 11.16.0`; Phase 2 re-captured and diffed with
  nothing changed, `pass: true`, no Discord post sent (flag was off). No
  live traffic went to Matt's channels.
**§9 step 5 (the real update) ran 2026-09-08, same day, later sitting.** Node
went 24.18.0 → 24.20.0.

- The v24.20.0 x64 MSI wasn't on the host; with Matt's explicit approval it
  was fetched from `nodejs.org` and its SHA-256
  (`28B69132C35CCC033BF8F2A67CD10C9D75EF5822593363309DA448F2AFFF2D8A`)
  verified against nodejs.org's own `SHASUMS256.txt` before being trusted.
- The read-only UpgradeCode check (§9 step 1's residual gap) was re-run
  against this real target MSI — `{47C07A3A-42EF-4213-A85D-8F5A59077C28}`,
  matching the recorded UpgradeCode — closing the one gap Sitting 1 flagged.
- Phase 0/Phase 2 ran for real against run `20260908-220239`: `pass: true`.
  `node` v24.18.0 → v24.20.0 (exact target), `npm` 11.16.0 → 11.19.0 (bundled
  bump, expected — not a regression), binary and npm paths unchanged, no
  side-install. Registry confirms ProductCode
  `{DC5BBE4F-0668-40DC-A913-83710DA79E35}`, InstallSource still Matt's own
  Downloads folder.
- `config\inventory.json`'s node `deployment` block updated: `product_code`
  now the live one, old code kept in a new `product_code_history`,
  `update_behavior` closed out with the real-run confirmation.
- **Per `TIERS.md`'s promotion rule, Node's apply step is now F→E**: one
  clean Tier-F run (this one — verify passed, no surprises) is exactly the
  condition that promotes it. The next Node update can run at Tier E
  (evidence-only) rather than the full first-time gate. Any surprise on a
  future run sends it back to F per the demotion rule.
- The retained `node-v24.18.0-x64.msi` in Matt's Downloads stays as the
  rollback artifact; the new `node-v24.20.0-x64.msi` now also sits there
  alongside it (not something this project's 7-day retention manages —
  both are pre-existing files in Matt's own folder, per the runbook's
  Retention note).

v1 itself remains built and unchanged — `run-check.ps1` runs weekly,
Mondays 8am, via Task Scheduler (`infra-watch-weekly`). Next scheduled run:
9/14/2026. The three v1 sittings are committed (`b336544`, `353678e`,
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
