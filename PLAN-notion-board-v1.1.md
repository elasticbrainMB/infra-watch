# Notion board (v1.1) — design

_Drafted 2026-09-08, against run `20260907-080001` (`records\assessments\docker.md`,
`node.md`, `n8n.md`, `ollama.md`). Notion MCP tools not yet reachable in-session
(connector shows connected + all tools allowed in Settings; likely needs an app
relaunch to register). This doc is the build-ready spec for when they are — no
Notion calls made yet._

## Source of truth

Every field below traces to one of two real files on disk. Nothing is invented:

- The five-row table + H1 + date line in each `records\assessments\*.md` file
  (per `TEMPLATE-assessment.md`, confirmed against the four real files).
- `config\inventory.json` — read directly (not `STATE.md`'s echo of it) for the
  7 component `id`/`display`/`blast_radius` values, since a Select property's
  option list is a concrete value worth pulling from the source, not a summary.

## Database properties

One database, one row per tracked component, upserted on `Component` (not
appended) — each weekly run overwrites the matching row, same as
`records\assessments\<id>.md` overwrites in place on disk. That's what makes
this a mirror rather than a log.

| Property | Type | Source | Example |
|---|---|---|---|
| Name | Title | `{{display}}` from the H1 | `Docker Engine` |
| Component | Select (7 fixed options, from `inventory.json`: n8n, open-webui, openclaw, ollama, docker, node, pwsh) | `Component` table row | `docker` |
| Installed version | Rich text | `Installed version` table row | `29.6.1` |
| Current version | Rich text | `Current version (installed's own major line)` table row | `docker-v29.8.0` |
| Releases behind | Number | `Releases behind` table row | `5` |
| Minor boundary crossed | Checkbox | `Minor boundary crossed` table row | `true` |
| Newer major/track exists | Rich text | `Newer major/track exists (uncounted)` table row — stays text; value is either the literal `no` or a version string (`v26.8.1`), so it can't be split into a boolean without inventing structure the file doesn't have | `no` / `v26.8.1` |
| Blast radius | Select (high / medium / low, from `inventory.json`) | `` `blast_radius` `` table row | `high` |
| Verdict | **Status** (do-now / schedule / defer) | `## Verdict: `{{verdict}}`` heading | `do-now` |
| Assessment date | Date | `_Assessment written {{date}}_` line | `2026-09-07` |
| Run ID | Rich text | same line, `` `{{run_id}}` `` | `20260907-080001` |
| Source URL | URL | link under `## Source` | `https://github.com/moby/moby/releases/tag/docker-v29.8.0` |

Verdict is **Status**, not Select — Status is Notion's board-grouping property
type, so opening this database as a Board view and grouping by Verdict gives
Matt do-now / schedule / defer columns natively. That's the literal ask
("Notion as a board").

## Page body (per row, mirrors the two prose sections + footer)

1. Heading "Verdict: `{{verdict}}`" — the Why paragraph as body text.
2. Heading "What it will take" — that paragraph as body text.
3. The Source link, repeated as a body link (cheap, keeps the page a full
   mirror of the file, not just the table).
4. The disclaimer footer, as a quote/callout block — present verbatim in
   every file, so mirroring it is more faithful than dropping it as
   boilerplate.

## Open judgment calls (not resolved here — need Matt)

1. **`openclaw.md` is on disk right now but is stale** (written 2026-09-04,
   from a prior run — the 09-07 run's `summary.json` shows
   `{"id": "openclaw", "ok": false, "verdict": null}`, i.e. this run's
   assessment attempt failed and the old file was never overwritten). Two
   honest options:
   - Build only the 4 rows yesterday's run actually produced (matches the
     Discord notification Matt has for that run).
   - Build 5 rows — true current disk state includes openclaw — and let its
     older `Assessment date` visibly signal it's stale, which a mirror
     arguably should surface rather than hide.
   Leaning toward **option 2** since "mirroring disk" was the stated goal and
   an oddly-dated row is informative, not a bug — but this is Matt's call.
2. **Database name/location** — no existing Notion workspace structure is
   visible yet (tools unreachable). Once they're up, first call should be a
   search/list to see if Matt already has an "Infra-Watch" page or similar
   before creating a new top-level database.
3. Unrelated but noticed in-repo: `.github\workflows\notion-status.yml`
   already pushes this project's commit metadata to a *different* Notion
   database (a portfolio "Projects" tracker, keyed on project name, via repo
   secrets) on every push to `main`. Different database, different purpose
   (project-level status vs. per-component assessments) — flagging only so
   the new board doesn't get confused with it or accidentally targeted at
   the same database ID.

## Build steps once Notion tools are reachable

1. Confirm connector identity again (`notion-search` / `notion-create-pages`
   etc. — official Notion MCP tool names) and resolve the two judgment calls
   above with Matt.
2. Search the workspace for an existing home page/database before creating
   new.
3. Create the database with the 12 properties above.
4. Create one page per row (4 or 5, per judgment call #1), setting
   properties + page body per the mapping above.
5. Record the database URL/ID in `STATE.md` and note the addition in
   `SESSION-LOG.md`, per this repo's own maintenance rules.
