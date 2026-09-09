# Node.js runbook — 24.18.0 → v24.20.0

_Seeded 2026-09-08 from `records\assessments\node.md` (run `20260907-080001`,
the latest successful run for `node` — confirmed against
`records\runs\20260907-080001\summary.json` before writing this)._

Deployment facts below come from the `deployment` block added to the `node`
entry in `config\inventory.json` during this same sitting (verified read-only
against the live host, 2026-09-08).

| Field | Value |
|---|---|
| Component | `node` |
| Installed | `24.18.0` |
| Target | `v24.20.0` (within the installed 24.x major line) |
| Verdict | `do-now` — v24.18.1 fixes 12 CVEs, 3 rated High |
| `blast_radius` | low |
| Mechanism | Manual MSI install (nodejs.org official Windows x64 `.msi`) |
| Binary | `C:\Program Files\nodejs\node.exe` |

## Phase 0 — Pre-flight capture (read-only, infra-watch can run this)

- Record `node --version`, `npm --version`.
- Confirm target is a pinned, explicit version — `v24.20.0`, not a floating
  tag. Yes; stop here if this ever isn't true.
- Deployment facts already on file (no need to re-derive): install root
  `C:\Program Files\nodejs`, ProductCode `{6178C0C7-8EA8-458F-8060-E49E500A666F}`,
  UpgradeCode `{47C07A3A-42EF-4213-A85D-8F5A59077C28}`.
- If anything in this project or on the host has a build that depends on
  Node, capture its baseline build/run result now. None is currently on file
  for this project — if Matt has one in mind (e.g. the caddy build), name it
  before the real run so Phase 2 has something concrete to re-check.

## Phase 1 — Install (Matt runs by hand; infra-watch never does)

1. Download the official `v24.20.0` Windows x64 MSI (nodejs.org or
   https://github.com/nodejs/node/releases/tag/v24.20.0).
2. Before running it, read-only-verify its UpgradeCode matches
   `{47C07A3A-42EF-4213-A85D-8F5A59077C28}` — same check used in Chunk 1
   (open the MSI via the WindowsInstaller COM API, `OpenDatabase` mode 0,
   query the `Property` table; installs nothing). A match confirms this
   install will replace 24.18.0 in place rather than side-installing. If it
   doesn't match, stop and treat the mechanism as unconfirmed rather than
   assuming in-place behavior.
3. Run the MSI. Default install location is `C:\Program Files\nodejs`.
4. Open a fresh shell so PATH and any cached version lookups refresh.

## Phase 2 — Verify (read-only, infra-watch can run this)

- `node --version` equals `v24.20.0`.
- `npm --version` is sane (bundled npm for 24.20.0 — confirm against the
  release's own bundled-npm note, don't assume it matches 11.16.0).
- `C:\Program Files\nodejs\node.exe` still resolves as the `node` on PATH
  (no side-install created a second copy elsewhere).
- Whatever dependent build was named in Phase 0 still builds and runs.
- Diff against the Phase 0 capture: version changed, install root and binary
  path unchanged, nothing else moved.

## Phase 3 — Resolve (if verify fails)

- Assessment notes flag no config/API/CLI breaks in this range, so an
  unexpected failure here is not one the release notes predicted.
- `node --version` didn't change: check the MSI transaction actually
  completed (a pending reboot or a concurrent MSI transaction can cause a
  silent no-op) before assuming a deeper problem.
- Anything else unexpected → do not fight it live. Go to Phase 4.

## Phase 4 — Rollback (Matt runs by hand)

- Source: `C:\Users\Matt Becker\Downloads\node-v24.18.0-x64.msi`
  (SHA-256 `E30CD4CA15529583AFE0EFC978F1AE3AB3A93C2400C222D0752D17900552EBB3`,
  recorded in `inventory.json`'s `deployment.rollback_source`).
- Run that MSI (`msiexec /I{6178C0C7-8EA8-458F-8060-E49E500A666F}`) to
  reinstall 24.18.0.
- Re-run Phase 2's version check to confirm the rollback itself landed on
  `24.18.0` — a run isn't done until verify passes, forward or back.

## Retention

7-day artifact window (Decision D) applies to whatever Phase 0/Phase 2
capture files this project generates. It does not apply to the rollback MSI
itself — that's a pre-existing file in Matt's own Downloads folder, outside
this project's retention control.

## Gate

`blast_radius: low` → Tier E / near-checklist per
`PLAN-update-execution-v1.md` §5. Per `TIERS.md`'s promotion rule, the first
real apply on Node still runs at Tier F regardless — promotion to E happens
only after one clean F run, which this sitting's dry run (§9 step 4) is
building toward but does not itself satisfy, since nothing is applied yet.

## Source

Raw release notes this verdict was drawn from:
https://github.com/nodejs/node/releases/tag/v24.20.0

---

_This runbook is generated from a model's assessment and this project's own
read-only host discovery — advisory input to Matt's decision, not a
substitute for it. Every install and rollback step above is Matt's hand
action; infra-watch performs only the read-only capture and verify steps._
