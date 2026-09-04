# STATE.md — current state, fast orientation

**What this file is.** A short, current-facts-only summary — not a design
document and not a history. Nothing here overrides or restates *why*
something became true; `PLAN-infra-watch-v1.md` remains authoritative on
*how* and *why*, and stays archive, read on demand. Read this file first;
go to the full plan only when a provenance question actually requires it.

_Last updated: 2026-09-04 — project moved from Planned to Active._

## 1. What's tracked

Not yet populated. `config\inventory.json` and the six-component baseline
get written in Sitting 1.

## 2. In progress

**Sitting 1 (inventory and collection) not yet started.**

## 3. Blocked, and on whom

Nothing yet.

## 4. Governance items open

None yet.

## 5. Standing rules in force

- **This project never applies an update** — read-and-recommend only. Enforced in `.claude\settings.json`.
- **Model-call caps**, read fresh from `config\model-caps.json`: `per_call_max_tokens` 16000, `per_run_dollar_cap` $0.25, `per_day_dollar_cap` $0.50.
- **Write-permission split** — confirmed fresh against `.claude\settings.json`: free `Edit` access to `records\` and `config\`; `scripts\` is an explicit `ask`-gate entry.

## 6. Maintenance rule for this file

Update this file at the close of any sitting that changes one of the facts
above — a component gets tracked, a verdict lands, a cap changes. Not on a
schedule, and not for anything outside those categories.
