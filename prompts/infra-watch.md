# infra-watch — planning

**Status: Planned, not yet built.** This document is the full v1 definition
for infra-watch — a read-only update tracker for Matt's self-hosted
infrastructure. It moves out of `planning\` into
`C:\automation\infra-watch\` the moment the project goes Active, per this
roadmap's own lifecycle rule in `..\CLAUDE.md`. Until then, this is the only
copy — see `..\projects\infra-watch.md` for the pointer entry.

Two parts, migrated in from a Cowork thread that ran in the caddy's
claude.ai project (*Vpin Skills Improvement*) before this project existed:

1. **Setup instructions** — steps for Matt to do by hand before the first
   Claude Code sitting (folder, repo, secrets file, what to copy from the
   caddy).
2. **Build handoff, Sitting 1** — paste this whole section as the first
   message of the first Claude Code sitting in the infra-watch project.

---

# Part 1 — clean project setup

**What this is.** Step-by-step instructions to stand up the update-tracker project
as a genuinely separate thing from the pinball caddy, reusing the parts of the
caddy that earned their keep and leaving behind the parts that didn't.

**Written 2026-09-03**, from a read of `C:\automation\caddy` at commit `66062ca`.

## 1. Names and locations

| Thing | Value |
|---|---|
| Project name | **infra-watch** |
| Folder | `C:\automation\infra-watch\` |
| GitHub repo | `elasticbrainMB/infra-watch` — **private** |
| Secrets file | `C:\automation\secrets\infra-watch.env` |
| Claude project | **infra-watch** (new, parallel to *Vpin Skills Improvement*) |
| Discord | reuse `#alerts` and `#decisions`, every post prefixed `[infra-watch]` |

**On the name.** Short, doesn't collide with `caddy`, and it doesn't bake
"versions" into the title — which matters because the model-review branch you
want as a roadmap item is a different kind of watching that may end up living
in the same repo.

**On reusing the Discord channels.** Your architecture plan already tuned those
two correctly: `#alerts` muted and carrying the log, `#decisions` pinging you and
carrying only things that need you. That split is exactly what this project
wants, and it's the reason not to create new channels — you'd be re-deriving a
notification setup you already got right. The prefix keeps the two projects
legible in one scrollback. If it gets noisy, split later; it's a one-line change.

## 2. Order of operations

Do these in order. Steps 1–4 are yours; step 5 hands off to Claude Code.

**1. Audit what's pinned, before anything else.**

This is the prerequisite that makes the whole project coherent, and it is worth
doing even if you never build the rest. Run:

```powershell
docker ps --format "{{.Names}}`t{{.Image}}"
```

Anything showing `:latest` is a component whose version can change under you on
the next restart, which means the tracker has nothing stable to compare against.
Pin those to explicit version tags. **Do not do this as part of a build sitting** —
recreating containers touches your hard boundary around live n8n workflows, and
it deserves your full attention rather than being step 3 of something else.

**2. Create the folder and the repo.**

```powershell
New-Item -ItemType Directory -Path C:\automation\infra-watch
cd C:\automation\infra-watch
git init
```

Create the private repo on GitHub, add the remote, and **push an empty initial
commit before you put anything in it.** The caddy's own roadmap listed "no remote
configured" as a standing risk for weeks. Don't re-run that experiment.

**3. Create the secrets file.**

`C:\automation\secrets\infra-watch.env`, same `NAME=value` shape the caddy uses:

```
OPENROUTER_API_KEY=...
DISCORD_WEBHOOK_RUNS=...
DISCORD_WEBHOOK_DECISIONS=...
GITHUB_TOKEN=...
```

The first three are copies of what's already in `caddy.env`. Duplicating one API
key is the right trade — a shared secrets file means a mistake in one project can
take out the other.

`GITHUB_TOKEN` is new and optional. Unauthenticated GitHub API calls are capped at
60 per hour, which is plenty for six components once a day, but a token raises it
to 5,000 and removes a class of confusing intermittent failure.
A fine-grained token with **public repo read access and nothing else** is all this
needs — it never writes anything.

**4. Connect the folder to Cowork** and create the Claude project (§5 below).

**5. Start the first Claude Code sitting** with the handoff prompt (Part 2, below).

## 3. What to copy from the caddy

Four files come across nearly as-is. They are the parts of the caddy that are
about *how to run work safely*, not about pinball.

| File | To | What changes |
|---|---|---|
| `scripts\invoke-model.ps1` | `scripts\invoke-model.ps1` | The four path constants near the top: `$secretsFile` → `infra-watch.env`, `$capsFile`, `$runsDir`, `$tmpDir`. **Nothing else.** The cap logic, the JSONL call log, the TEMP sweep that clears a leaked auth file, and the documented known-limit comment about caps being a gate rather than a ceiling all transfer intact. |
| `scripts\post-discord.ps1` | `scripts\post-discord.ps1` | `$secretsFile` only. Add the `[infra-watch]` prefix at the `$content` assembly line. Keep the catch block that makes a failed Discord post exit non-zero without failing the run — that behavior is correct and non-obvious. |
| `config\model-caps.json` | `config\model-caps.json` | Lower the numbers. The caddy sends 180–200 KB rules bundles; this sends changelogs. Start at `per_call_max_tokens: 16000`, `per_run_dollar_cap: 0.25`, `per_day_dollar_cap: 0.50` and raise only if a real run hits a wall. |
| `TIERS.md` | `TIERS.md` | **Verbatim, including the PROVISIONAL banner.** It is project-agnostic and it has never been applied to a real chunk. This project is a better place to test it than the caddy — lower stakes, shorter runs, and a genuine mix of all three tiers. |

Two more come across as **shape, not content** — read the caddy's version, keep
the structure and the standing discipline, throw out every pinball fact:

| File | Keep | Drop |
|---|---|---|
| `CLAUDE.md` | Execution discipline. The `[VERIFY]` rule. "Never infer a default from an absent environment variable." The four API-calling hazards (no `\| Out-Null`, no inline JSON to curl, no BOM, `-ceq` not `-eq`). "Use the fact, not a proxy for it." "How a check is written." "What belongs in this file." The n8n and OpenClaw hard boundaries — **more** relevant here, not less. | Rules-doc mechanics, table hashes, Ollama context-length archaeology, the definition of done for a rules doc, canonical-source rules for `rules\`. |
| `STATE.md` | The header paragraph explaining what the file is and is not, the numbered-section shape, and §6 the maintenance rule. | All six sections of content. Start it nearly empty and let it fill. |

And `.claude\settings.json` comes across as a **starting point with one section
kept and two rewritten**:

- **Keep the entire `deny` list verbatim.** Destructive git plus every mutating
  `docker` verb. This project is *about* Docker, which makes that list load-bearing
  rather than precautionary — a tracker that can `docker pull` is one bad
  assessment away from being an auto-updater you didn't ask for.
- **Rewrite `ask` and `allow`** for the new folder shape. `Edit(records/**)` and
  `Edit(config/**)` on allow; `Edit(scripts/**)` on ask. Drop the four caddy
  filename patterns — they select on files that won't exist here.
- Path rules use `Edit(...)`, never `Write(...)`, for the reason the caddy's
  `CLAUDE.md` already documents.

Also copy `.gitattributes` and `.gitignore` (adjusting the ignore paths).

## 4. What deliberately does not come across

Worth being explicit, because the instinct will be to bring more than this.

- **The three governing documents** — charter, roadmap, amendments. About 280 KB
  of pinball. Nothing in them governs this project.
- **Everything under `rules\`, `eval\`, `play\`, `briefs\`, `sources\`,
  `records\`, `prompts\`, `config-snapshots\`, `certs\`.**
- **`caddy-server.js`** and the whole drafting pipeline — `new-table.ps1`,
  `build-draft-bundle.ps1`, `verify-draft.ps1`, `reconcile-draft.ps1`,
  `retrieve-check.ps1`, `draft-by-api.ps1`.
- **`check-deps.ps1` and `check-owui-drift.ps1`** — do not copy, but **do read
  them once** before writing this project's collector. `check-deps.ps1` is a
  working example of a health check that hashes things and reports rather than
  acts. `check-owui-drift.ps1` already solves "read a live config and detect that
  it moved," which is a cousin of the problem here. Reference material, not a
  starting file.

## 5. The Claude project — and the one rule that keeps it clean

Create a new project named **infra-watch**. Copy your existing plain-language
project instructions across verbatim.

**Then keep it nearly empty**, and this is the part worth being deliberate about.

The Vpin project holds 157 documents. That's 157 surfaces that can drift out of
sync with disk, and the caddy has already been bitten by exactly that — on
2026-07-31 a file was found present in the claude.ai copy and absent from disk,
so the *stale* side was the disk. The caddy's own rule is that every copy outside
the canonical folder is "a dated snapshot and never a review input."

Since Cowork reads `C:\automation\infra-watch` directly through the connected
folder, the project doesn't need to hold operational files at all. Put in it:

- `PLAN-infra-watch-v1.md` — the charter, written in the first sitting
- The handoff prompt
- Nothing else

Everything operational — `STATE.md`, `CLAUDE.md`, scripts, records, assessments —
lives on disk only and is read from there. One canonical location, no drift
surface, and the fast-orientation file stays honest because there's only one of it.

## 6. Before the first sitting — a checklist

- [ ] `docker ps` audited; anything on `:latest` pinned to an explicit tag
- [ ] `C:\automation\infra-watch\` created, `git init`, private remote added, empty commit pushed
- [ ] `C:\automation\secrets\infra-watch.env` created with four values
- [ ] Four files copied and paths adapted: `invoke-model.ps1`, `post-discord.ps1`, `model-caps.json`, `TIERS.md`
- [ ] `.claude\settings.json` created — deny list verbatim, allow/ask rewritten
- [ ] Folder connected to Cowork
- [ ] Claude project **infra-watch** created with your project instructions
- [ ] Handoff prompt ready to paste

The pinning audit is the only one of these that can't be done inside a sitting.
Everything else can be handed to Claude Code if you'd rather — but the copies are
five minutes by hand and you'll want to have read `invoke-model.ps1` anyway.

---

# Part 2 — build handoff, Sitting 1

**Paste this whole section as the first message of the first Claude Code sitting
in the infra-watch project.**

## Before you act

**Verify everything yourself. Disk is authoritative; this handoff is not.** It was
written on 2026-09-03 from a read of the pinball-caddy repository, by a session
that has never seen the infra-watch folder. Anything it asserts about what is on
disk is a claim to check, not a fact to build on.

Read, in this order:

1. `CLAUDE.md` — the build rules for this project
2. `TIERS.md` — how closely a step is watched
3. `STATE.md` — what is true right now
4. `scripts\invoke-model.ps1` and `scripts\post-discord.ps1` — inherited from the
   caddy, already working, do not rewrite them

**Run commands verbatim. Show raw output, not summaries. STOP conditions are hard
stops — do not route around a failure. Failures are informative.**

## What this project is

A tool that answers one question on a schedule: **which of my self-hosted
components are behind, and which of those updates should I actually care about
this week?**

The thing being built is not an update notifier. Notifiers already exist —
`diun` and its relatives watch a registry and tell you a new tag appeared, and if
that were the whole job the correct move would be to install one and stop. **What
does not exist off the shelf is the judgment layer**: something that reads what
actually changed between the version you're running and the current one, and
sorts it into "do this tonight," "block out a Saturday," and "ignore."

The deliverable of a run is a **decision queue**, not a dashboard. If a run
produces nothing that needs Matt, it should say so in one line and be silent
otherwise.

## Scope

**In, for v1:**

- Six tracked components (§ *The inventory* below)
- Reading the installed version of each
- Reading the current released version of each
- A model-written assessment of the gap, from release notes and changelogs
- Output to disk, plus a Discord post to `#alerts` (log) and `#decisions` (only
  when something needs Matt)

**Out, for v1 — each of these is a deliberate cut, not an oversight:**

- **Applying any update.** This tool is strictly read-and-recommend. It never
  pulls, restarts, recreates or upgrades anything. The `deny` list in
  `.claude\settings.json` enforces this and is not to be widened.
- **Formal vulnerability lookup.** Mapping a product and version to known CVEs
  properly means OSV or NVD, and coverage for whole self-hosted applications
  (as opposed to their libraries) is thin enough that it would eat the entire
  v1 budget for a weak signal. v1's security signal is what the release notes
  say. If the notes say "fixes a security issue," that's the flag. Real lookups
  are a v2 candidate, listed at the end.
- **Notion.** v1.1. Get one real run's output on disk first, then design the
  board around fields that proved they matter.
- **Model versions** (Qwen, GLM). Separate roadmap item, described at the end.
  Do not build toward it in v1, but do not make it harder either.

## Architecture

```
C:\automation\infra-watch\
  CLAUDE.md
  STATE.md
  TIERS.md
  PLAN-infra-watch-v1.md        written this sitting
  TEMPLATE-assessment.md        the shape of one update assessment
  config\
    inventory.json              hand-maintained; what is tracked
    model-caps.json             inherited
  scripts\
    invoke-model.ps1            inherited — do not rewrite
    post-discord.ps1            inherited — do not rewrite
    read-installed.ps1          NEW  what version is running
    check-releases.ps1          NEW  what version is current
    assess-update.ps1           NEW  model reads the diff, writes a verdict
    run-check.ps1               NEW  one command, runs the above in order
  records\
    runs\                       model-calls.jsonl, raw responses per run
    assessments\                one .md per assessed update
```

**Disk is the source of truth. Discord is a mirror.** A run must succeed with
Discord unreachable. `post-discord.ps1` already behaves this way — a failed post
exits non-zero and reports, and never throws upward into the run.

## The inventory

`config\inventory.json` is **hand-maintained and seeded by Matt.** It is not
auto-discovered. Auto-discovering everything installed on the host is the scope
trap that turns this from a two-day build into a two-week one, and it produces a
list nobody curated.

One entry per component:

```json
{
  "id": "n8n",
  "display": "n8n",
  "kind": "docker",
  "installed_from": { "method": "docker-inspect", "container": "n8n" },
  "releases_from": { "method": "github", "repo": "[VERIFY]" },
  "blast_radius": "high",
  "notes": "Live workflows depend on this. Container recreation needs Matt's approval, per chunk."
}
```

**`blast_radius` is Matt's field, not the model's**, and this separation is the
central design idea of the whole tool. Matt pre-declares what an outage of this
component costs him — `high`, `medium`, `low` — because he is the only one who
knows. The model judges *the change*: is it a security fix, does it break
anything, does it need a migration. **Stakes are declared; change is assessed.**
The two multiply into the recommendation, and neither one alone produces a
useful answer. A cosmetic patch to a high-blast-radius component is still not
urgent; a breaking change to something nothing depends on is not a Saturday.

### The six components

| id | kind | installed version, read from | releases, read from |
|---|---|---|---|
| `n8n` | docker | `docker inspect` image tag | GitHub releases — `[VERIFY]` |
| `open-webui` | docker | `docker inspect` image tag | GitHub releases — `[VERIFY]` |
| `openclaw` | docker | `docker inspect` image tag | **`[VERIFY]` — see below** |
| `ollama` | host app | `ollama --version` | GitHub releases — `[VERIFY]` |
| `docker` | host app | `docker version --format` | Docker's own release notes — `[VERIFY]` |
| `node` / `pwsh` | host apps | `node --version`, `$PSVersionTable` | GitHub releases — `[VERIFY]` |

**Every repository path above is `[VERIFY]`. Resolve each one at build time and
do not accept a cached answer for any of them.** For OpenClaw this is not
boilerplate caution: a web search for the project returns several unrelated
repositories sharing the name plus a layer of SEO content farms, and there is no
way to tell from outside which one is actually running on this host. **Read it
off the running container** — `docker inspect` the image and look at the
`org.opencontainers.image.source` label, or the image's registry path — rather
than searching for it. If the label is absent, stop and ask Matt which project
he installed. A tracker pointed at the wrong upstream is worse than no tracker,
because it reports "up to date" forever.

**Also `[VERIFY]`:** `CLAUDE.md` in the caddy records PowerShell 7.6.4 while the
host is on 7.6.5. Read versions from the host, never from a document.

## What an assessment contains

One markdown file per component that is behind, in `records\assessments\`, from
`TEMPLATE-assessment.md`. Write the template this sitting.

Every assessment carries, at minimum:

- Component, installed version, current version, **how many releases behind**
- Whether a major or minor boundary was crossed
- `blast_radius`, copied from the inventory
- **The verdict**, one of exactly three: `do-now`, `schedule`, `defer`
- **Why**, in two or three plain sentences
- **What it will take** — a config change, a migration, a container recreation
- **A link to the raw release notes the verdict was drawn from**

That last line is not optional. The verdict is a model's opinion and must be
labelled as one, with the primary source one click away. This project inherits
the caddy's finding that **a model never grades its own output** — and the
corollary here is that a model's judgment is advisory input to Matt's decision,
never a substitute for it.

**"How many releases behind" is the metric that makes this actionable at a
glance.** One patch behind is noise. Eight releases and two minor versions behind
is accumulating migration debt, and it is the number that tells you which of
those you're looking at.

## Sitting plan

**Sitting 1 — inventory and collection. No model calls.**

1. Write `PLAN-infra-watch-v1.md` — this document's §*What this project is*
   through §*What an assessment contains*, as the project's own charter, in
   Matt's words rather than this handoff's.
2. Resolve every `[VERIFY]` above against the host and write
   `config\inventory.json`. **Stop and report if any repository path cannot be
   established from the running container.**
3. Write `read-installed.ps1`. Output JSON to `records\runs\`. Read-only.
4. Write `check-releases.ps1`. GitHub releases API, one call per component,
   authenticated if `GITHUB_TOKEN` is present. Output JSON.
5. Run both. Show raw output. **Sitting 1 ends here** — with a table of what's
   installed, what's current, and how far behind each one is. That table is
   already useful on its own, before any model has seen it.

**Sitting 2 — the judgment layer.**

6. Write `TEMPLATE-assessment.md`.
7. Write `assess-update.ps1`, calling `invoke-model.ps1` with the release notes
   between installed and current. **One component per call** — do not batch six
   components into one prompt. Batching is how a verdict for one leaks into
   another, which is the same failure the caddy recorded as "an absence phrased
   beside neighbours gets recruited into the disagreement."
8. Run it against the component with the **smallest** gap first. Read the raw
   output before running it against anything else.

**Sitting 3 — schedule and close.**

9. Write `run-check.ps1` — one command, end to end, with stop rules.
10. Wire the Discord posts. `#alerts` gets one line per run. `#decisions` gets a
    post **only** when at least one verdict is `do-now`, or a `schedule` verdict
    lands on a `high` blast radius.
11. Windows Task Scheduler, weekly. **Weekly, not daily** — the thing being
    tracked moves on a scale of weeks, and a daily job that says "nothing
    changed" six times a week trains you to stop reading it.
12. Update `STATE.md`. Commit.

## Stop conditions

Hard stops. Report and wait for Matt.

- Any `[VERIFY]` repository path that cannot be established from the running
  container or host.
- Any component whose installed version reads as `latest`, or cannot be
  determined. That means the pinning audit is incomplete, and comparison is
  meaningless until it isn't.
- Any model call that returns `finish_reason: length` or empty content. The
  caddy has hit this — reasoning tokens consuming the whole budget before any
  visible output. Raise `MaxTokens` within the cap, do not retry blindly.
- Any spend-cap trip in `invoke-model.ps1`.
- Any impulse to widen the `deny` list in `.claude\settings.json`.

## Standing rules inherited from the caddy

These are in `CLAUDE.md` and are repeated here because they cost something to
learn:

- Never `-s ... | Out-Null` on an API call — it hides a non-200.
- Inline JSON to `curl.exe` fails. Write the body to a file, no BOM, use `-d "@body.json"`.
- Write UTF-8 without a BOM: `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`.
- `-eq` compares strings case-insensitively. Byte equality needs `-ceq`.
- `Measure-Object -Line` is not a line count. Use `@(Get-Content <path>).Count`.
- Never infer a default from an absent environment variable.
- A gate states a decidable condition, not a count and not an adjective.

## Open roadmap item — model version reviews

**Not v1. Do not build toward it. Recorded here so it isn't lost.**

Matt wants a parallel track for reviewing new *model* releases — Qwen and GLM
both shipped new versions during the caddy build and there was no resource for
deciding whether to care. Current state as he describes it: Qwen is installed
locally on a pinned tag, GLM is configured as 5.2 in OpenRouter.

It is a genuinely different problem from this one and should not be forced into
the same pipeline. A new n8n has a changelog that says what changed; a new Qwen
is a different model whose only honest evaluation is running your own work
through it. The version-tracking half is nearly free once v1 exists — a model has
a release date and a tag. The review half is an eval harness, and the caddy
already has one (`eval\`, `cmp-answer.ps1`, `step5-baseline.ps1`) that would be
the natural starting point.

**Open question for Matt when this comes up:** does the model track live in this
repo as a second collector, or spin out as its own project? Argument for here:
the release-detection half is shared. Argument for separate: the deliverable is
a benchmark result, not a decision queue, and merging them would mean one tool
with two unrelated outputs.

## Other v2 candidates, parked

- Real vulnerability lookups via OSV, once v1's release-notes signal has been
  lived with long enough to know what it misses.
- Notion as a board, mirroring disk. v1.1.
- Extending the inventory beyond the six — the caddy's own Node dependencies,
  Tailscale, whatever else earns a line.

## First moves

1. Confirm the folder is connected and `git status` is clean.
2. Read the four files listed at the top.
3. Confirm `C:\automation\secrets\infra-watch.env` exists and
   `invoke-model.ps1` and `post-discord.ps1` point at it and not at `caddy.env`.
   **A path left pointing at the caddy is the single most likely inherited
   defect in this project** — the copies came from a working project and will run
   without complaint against the wrong secrets file and the wrong runs directory.
4. Begin Sitting 1, step 1.
