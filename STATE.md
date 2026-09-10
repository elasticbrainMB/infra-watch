# STATE.md — current state, fast orientation

**What this file is.** A short, current-facts-only summary — not a design
document and not a history. Nothing here overrides or restates *why*
something became true; `PLAN-infra-watch-v1.md` remains authoritative on
*how* and *why*, and stays archive, read on demand. Read this file first;
go to the full plan only when a provenance question actually requires it.

_Last updated: 2026-09-09 — OpenClaw updated 2026.7.1 → 2026.9.3 via the
update-execution flow, the third component through it and the first Docker
container. Retargeted mid-sitting from the originally-planned v2026.8.2 to
the newest release with Matt's explicit approval, after a freshness check
found three newer releases. Verify ultimately PASSED, but the run needed
two live fixes not in the original plan — see §1. Docker Engine was updated
29.6.1 → 29.7.2 earlier the same day (target was 29.8.0; not reached).
Fleet-wide verify passed on everything except the exact version pin;
Docker's apply step stays at Tier F, not promoted, because of that
surprise._

## 1. What's tracked

Seven entries in `config\inventory.json`, not six — `node` and `pwsh` were
split into separate entries (each has its own GitHub repo for releases;
one entry can't point `releases_from` at two repos). Confirmed with Matt
2026-09-03.

| id | blast_radius | installed (as of last run) |
|---|---|---|
| n8n | high | 2.26.0 |
| ollama | high | 0.33.3 |
| docker | high | 29.7.2 |
| openclaw | medium | 2026.9.3 |
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

**Update-execution sequence for the remaining three, settled with Matt
2026-09-09: Docker Engine → OpenClaw → n8n.** Not the order a runbook
happened to exist in — OpenClaw's runbook was drafted first only because
Matt had been exploring it in a separate thread, and that wasn't meant to
jump it ahead of Docker or n8n. The actual reasoning: OpenClaw's 2.0
migration and n8n's own forward-only migrations are each one-way with a
7-day rollback window (Decision D); updating the engine after either would
restart (bounce) an already-migrated container outside its own
verification window, stacking an unrelated substrate change on top of an
irreversible one. Doing the engine first means both later updates land on
an already-proven, stable substrate. `records\runbooks\docker.md` and
`prompts\docker-update-apply.md` are drafted (Cowork, pending Matt's
review, nothing run); OpenClaw's runbook (`PLAN-openclaw-2.0-update-v1.md`)
was also amended the same day with a no-secrets-to-disk rule after Ollama's
sitting incidentally surfaced a sibling container's credentials in raw tool
output.

**Open WebUI added to the queue, 2026-09-09 (Cowork sitting), as a fourth
item: Docker Engine → OpenClaw → n8n → Open WebUI.** It was already in
`inventory.json` from v1 and gets a version/release check every run, but it
was never named in the original update-execution ask and had no pending
gap to force the question — 0 releases behind as of run `20260907-080001`.
Ordered last, not first: unlike the other three it carries no known
migration and nothing else in the inventory depends on it running
(`inventory.json`'s own note on the component), so there's no
substrate-ordering hazard pulling it earlier the way OpenClaw's and n8n's
one-way migrations do. When it next shows behind, it takes the medium-blast
Tier-F-first/-then-E gate already defined generically for containers in
`PLAN-update-execution-v1.md` §4a/§5 — no new design work needed, just its
own runbook and check script once a real gap opens. A first "current, no
action needed" note was written for it this same sitting —
`records\assessments\open-webui.md`, in the shape `reconcile-current.ps1`
would produce, but by hand, since that script only reconciles a component
that already has a prior assessment file and open-webui never had one —
and mirrored to the Notion board so it has a row like the rest of the
tracked seven. Disk is still the source of truth; the Notion write was made
directly against the API this sitting (Cowork, no host shell access this
turn) rather than through `post-notion.ps1`, but matches that script's
field mapping and page-body shape exactly.

**Docker Engine updated 29.6.1 → 29.7.2, 2026-09-09** — the fourth
component through the update-execution flow, and the first on the
substrate itself. Step Zero closed read-only against the live host: Docker
Desktop (not a bare engine package), WSL2 backend (`docker info` OSType
linux, kernel `6.18.33.1-microsoft-standard-WSL2`), self-updates via its
own in-app updater. Downgrade-safety was checked individually against
GitHub's release notes for every intervening tag (`docker-v29.6.2`,
`docker-v29.7.0`, `docker-v29.7.1`, `docker-v29.7.2`, `docker-v29.8.0`), not
a summarized page — none names a storage-format, data-layout, graphdriver,
or containerd-snapshotter change. The 29.7.0 config wrinkle
(`max-concurrent-downloads`/`-uploads` starting to be honored) was surfaced
to Matt explicitly; his call was to accept the new default (3/5) rather
than pin `0`/`0` — no `daemon.json` edit made.

`scripts\docker-update-check.ps1` written new — unlike the single-target
Node/Ollama scripts, this one snapshots and diffs the **whole container
fleet** (6 containers total on this engine, not just the 3 tracked ones),
because the engine restart bounces everything at once. No retained
29.6.1-era rollback installer existed on the host (the in-place
`Docker Desktop Installer.exe` inside the live install directory doesn't
count — it's not a separately-retained artifact); Matt approved fetching
one, and it was hash-verified against Docker's own published
`checksums.txt` for that build before being trusted (same discipline as
Node's and Ollama's rollback artifacts).

Matt installed via Desktop's own updater; **the Desktop app didn't visibly
restart, but process start-time evidence (fresh start ~11 min after Phase 0)
confirmed it had — no manual restart was needed.** Phase 2 verify: **the
fleet-health portion passed cleanly** — 0 containers missing, 0 stuck
restarting, 0 unexpected additions; n8n/open-webui/openclaw each passed
their own health check before and after; both open-webui and openclaw still
reach Ollama over `host.docker.internal`; `daemon.json` unchanged, matching
Matt's decision. **The version-pin check failed**: the engine landed on
`29.7.2`, not the pinned `29.8.0` — Docker Desktop's newest available
release (`4.90.0`, published 2026-09-07) bundles `29.7.2`; Docker has not
shipped a Desktop release that bundles `29.8.0` yet, even though that
engine tag has existed since 2026-09-03. No further "check for updates"
click can reach it today. Matt's explicit call: accept `29.7.2` and record
it now (it already carries the CVE fixes named in the assessment for
29.6.2 and 29.7.0; only 29.8.0's own hardening additions — the configurable
default AppArmor profile and the btrfs world-writable container-root fix —
are still outstanding) rather than leave the entry stale at `29.6.1`. The
remaining gap to `29.8.0` will surface naturally in a future weekly
assessment once Desktop ships a release that bundles it.

**Per `TIERS.md`'s promotion rule, this does *not* promote Docker's apply
step F→E** — the target-version miss is exactly the kind of surprise that
keeps (or returns) a component at Tier F for its next update, even though
nothing actually broke. Full detail (mechanism evidence, both installer
records, the downgrade-safety research) is in the `docker` entry's
`deployment` block in `config\inventory.json`.

**OpenClaw updated 2026.7.1 → 2026.9.3, 2026-09-09** — the third component
through the update-execution flow, and the first Docker container (Node
and Ollama were both native-host). Step Zero found the container is
Docker-Compose-managed (`C:\automation\openclaw\docker-compose.yml`), so
the exact recreate definition was read directly rather than reconstructed
from `docker inspect`; state volume `openclaw_data`, mount path, and
container user all matched OpenClaw's own documented safe defaults exactly
(no risk of the silent-data-skip trap the runbook calls out); published
port scoped to loopback + one tailnet address, not broad-LAN.

**Retargeted mid-sitting, before Step Zero ran.** The apply prompt's
freshness check (run before anything else, per its own first step) found
`v2026.9.1`/`.2`/`.3` had all shipped since the runbook's original
`v2026.8.2` pin — per the prompt's own rule, this stopped the sitting and
reported to Matt rather than silently retargeting or proceeding stale.
None of the three named a security fix; `v2026.9.3`'s "Breaking" changes
were plugin-SDK/non-Docker-install-facing, not a change to the 2.0
migration itself. Matt reviewed and explicitly approved moving to the
newest release. One real catch from this step: GitHub's release tag
(`v2026.9.3`) and Docker Hub's actual image tag (`2026.9.3`, no `v`)
differ — confirmed against the Hub API directly before handing Matt a pull
command, avoiding a pull that would have failed on a tag that doesn't
exist.

**Mandatory Phase-0 backup taken and verified.** Because the backup
command is itself a `docker run`, unconditionally deny-listed for this
project with no carve-out, it was Matt's hand action rather than this
sitting's — a first for this project's Phase 0 discipline, previously
always run by the sitting itself for Node/Ollama/Docker. Verified
afterward by this project using Windows' own `tar.exe`, no Docker needed
for that half: 19.5 MB, 3653 real entries including the state SQLite files.

**The update did not go cleanly, though it ultimately passed.** Two
distinct problems surfaced after the real pull+recreate, both resolved by
Matt's own hand actions on this sitting's diagnosis:

1. The container crash-looped (exit 78) — the gateway required its
   documented one-time database schema migration (`audit-events-v2`) via
   `openclaw doctor --fix`. This is the exact anticipated path from
   `PLAN-openclaw-2.0-update-v1.md` Phase 3, and it worked as documented
   once Matt ran the stop → one-shot `doctor --fix` → start sequence
   (OpenClaw's own error text specifies this exact order, which the
   runbook's single-command Phase 3 text hadn't spelled out).
2. Discord then failed to load entirely — a genuine gap in this sitting's
   own Step Zero: the plugin-compatibility check (added when the target
   was retargeted, because `v2026.9.3` renames/moves plugin-SDK exports)
   concluded "discord and ollama are both official, no exposure" from the
   startup log alone. That conclusion was incomplete — OpenClaw's Discord
   channel is itself an independently-versioned npm package inside the
   data volume, built against 2026.7.1's SDK, and it broke against
   2026.9.3's renamed internals exactly like a custom plugin would have.
   Fixed via `openclaw plugins update @openclaw/discord@latest` (its
   version-pin mechanism refused a plain `update discord`) plus a gateway
   restart — both run by Matt via `docker exec`, not this project, since
   installing/updating a component is squarely out of scope here regardless
   of which Docker verb carries it.

Separately (expected behavior, not a defect): the container recreate did
not carry over existing device pairings ("kept 0 existing record(s)"), so
the Control UI asked for its password again and a new device (Matt's
MacBook) needed `openclaw devices approve` — both his own actions, since
approving access and handling the gateway password are his calls, not
this project's.

**`scripts\openclaw-update-check.ps1` needed two live corrections during
this same sitting**, both found by Phase 2 actually running against a real
failure rather than a synthetic one: the "manual repair" detection
originally matched the runbook's own paraphrase, which never appears in
OpenClaw's real output (the actual strings are `gateway.maintenance_required`
and `doctor --fix`); and the log check originally used a fixed `--tail`
window, which stayed populated with the *original* crash-loop's text long
after the repair succeeded — switched to `docker logs --since <StartedAt>`,
scoped to the container's actual current run.

**Per `TIERS.md`'s promotion rule, this does *not* promote openclaw's apply
step F→E** — same reasoning as Docker's engine update this same week: verify
ultimately passed, but two real surprises occurred that this sitting's own
pre-flight checklist didn't catch. openclaw's apply step stays at Tier F for
its next update. Full detail (the corrected plugin-check note, the
`known_issues_2026-09-09` list, backup record, rollback reference) is in the
`openclaw` entry's `deployment` block in `config\inventory.json`.

**Update-execution sequence: Docker Engine (done) → OpenClaw (done) → n8n →
Open WebUI.** OpenClaw's runbook and handoff prompt (drafted earlier the
same day) are now the executed record for this run, not a pending draft.

**OpenClaw's handoff prompt amended, and n8n's runbook + handoff prompt
newly drafted, 2026-09-09 (Cowork sitting, later the same day as Docker's
real run).** With Docker done, Matt asked to get the next item ready while
he was away from the host — both remaining items were built rather than
picking one, per his own "if it makes sense to build the plan for both now
... that works too" call.

- `prompts\openclaw-update-apply.md` gained a new first step: a freshness
  check against openclaw/openclaw's live GitHub releases before Step Zero
  runs, since its target (`v2026.8.2`) was pinned from the `20260904`
  assessment and the `20260907` weekly run's attempt to refresh it failed
  (hit the spend cap) — so by the time this sitting actually runs, the
  target may be several days stale. The check either confirms nothing
  newer shipped, or stops and reports to Matt rather than silently
  retargeting. Everything else in that prompt (the mandatory backup, the
  no-secrets-to-disk rule added earlier the same day, Chunk A/B shape) is
  unchanged from its prior draft.
- `records\runbooks\n8n.md` and `prompts\n8n-update-apply.md` are newly
  written — n8n's own first sitting under this flow, so (like Ollama's and
  OpenClaw's first sittings) Step Zero is genuine discovery: n8n has no
  `deployment` block on disk yet. Grounded in `records\assessments\n8n.md`
  (run `20260907-080001`, confirmed still the latest successful run for
  `n8n`): target `n8n@2.37.11`, verdict `schedule` (no security content in
  the 42 releases behind, but real breaking API changes — the workflow-
  history endpoint's `offset` param removed and a JSON content-type now
  required on decorator routes in `2.36.7`, plus the Google Ads node's
  migration off its sunset v21 API in `2.34.6`/`2.35.3`). The runbook
  carries the same forward-only-migration hazard as OpenClaw's (§4a):
  re-pinning the old tag alone is not a rollback once the schema has
  migrated, so the Phase 0 volume/DB backup is mandatory, not optional,
  same as OpenClaw's. Also carries n8n's own freshness-check step and a
  reminder for Matt to check his own API scripts/workflows against the two
  breaking changes before or during the window. `blast_radius: high` (from
  `inventory.json`) already forces full Tier F on its own; the migration
  reinforces it independently via Decision E.

Both were pending Matt's review at the time they were drafted; n8n's still
is. OpenClaw's has since run for real (see above) — update-execution
sequence is now Docker Engine (done) → OpenClaw (done) → n8n → Open WebUI.

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
