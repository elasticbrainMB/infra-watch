# infra-watch v1 — what this project is

**Written Sitting 1, 2026-09-03.** This is the project's charter: what it's
for, what's in and out of scope for v1, and what a run is supposed to
produce. `CLAUDE.md` and `STATE.md` point back here for the *why* behind the
build; this file is where that why lives.

## The question this answers

One question, on a schedule: **which of my self-hosted components are
behind, and which of those updates should I actually care about this week?**

This is not an update notifier. Notifiers already exist — `diun` and its
relatives watch a registry and tell you a new tag showed up, and if that were
the whole job the right move would be to install one of those and stop. What
doesn't exist off the shelf is the judgment layer: something that reads what
actually changed between the version I'm running and the version that's
current, and sorts it into "do this tonight," "block out a Saturday," and
"ignore."

The output of a run is a **decision queue**, not a dashboard. If a run finds
nothing that needs my attention, it says so in one line and stays quiet
otherwise.

## Scope

**In, for v1:**

- Six tracked components (below)
- Reading the installed version of each
- Reading the current released version of each
- A model-written assessment of the gap, from release notes and changelogs
- Output to disk, plus a Discord post to `#alerts` (log) and `#decisions`
  (only when something needs me)

**Out, for v1 — deliberate cuts, not oversights:**

- **Applying any update.** This tool is strictly read-and-recommend. It never
  pulls, restarts, recreates, or upgrades anything. The `deny` list in
  `.claude\settings.json` enforces this and isn't to be widened.
- **Formal vulnerability lookup.** Doing that properly means OSV or NVD, and
  coverage for whole self-hosted applications (as opposed to the libraries
  inside them) is thin enough that chasing it would eat the whole v1 budget
  for a weak signal. v1's security signal is whatever the release notes say —
  if they say "fixes a security issue," that's the flag. Real lookups are a
  v2 candidate.
- **Notion.** v1.1. I want one real run's output on disk first, so the board
  gets designed around fields that proved they matter, not guessed ones.
- **Model versions** (Qwen, GLM). A separate, later roadmap item — see
  below. Not built toward in v1, but not blocked by it either.

## Architecture

```
C:\automation\infra-watch\
  CLAUDE.md
  STATE.md
  TIERS.md
  PLAN-infra-watch-v1.md        this file
  TEMPLATE-assessment.md        the shape of one update assessment
  config\
    inventory.json              hand-maintained; what is tracked
    model-caps.json             inherited
  scripts\
    invoke-model.ps1            inherited — not rewritten
    post-discord.ps1            inherited — not rewritten
    read-installed.ps1          what version is running
    check-releases.ps1          what version is current
    assess-update.ps1           model reads the diff, writes a verdict
    run-check.ps1               one command, runs the above in order
  records\
    runs\                       model-calls.jsonl, raw responses per run
    assessments\                one .md per assessed update
```

**Disk is the source of truth. Discord is a mirror.** A run has to succeed
even with Discord unreachable. `post-discord.ps1` already behaves that way —
a failed post exits non-zero and reports, and never throws upward into the
run.

## The inventory

`config\inventory.json` is **hand-maintained by me, not auto-discovered.**
Auto-discovering everything installed on the host is the scope trap that
turns this from a two-day build into a two-week one, and the list it
produces is one nobody actually curated.

One entry per component, shaped like:

```json
{
  "id": "n8n",
  "display": "n8n",
  "kind": "docker",
  "installed_from": { "method": "docker-inspect", "container": "n8n" },
  "releases_from": { "method": "github", "repo": "[VERIFY]" },
  "blast_radius": "high",
  "notes": "Live workflows depend on this. Container recreation needs my approval, per chunk."
}
```

`blast_radius` is my field, not the model's, and that split is the central
design idea of the whole tool. I pre-declare what an outage of this
component costs me — `high`, `medium`, `low` — because I'm the only one who
knows that. The model judges *the change*: is it a security fix, does it
break anything, does it need a migration. Stakes are declared; change is
assessed. The two multiply into the recommendation, and neither one alone
produces a useful answer. A cosmetic patch to a high-blast-radius component
is still not urgent; a breaking change to something nothing depends on isn't
a Saturday.

### The six components

| id | kind | installed version, read from | releases, read from |
|---|---|---|---|
| `n8n` | docker | `docker inspect` image tag | GitHub releases |
| `open-webui` | docker | `docker inspect` image tag | GitHub releases |
| `openclaw` | docker | `docker inspect` image tag | GitHub releases — resolved from the running container's own labels, never guessed |
| `ollama` | host app | `ollama --version` | GitHub releases |
| `docker` | host app | `docker version --format` | Docker's own release notes |
| `node` / `pwsh` | host apps | `node --version`, `$PSVersionTable` | GitHub releases |

Every repository path above gets resolved against the live host at build
time, not accepted from memory or from a document. For OpenClaw this isn't
boilerplate caution: a web search for the project turns up several unrelated
repositories sharing the name plus a layer of SEO content farms, and there's
no way to tell from outside which one is actually running here. The way to
find out is to read it off the running container — the image's
`org.opencontainers.image.source` label, or its registry path — rather than
searching for it. If the label is absent, the answer is to stop and ask me
which project I installed, not guess. A tracker pointed at the wrong
upstream is worse than no tracker, because it reports "up to date" forever.

## What an assessment contains

One markdown file per component that's behind, in `records\assessments\`,
built from `TEMPLATE-assessment.md`.

Every assessment carries, at minimum:

- Component, installed version, current version, **how many releases behind**
- Whether a major or minor boundary was crossed
- `blast_radius`, copied from the inventory
- **The verdict**, one of exactly three: `do-now`, `schedule`, `defer`
- **Why**, in two or three plain sentences
- **What it will take** — a config change, a migration, a container
  recreation
- **A link to the raw release notes the verdict was drawn from**

That last line isn't optional. The verdict is a model's opinion and has to
be labelled as one, with the primary source one click away. A model never
grades its own output, and the corollary here is that a model's judgment is
advisory input to my decision, never a substitute for it.

"How many releases behind" is the metric that makes this actionable at a
glance. One patch behind is noise. Eight releases and two minor versions
behind is accumulating migration debt, and that number is what tells you
which of those you're looking at.

## Open roadmap item — model version reviews

**Not v1. Not built toward yet.** Recorded here so it isn't lost.

I want a parallel track for reviewing new *model* releases — Qwen and GLM
both shipped new versions during the caddy build and there was no way to
decide whether to care. Current state: Qwen runs locally on a pinned tag,
GLM is configured as 5.2 in OpenRouter.

It's a genuinely different problem from this one and shouldn't be forced
into the same pipeline. A new n8n has a changelog that says what changed; a
new Qwen is a different model whose only honest evaluation is running my own
work through it. The version-tracking half is nearly free once v1 exists — a
model has a release date and a tag. The review half is an eval harness, and
the caddy already has one (`eval\`, `cmp-answer.ps1`, `step5-baseline.ps1`)
that would be the natural starting point.

**Open question for later:** does the model track live in this repo as a
second collector, or spin out as its own project? Argument for here: the
release-detection half is shared. Argument for separate: the deliverable is
a benchmark result, not a decision queue, and merging them means one tool
with two unrelated outputs.

## Other v2 candidates, parked

- Real vulnerability lookups via OSV, once v1's release-notes signal has
  been lived with long enough to know what it misses.
- Notion as a board, mirroring disk. v1.1.
- Extending the inventory beyond the six — the caddy's own Node
  dependencies, Tailscale, whatever else earns a line.
