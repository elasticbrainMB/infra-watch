# SESSION-LOG.md — recap log for future chat threads

**What this file is.** Append-only. One dated entry per session, written so
a new chat thread can get caught up fast without reading the full
transcript. `STATE.md` is the current-facts snapshot (what's true *now*,
overwritten as facts change); this file is the narrative history behind
it — what happened, in what order, and why. Newest entry at the top.

---

## 2026-09-08 — update-execution, Sitting 1: Node read-only proof

**Starting point:** `PLAN-update-execution-v1.md` (drafted earlier the same
day) settled seven design forks (§8, Decisions A–G) for a companion
install→verify→resolve→rollback flow, gated at "prove it read-only on Node
first" (Decision G) before touching anything higher-blast. Nothing in that
plan had been built yet.

- **Closed Node's `[VERIFY]` deployment facts, read-only.** Determined the
  actual install mechanism directly from the live host rather than
  guessing: no `nvm` command, no `NVM_HOME`/`NVM_SYMLINK`, no nvm install
  directories (rules out nvm-windows); `C:\Program Files\nodejs` is a real
  directory, not a symlink (also rules out nvm-windows, which would
  symlink that path); the registry Uninstall entry has `WindowsInstaller=1`
  with a ProductCode that exactly matches the ProductCode embedded in a
  leftover installer file (`node-v24.18.0-x64.msi`) still sitting in Matt's
  own Downloads folder, dated 2026-07-07. Conclusion: a manual MSI install,
  not nvm-windows, not winget-managed (winget's `list` output matches the
  install to its own catalog for upgrade-tracking purposes only — that's
  not evidence of how it was actually installed).
- Went one step further than the plan's minimum ask: opened that retained
  MSI's own Property table via the WindowsInstaller COM API in read-only
  mode (`OpenDatabase` mode 0 — reads the file, installs nothing) to pull
  its UpgradeCode, which is what actually determines in-place-replace vs.
  side-install behavior. Confirmed a populated UpgradeCode is present;
  flagged in the record that this is only confirmed against the
  *installed* 24.18.0 MSI, not yet against the real v24.20.0 target (not on
  this host) — Matt should re-run the same check against that file before
  applying.
- Wrote all of this into a new `deployment` block on **only** the `node`
  entry in `config\inventory.json` (Decision F) — mechanism, evidence,
  binary/npm paths, ProductCode/UpgradeCode, update-behavior, and a
  rollback source (the retained MSI, SHA-256 hashed).
- **Caught and fixed my own "proxy, not fact" error mid-sitting:** first
  pass recorded `npm_path` as `npm.cmd` because that file exists on disk
  (`Test-Path` returned true), but `Get-Command npm` — the thing that
  actually resolves what runs — returns `npm.ps1` on this host. Both files
  ship with Node; only one is what actually executes. Fixed to match the
  directly-observed resolution, confirmed again during the Chunk 4 dry run
  below.
- Wrote `records\runbooks\node.md` from the §4d template, seeded from
  `records\assessments\node.md` — checked its `run_id`
  (`20260907-080001`) against `records\runs\20260907-080001\summary.json`
  first and confirmed it's the latest successful run for `node`, per the
  plan's own "refuse a stale seed" rule, before writing anything.
- Wrote `scripts\node-update-check.ps1` (new file in the ask-gated
  `scripts\` path — no permission prompt actually fired for a brand-new
  file via `Write`, only `Edit` on an existing one is gated per
  `CLAUDE.md`'s note; flagging that as observed behavior, not something to
  route around). One script, `-Phase capture` / `-Phase verify` tied by
  `-RunId`: captures node/npm versions and paths, diffs Phase 2 against
  Phase 0, and supports an optional `-BuildCommand` for a future dependent-
  build baseline (none configured yet for this project — nothing runs
  unless Matt explicitly supplies one). Posting to `#decisions` is gated
  behind `-PostToDiscord` (off by default) so a dry run can never reach
  Matt's real channels; `post-discord.ps1` itself untouched.
- **Dry-ran Phase 0 then Phase 2** against the current, unchanged Node
  (run `20260908-193732`): captured `v24.18.0` / `11.16.0`, re-captured,
  diffed — no drift, `pass: true`, exit 0. No Discord post sent.
- **Stopped exactly where the plan said to.** The real Node update
  (24.18.0 → v24.20.0) is Matt's own hand action (§9 step 5); this sitting
  applied nothing. Also confirmed no new model call was made anywhere in
  this sitting — the `$0.25`/run cap that the prior run (`20260907-080001`)
  tripped was never at risk here.

---

## 2026-09-09 — Notion board wired into weekly automation

**Starting point:** the 09-08 sitting built the Notion database and mirrored
the 5 existing assessment files into it by hand, but left `run-check.ps1`'s
weekly run untouched (STATE.md flagged the upsert-on-Component API calls as
the next sitting's job). Matt asked to close that gap.

- Added `scripts\post-notion.ps1` and `config\notion.json`. The script
  takes one `-ComponentId`, reads that component's
  `records\assessments\<id>.md` fresh off disk (never reuses in-memory
  state from the caller), parses every field the Notion mapping needs via
  regex, and upserts one Notion page: queries by Component, PATCHes
  properties and replaces the page body (delete existing blocks, append
  new ones) if a row exists, otherwise creates one. Calls Notion's REST
  API directly with `curl.exe` — no dependency on any MCP connection at
  run time, matching how `post-discord.ps1` and `invoke-model.ps1` already
  call their own external APIs (temp file for the body, `-K` config file
  for headers, response written via `-o` to avoid the console-encoding
  corruption noted in `invoke-model.ps1`'s own header comment).
- `run-check.ps1` calls `post-notion.ps1` once per successfully assessed
  component, right after the assess-update loop, and never checks its exit
  code — a Notion outage must not fail the run, same rule already in force
  for Discord ("disk is source of truth, Discord/Notion is a mirror" per
  `CLAUDE.md`). `post-notion.ps1` itself never throws upward: every failure
  is caught, printed, and it exits 1 on its own.
- Verified as much as possible without a live token: installed a real
  PowerShell 7 interpreter in a scratch environment (not available in this
  chat's own sandbox) and ran the actual parsing logic against all 5 real
  assessment files — every field matched exactly. Also ran the full script
  (property/body JSON construction, `curl.exe` invocation) with a dummy API
  key; it built valid request bodies and failed only on the network call
  itself, caught cleanly. The live HTTP round trip against Notion's real
  API was not exercised — no token exists yet to test with.
- **Genuine blocker, needs Matt:** the script authenticates with a Notion
  integration token it reads from `C:\automation\secrets\infra-watch.env`
  as `NOTION_API_KEY`. That file doesn't have one yet, and there's no way
  for this tool to create or extract one - it has to come from Matt
  creating an internal integration in Notion and explicitly sharing the
  "Infra-Watch — Component Assessments" database with it. Until then, the
  Notion-sync step fails cleanly every run (logged, non-fatal) and
  everything else proceeds as before.

---

## 2026-09-08 — Notion board (v1.1) built

**Starting point:** `PLAN-notion-board-v1.1.md` (drafted the same day), which
mapped `records\assessments\*.md` and `config\inventory.json` to a 12-property
Notion database and left three open judgment calls for Matt. Notion MCP tools
were unreachable when the plan was drafted; they were reachable this session.

- Matt resolved the two live judgment calls: build all 5 rows (including
  `openclaw`'s stale 09-04 assessment), and the workspace is "AI development."
- Searched the workspace first, per the plan's own build steps — found an
  existing "Infra-Watch" page, but it's a row in the separate portfolio
  "Projects" tracker (pushed by `.github\workflows\notion-status.yml`), not a
  home for this board — confirms judgment call #3's flag that the two are
  unrelated. Created a new top-level database instead: "Infra-Watch —
  Component Assessments"
  (https://app.notion.com/p/dca7751313d8462b9ddd0e4bb1525ce3).
- One deviation from the plan: Verdict is a **Select** property, not
  **Status**. The create-database/update-data-source tools accept custom
  options for Select at creation, but a Status property's options can't be
  renamed or custom-labeled through them — `ALTER COLUMN "Verdict" SET
  STATUS('do-now', ...)` was rejected outright. Select produces the same
  do-now/schedule/defer Board-view columns, so the literal ask ("Notion as a
  board") is unaffected; noting the substitution since the plan called out
  Status deliberately.
- Created all 12 properties and all 5 pages (Docker Engine, n8n, Node.js,
  Ollama, OpenClaw), each with the page body the plan specified (Verdict +
  why, What it will take, Source link, disclaimer callout) mirroring its
  `records\assessments\*.md` file. OpenClaw's page additionally carries a
  staleness callout explaining why its assessment date trails the other four.
- Recorded the database URL in `STATE.md` §1, per this repo's maintenance
  rule for that file.

**Not yet done:** wiring this into `run-check.ps1`'s weekly run — this was a
one-time manual build against the 09-07 assessment run; a future sitting adds
the Notion API calls to the weekly script itself, upserting on Component per
the plan's design.

---

## 2026-09-04 — v1 built, all three sittings complete, weekly automation live

**Starting point:** a written handoff (`prompts\infra-watch.md`) with the
full v1 definition, pasted as the first message of the first Claude Code
sitting in this project. Repo was freshly initialized with `CLAUDE.md`,
`STATE.md`, `TIERS.md`, and the scripts/permissions copied over from the
caddy project — nothing else built yet.

**Sitting 1 — inventory and collection** (commit `b336544`):
- Wrote `PLAN-infra-watch-v1.md` as the project's own charter.
- Resolved all `[VERIFY]` items against the live host, not from memory or
  cached knowledge — every `releases_from` repo path checked against the
  GitHub API directly. OpenClaw's repo in particular came from the running
  container's own `org.opencontainers.image.source` label, per the plan's
  hard rule for that component (the project name collides with unrelated
  repos and SEO content, so guessing was never an option).
- Two decisions needed Matt's call and got asked rather than guessed:
  `node`/`pwsh` split into seven inventory entries instead of six (each
  needs its own GitHub repo for releases), and version comparisons stay
  within the installed version's own major line (n8n has a legacy 1.x tag
  line still being patched alongside 2.x; `moby/moby` mixes `client/vX`
  and `api/vX` tags in with `docker-vX` engine tags; Node has an official
  even-major-is-LTS model where the newest even major is "Current," not
  the safe upgrade target). Both confirmed with Matt before building
  further.
- Wrote and ran `read-installed.ps1` and `check-releases.ps1` cleanly.
- Two real bugs caught and fixed: an unquoted Go-template format string
  (`--format {{.Server.Version}}`) getting mis-parsed by PowerShell's
  `Invoke-Expression` as a script block, corrupting the arguments passed
  to `docker`; and confirming that invoking a script via `powershell`
  launches Windows PowerShell 5.1 instead of pwsh 7 on this host — always
  use `pwsh -File`.

**Sitting 2 — the judgment layer** (commit `353678e`):
- Wrote `assess-update.ps1` — one model call per component, never batched,
  with deterministic facts (installed/current version, releases behind,
  boundary crossed, `blast_radius`) supplied by the script itself so the
  model only judges the change, not the retrieval.
- GLM-5.2, referenced in Matt's own personal notes, no longer exists on
  OpenRouter — superseded by 5.3. Used `z-ai/glm-5.3-20260816`.
- Ran against all five non-zero-gap components. Verdicts discriminated
  correctly: node (smallest blast radius, `low`) got `do-now` on a
  concrete 12-CVE fix; n8n (largest gap, 40 releases, `high` blast radius)
  got `defer` because nothing in the notes was security-related or flagged
  as requiring action. Total spend $0.2137 against the $0.25/run cap.

**Sitting 3 — schedule and close** (commits `2a438d1`, `d82554e`):
- Wrote `run-check.ps1` — one command, end to end. Each stage
  (`read-installed`, `check-releases`, `assess-update`) is spawned as a
  real subprocess (`pwsh -File`), not called in-process via `&` — all
  three end with `exit N`, and an in-process call would take the
  orchestrator down with it. `invoke-model.ps1` avoids this deliberately
  by using `return` instead (see its own header comment).
- Two more bugs found running it live: PowerShell captures *everything*
  written inside a `foreach` used as an expression — a stray
  `Write-Output` meant only as console echo was getting swept into the
  result collection, corrupting the failure count (fixed with
  `Write-Host` instead); and the model wrote `WHAT_IT_WILL_TAKES:`
  (plural) once, which the strict parser correctly refused to guess at
  rather than silently mangling — the regex was relaxed to accept it.
- Real Discord posts went out during testing (two to `#runs`, two to
  `#decisions`) — the first `#runs` post has a garbled "FAILED" segment
  from the bug above (nothing actually failed), and the first
  `#decisions` post is missing ollama's line (resolved after a retry).
  Both are superseded by the first real scheduled run.
- Matt was asked before registering anything persistent. First choice was
  triggering via n8n instead of Task Scheduler, to keep n8n as the primary
  scheduling hub — but n8n runs in a Docker container isolated from the
  host tools this project reads (`docker inspect` on host containers,
  `ollama`, `node`, `pwsh`), so that would need a new host-side webhook
  listener with its own security surface. On seeing that tradeoff, Matt
  chose Task Scheduler for this one job.
- Verified the WindowsApps-packaged `pwsh.exe` (not the MSI install path)
  actually launches correctly under Task Scheduler using a zero-cost
  throwaway task, before trusting the real one against live spend.
- Registered `infra-watch-weekly`: Mondays 8:00 AM, runs as Matt's own
  account only when logged in (no stored password). Next run: 9/7/2026.

**End state:** v1 is fully built and committed. Weekly automation is live
and unattended. Total model spend for the whole build: **$0.2316** across
all testing (day-of numbers only — Sitting 2's run happened the prior
calendar day and isn't included in that figure), well under the $0.50/day
cap throughout.

**Not yet done / open for later** (see `PLAN-infra-watch-v1.md`'s roadmap
section for full detail): Notion board (v1.1), real OSV/NVD vulnerability
lookups, extending the inventory beyond six components, and a separate
model-version-review track (Qwen/GLM) that's explicitly out of scope for
this project and not being built toward.
