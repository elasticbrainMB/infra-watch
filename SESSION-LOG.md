# SESSION-LOG.md — recap log for future chat threads

**What this file is.** Append-only. One dated entry per session, written so
a new chat thread can get caught up fast without reading the full
transcript. `STATE.md` is the current-facts snapshot (what's true *now*,
overwritten as facts change); this file is the narrative history behind
it — what happened, in what order, and why. Newest entry at the top.

---

## 2026-09-09 — update-execution, Docker Engine Sitting: 29.6.1 → 29.7.2 (target 29.8.0 not reached)

**Starting point:** `records\runbooks\docker.md` and `prompts\docker-update-apply.md`
(drafted in Cowork 2026-09-09, before this sitting) — the fourth instance of
the five-phase apply loop, and the first on the substrate itself: updating
the engine restarts the daemon, bouncing every tracked container at once,
so this sitting's checks had to cover the whole fleet, not one target.

**Chunk A (Step Zero + Phase 0, read-only):**
- Confirmed Docker Desktop (not a bare engine package) on a WSL2 backend —
  `docker info`'s `OSType: linux` and kernel string
  `6.18.33.1-microsoft-standard-WSL2` settle it; Windows commonly runs
  Desktop, but this wasn't assumed.
- **Downgrade-safety research done properly**, not from a cached prior —
  fetched GitHub's own release notes individually for every tag between
  current and target (`docker-v29.6.2`, `docker-v29.7.0`, `docker-v29.7.1`,
  `docker-v29.7.2`, `docker-v29.8.0`), not just a summarized docs page. None
  names a storage-format, data-layout, graphdriver, or
  containerd-snapshotter change — the only functional change in range is
  29.7.0 starting to *honor* `max-concurrent-downloads`/`-uploads` (a bug
  fix, not a format change).
- Full fleet captured: **6 containers**, not the 3 tracked ones —
  `kokoro`, `searxng-core`, `searxng-valkey` also run on this engine and
  also bounce. All 6 were `Up` at baseline.
- Two decisions surfaced to Matt explicitly via `AskUserQuestion` rather
  than decided unilaterally: (1) the `daemon.json` concurrency wrinkle —
  Matt chose to accept the new 3/5 default over pinning `0`/`0`; (2) no
  29.6.1-era rollback installer was retained anywhere on the host (the
  in-place `Docker Desktop Installer.exe` in the live install directory
  isn't a separately-retained artifact) — Matt approved fetching one.
- Found Docker's own published `checksums.txt` alongside the installer
  download (same S3/CloudFront host as the installer itself) — not
  documented anywhere, discovered by probing for the sidecar file the same
  way Node's `SHASUMS256.txt` and Ollama's `sha256sum.txt` worked. Fetched,
  hash-verified (exact match), and cross-checked against the live-installed
  file's own embedded version metadata (`4.81.0.232925`) before trusting it.
- `scripts\docker-update-check.ps1` written new — **fleet-scoped**, not
  single-target like `node-update-check.ps1`/`ollama-update-check.ps1`:
  engine version, full `docker ps -a` diffed by container name, each
  tracked container's own HTTP/health check, both dependents' Ollama
  reachability, `daemon.json`'s concurrency keys. openclaw's Ollama
  reachability check is a network-only curl from inside the container
  (never reads its provider config), staying inside CLAUDE.md's hard
  boundary. Ran a real Phase 0 capture (run `20260909-062238`, target
  pinned `29.8.0`) plus a separate no-op dry run (`20260909-062253`) to
  prove the diff mechanism itself works before trusting it — both clean.
- Reported everything and stopped, per the runbook's Chunk A/B split,
  handing Matt the install step.

**Chunk B (verify, on "installed"):**
- Matt reported the install ran but Desktop didn't visibly restart. Rather
  than guess whether a manual restart was needed, checked live: Desktop
  process start times were ~11 minutes after Phase 0's capture — a real
  restart had happened, just not a visibly obvious one. No manual restart
  needed.
- **Phase 2 verify surfaced a real mismatch**: the engine landed on
  `29.7.2`, not the pinned `29.8.0`. Root cause confirmed live, not
  assumed: Docker Desktop's newest available release (`4.90.0`, published
  2026-09-07) bundles engine `29.7.2` — Docker has not yet shipped a
  Desktop release bundling `29.8.0`, even though that engine tag has
  existed since 2026-09-03. No further "check for updates" click can reach
  it today; this is a structural gap in the update channel, not a
  transient one.
- Everything else in Phase 2 passed cleanly: 0 containers missing, 0 stuck
  restarting, 0 unexpected additions across the full fleet; all three
  tracked containers passed their own health check before and after; both
  open-webui and openclaw still reach Ollama; `daemon.json` unchanged,
  matching Matt's decision.
- This hit the runbook's own hard STOP condition ("target isn't pinned
  exact 29.8.0") — did not paper over it or silently treat 29.7.2 as
  equivalent. Asked Matt explicitly via `AskUserQuestion` how to close out;
  he chose to accept `29.7.2` and record it now rather than leave the
  inventory entry stale at `29.6.1`.
- `config\inventory.json`'s `docker` entry got a full `deployment` block
  (mechanism evidence, Desktop version history, the downgrade-safety
  research, the `daemon.json` decision, both installer records) — first
  time this component has one, following Node's/Ollama's precedent.
  `STATE.md` updated to match. **Per `TIERS.md`'s promotion rule, this does
  *not* promote Docker's apply step F→E** — the target-version miss is
  exactly the kind of surprise that keeps a component at Tier F for its
  next update, even though nothing actually broke; explicitly not treated
  as equivalent to Node's or Ollama's clean first runs.

---

## 2026-09-09 — Cowork sitting: Open WebUI queued for update-execution, current-note added to Notion

**Starting point:** Matt was mid-run on Docker's update-apply prompt in a
separate Claude Code session on the host when he noticed Open WebUI wasn't
part of the update-execution rollout and asked to have it added — from this
Cowork session, which can reach the repo over the device bridge but not run
PowerShell on the host this turn (the `infra-watch` folder mounted for file
access but not for a host shell).

- **Checked the premise first rather than editing on the word.** Open WebUI
  turned out to already be tracked — one of the seven `inventory.json`
  entries, checked for installed/release version every run — just never
  behind (0 releases behind since it was first tracked), so it never
  produced an assessment file, a Discord post, or a Notion row, and it was
  never named in `PLAN-update-execution-v1.md`'s original four-platform ask
  (n8n, Docker, Ollama, Node). Asked Matt via `AskUserQuestion` which gap he
  meant rather than guessing; he confirmed: queue it in the update-execution
  sequence, and add it to the Notion board.
- **`STATE.md` §1** — added Open WebUI as a fourth item on the
  update-execution queue (Docker Engine → OpenClaw → n8n → Open WebUI),
  ordered last since it has no known migration and no dependents, unlike
  the other three's migration-driven ordering. Read the file fresh
  immediately before editing (and re-checked its mtime) since the live
  Docker sitting could have been about to write its own close-out to the
  same file; no collision as of this edit.
- **`records\assessments\open-webui.md`** — a new "current, no action
  needed" note, written by hand in the shape `reconcile-current.ps1`
  produces (that script only touches components with a prior assessment
  file, and this component never had one), sourced from run
  `20260907-080001`'s `releases.json` (installed `0.11.3`, current
  `v0.11.3`, 0 behind).
- **Notion row created** for `open-webui` in the "Infra-Watch — Component
  Assessments" database, via the Notion MCP connector directly (queried
  first to confirm no row already existed) rather than `post-notion.ps1` —
  this session couldn't reach the host shell to run it. Same field mapping
  and page-body shape as the script produces, verified against
  `post-notion.ps1`'s own code and the live data source schema before
  writing.
- **Scope held to what was asked.** Did not write open-webui's runbook,
  check script, or apply prompt — Matt picked "queue it," not "build it
  now" — so those stay for whenever it actually falls behind.

---

## 2026-09-09 — update-execution, Ollama Sitting: 0.32.6 → 0.33.3

**Starting point:** `records\runbooks\ollama.md` (drafted in Cowork
2026-09-09, before this sitting) was a draft with every fact in its Step
Zero table marked `[VERIFY]` — the second concrete instance of the
five-phase apply loop, following Node's proven shape, but nothing on it had
been confirmed against the live host yet.

- **Closed Step Zero, read-only.** Install mechanism: registry Uninstall
  entry under **HKCU** (not HKLM), `_is1` suffix, `UninstallString` pointing
  at `unins000.exe`, no `WindowsInstaller` property — Inno Setup, not an
  MSI, so Node's ProductCode/UpgradeCode check doesn't apply here at all.
  Binary at `C:\Users\Matt Becker\AppData\Local\Programs\Ollama\ollama.exe`
  (a per-user AppData path, not Program Files).
- **Models path** confirmed the harder way, per CLAUDE.md's absent-env-var
  rule: `$env:OLLAMA_MODELS` is unset at every scope, so rather than
  assuming the documented default, read Ollama's own `server-1.log`
  "server config" line, which reports `OLLAMA_MODELS:C:\Users\Matt
  Becker\.ollama\models` as the actual effective path (it happens to match
  the default, but this is Ollama's own statement of it, not an inference
  from absence). Same log line also confirmed `OLLAMA_HOST:http://
  127.0.0.1:11434`, matching CLAUDE.md.
- **The caddy model** — the one fact the draft runbook flagged as
  untrustworthy from memory (Matt's old notes said `qwen3:14b`). Found the
  real answer by reading `C:\automation\caddy\scripts\caddy-server.js`
  directly: line 354 hardcodes `const MODEL = 'qwen3.5-caddy';`, called via
  POST to `/api/chat` (never `/api/generate` — the file's own comment says
  the latter ignores `think:false` for the qwen3.5 series) with
  `think:false` and `keep_alive:-1` as top-level fields. `ollama list`
  confirmed `qwen3.5-caddy:latest` present on the live host — a
  custom-derived 10GB tag, distinct from the base `qwen3.5:9b-q8_0` also
  present. Neither the stale name nor the base tag was the real answer.
- **Dependent reachability:** open-webui confirmed live via `docker inspect
  open-webui`'s env — `OLLAMA_BASE_URL=http://host.docker.internal:11434`.
  Openclaw was deliberately **not** dug into beyond that same env check
  (which found no equivalent var for it) — CLAUDE.md's hard boundary for
  this project reads OpenClaw's version only and never edits or actively
  probes its config, so its documented `host.docker.internal` baseUrl
  comes only from the (unverified-live) planning doc
  `caddy\openclaw-environment-spec-v1.md`. **Side finding, flagged to
  Matt rather than acted on:** that one `docker inspect openclaw` call
  incidentally surfaced openclaw's live Telegram bot token and gateway
  password in tool output. Nothing from it was written to disk anywhere in
  this project.
- **No `0.32.6` installer was retained anywhere on the host** — checked
  Downloads, Program Files, Ollama's own `updates_v2` update cache, and
  `C:\` root. This is an explicit hard STOP in both the runbook and this
  project's own file-download rule. Asked Matt via `AskUserQuestion`
  rather than assuming; he approved fetching both the `0.32.6` rollback
  artifact and the `v0.33.3` target from Ollama's official GitHub releases.
  Both downloaded (~1.5GB each, backgrounded) and hash-verified before
  being trusted — the target's checksum was cross-checked two independent
  ways (GitHub's own per-asset digest via `gh release view`, and Ollama's
  published `sha256sum.txt` for that release) and both agreed.
- Wrote all of Step Zero plus both installer records into a new
  `deployment` block on **only** the `ollama` entry in
  `config\inventory.json` (Decision F), mirroring Node's shape.
- Wrote `scripts\ollama-update-check.ps1` — `-Phase capture`/`-Phase
  verify` tied by `-RunId`, same shape as `node-update-check.ps1`, but
  capturing what Ollama's runbook actually calls for: `ollama --version`,
  the full `ollama list` output (diffed by name **and** size, not count),
  `ollama ps`, a live known-good chat-API query against the caddy model
  (recording the answer and latency), and open-webui's own round-trip to
  Ollama over `host.docker.internal` (confirmed live via `docker exec
  open-webui curl ...` — `curl` is present in that container and the call
  worked on the first try). Openclaw's round-trip is deliberately not
  probed, same boundary as Step Zero. No data-backup logic — per §4c an
  Ollama update is a binary swap and models aren't backed up.
- **Phase 0 ran clean** (run `20260909-054429`): version `0.32.6`, 3 models
  present, known-good query answered "OK" in 17.9s (a cold load — the
  caddy's own code comments call this the normal case), open-webui's
  round-trip HTTP 200.
- **Matt ran the verified `v0.33.3` installer by hand** — the one mutating
  step in the whole flow, same shape as Node's. Replied "installed."
- **Phase 2 verified PASS.** `ollama --version` exact match to `0.33.3`;
  model list unchanged (0 missing, 0 added, 0 size changes — all three
  models present at the same sizes); known-good query still answers
  correctly, though latency rose to 64.0s (not a pass/fail criterion —
  plausibly a fresh Ollama process cold-loading the model again after the
  install restarted it; noted, not treated as a surprise); open-webui's
  round-trip now reports `0.33.3` too, confirming the dependent picked up
  the real change. No Phase 3 triage needed.
- Updated `inventory.json`'s `ollama` deployment block: `current_version`
  now `0.33.3`, `version_history` added, `update_behavior` closed out with
  the real-run confirmation (binary/install paths unchanged, no
  side-install, models directory untouched). The `0.32.6` installer is now
  the rollback artifact for the 7-day window (Decision D), through
  2026-09-16.
- **Per `TIERS.md`'s promotion rule, this is Ollama's own first clean
  Tier-F run**, which promotes *Ollama's own* apply step F→E for its next
  update. This is separate from and not inherited from Node's earlier F→E
  promotion — the runbook's own gate section is explicit that promotion is
  per-component.
- Commit scoped to exactly what this sitting touched:
  `config\inventory.json`, `scripts\ollama-update-check.ps1`,
  `records\runs\20260909-054429\`, `STATE.md`, `SESSION-LOG.md`. Left
  pre-existing uncommitted changes to `CLAUDE.md`, `PLAN-update-
  execution-v1.md`, and the `prompts\` files untouched and unstaged, per
  CLAUDE.md's scoped-commit rule — this sitting didn't write any of those.

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

## 2026-09-08 (later, same day) — update-execution, Sitting 2: Node update applied

**Starting point:** Sitting 1 above closed every `[VERIFY]` gap except one —
the UpgradeCode match was confirmed only against the *installed* 24.18.0
MSI, not the real v24.20.0 target, which wasn't on the host yet. §9 step 5
(Matt's go-ahead to apply) was still pending.

- **Chunk A (prep/pre-checks).** The v24.20.0 x64 MSI wasn't found anywhere
  on the host (checked Downloads, Desktop, `C:\automation`) — only the
  retained 24.18.0 rollback MSI was present. Per the runbook's STOP
  condition, asked Matt how to proceed rather than guessing; he approved
  fetching it directly. Pulled `SHASUMS256.txt` from `nodejs.org` first to
  get the published hash, confirmed the file size via a HEAD request, told
  Matt the exact filename/source/size, then downloaded it and verified its
  SHA-256 matched the published value exactly before trusting it.
  Re-ran the same read-only WindowsInstaller COM UpgradeCode check from
  Sitting 1 against this real target MSI (once under Windows PowerShell,
  once re-run under pwsh 7 for discipline) — `{47C07A3A-42EF-4213-A85D-8F5A59077C28}`,
  matching the recorded UpgradeCode. This closed Sitting 1's one residual
  gap: the in-place major-upgrade replace assumption now holds against the
  real target, not just the installed version. Ran Phase 0 capture (run
  `20260908-220239`): `node v24.18.0` / `npm 11.16.0`, unchanged paths.
  Reported results and handed Matt the exact `msiexec /i ... /passive`
  command, then stopped.
- **Chunk B (verify and record), on Matt's "installed".** Phase 2 verify
  against the same run ID: **PASS**. `node` v24.18.0 → v24.20.0 (exact
  target), `npm` 11.16.0 → 11.19.0 (bundled bump — expected, not a
  regression, per the runbook's own "don't assume it matches 11.16.0"
  note), binary and npm paths unchanged, no side-install. Registry
  cross-check confirmed the live ProductCode
  (`{DC5BBE4F-0668-40DC-A913-83710DA79E35}`) and InstallSource (still
  Matt's own Downloads folder) — matches the new MSI's own Property table,
  as expected for a real in-place upgrade.
- Updated `config\inventory.json`'s node `deployment` block: `product_code`
  now the live one (old code preserved in a new `product_code_history`
  array rather than discarded), `update_behavior` closed out with the
  real-run confirmation.
- **Per `TIERS.md`'s promotion rule, Node's apply step moves F→E** — this
  was the one clean Tier-F run the rule requires. No surprise occurred
  (the npm bump was anticipated, not a regression), so nothing triggers the
  demotion rule.
- **Discovered mid-sitting: the working tree already carried unrelated,
  substantial uncommitted work** (a Notion-sync feature and a
  reconcile-current fix, dated 2026-09-09, touching `STATE.md`,
  `SESSION-LOG.md`, `PLAN-update-execution-v1.md`, four assessment files,
  `run-check.ps1`, and more — none of it done in this sitting). Caught this
  before compounding it: an early edit of mine had clobbered the
  pre-existing Notion "Last updated" note in `STATE.md`; reverted that
  specific damage immediately, restoring the original text, before
  finishing this sitting's own additions in the non-overlapping section.
  Flagged the entanglement to Matt before touching `git commit` — see his
  answer, if given, for how the commit(s) were actually scoped.

---

## 2026-09-09 (later same day) — Notion sync confirmed live

**Starting point:** the sitting above wired `post-notion.ps1` into
`run-check.ps1` but couldn't test the live HTTP path - no Notion API key
existed yet, and creating one isn't something this tool can do on Matt's
behalf.

- Matt asked where to create a new integration, since Settings →
  Connections only showed one existing internal connection
  (`project-status`, used by the unrelated portfolio-tracker GitHub
  Action) with no obvious "add new" button. Confirmed via Notion's own
  help docs that this wasn't a free-plan cap - the Connections hub Matt
  was on is for installing prebuilt connectors/MCP servers, while creating
  a new custom integration happens at the separate Developer portal
  (`app.notion.com/developers/connections`).
- Matt created an `infra-watch` internal integration there, shared the
  "Infra-Watch — Component Assessments" database with it, and added
  `NOTION_API_KEY=...` to `C:\automation\secrets\infra-watch.env`.
- Ran a live one-component test (`post-notion.ps1 -ComponentId docker`)
  from an actual terminal on the mini PC. It reported success; independently
  confirmed via the Notion API that the page's `last_edited_time` moved to
  that exact moment and its properties/body content came through unchanged
  and undamaged by the delete-and-rewrite cycle. This is the first real
  proof the auth, the upsert-by-Component lookup, the property PATCH, and
  the block delete+append all work against Notion's actual API, not just
  against a mocked/local test.
- The Notion board is now fully live. Nothing else is pending on this
  thread - the next scheduled Monday `run-check.ps1` run will be the first
  real unattended exercise of it.

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
---

## 2026-09-09 (later still) — reconcile-current fix for resolved components

**Starting point:** the sync just proved live end-to-end, but Matt asked a
sharp follow-up: once a component that was `do-now`/`schedule`/`defer`
actually gets updated and its `releases_behind` drops to 0, does its
Notion row (and its assessment file) actually show "current," or does it
just keep showing the old stale verdict forever? Answer at the time was
the latter — nothing in the pipeline ever revisited a component once it
left the `behind` list, so a resolved component would sit with its last
real verdict indefinitely, until the *next* release put it back in the
`behind` list and triggered a fresh `assess-update.ps1` call. Matt asked
for the fix.

- Added `scripts\reconcile-current.ps1` — deliberately not a variant of
  `assess-update.ps1`: no model call, no judgment to make. It takes a
  component id that `check-releases.ps1` already reported at
  `releases_behind: 0`, confirms that as a sanity check (throws if it
  isn't actually 0), and — only if `records\assessments\<id>.md` already
  exists for it (meaning it was behind at some point and has a real
  verdict sitting there) — overwrites that file with a short "current, no
  action needed" note. A component that's never been behind has never had
  an assessment file or a Notion row, and reconciliation leaves it alone.
- `run-check.ps1` now loops over every `current` component right after the
  `assess-update` loop, calling `reconcile-current.ps1` for any that have
  a prior assessment file. Its output is merged with the real assessments
  before the Notion-sync loop, so a reconciled component's file gets
  upserted to Notion exactly like any other — same `post-notion.ps1`
  call, no separate code path. Extended the run summary and the `#runs`
  Discord alert to call out "N now-current" separately from the do-now/
  schedule/defer counts.
- Patched `post-notion.ps1`'s parsing regexes to accept `current` as a 4th
  verdict value (alongside `do-now`/`schedule`/`defer`) and to also accept
  a "Current release:" source-line phrasing (the reconcile note has no
  "raw release notes" to point to, so it names the release it's now
  current with instead).
- Added a 4th Select option, `current` (green), to the "Verdict" property
  on the "Infra-Watch — Component Assessments" Notion database. Existing
  option data for the other three was preserved by the `ALTER COLUMN`
  call.
- **Verified offline only, three ways:** a synthetic fixture (fake
  component, fake prior assessment, fake 0-behind release data) exercised
  the full reconcile → parse → format path end to end; a regression run
  of `post-notion.ps1` against all five real assessment files came back
  byte-identical to before the regex change, confirming nothing broke for
  the normal case; and an isolated test of `run-check.ps1`'s new
  array-merging logic (`$notionTargets`, `$failed`, `components`) covered
  the empty-array and single-item-array edge cases PowerShell is known to
  silently unwrap. All three passed. No live test against a real
  currently-current component was possible this sitting — none of the
  five tracked components (`docker`, `n8n`, `node`, `ollama`, `openclaw`)
  is actually at `releases_behind: 0` this week; they're all genuinely
  still behind. This path gets its first live exercise whenever a
  component naturally resolves in a future scheduled run.
