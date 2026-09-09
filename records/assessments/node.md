# Node.js — 24.18.0 → v24.20.0

_Assessment written 2026-09-07, run `20260907-080001`._

| Field | Value |
|---|---|
| Component | `node` |
| Installed version | `24.18.0` |
| Current version (installed's own major line) | `v24.20.0` |
| Releases behind | 3 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | v26.8.1 |
| `blast_radius` | low |

## Verdict: `do-now`

v24.18.1 is explicitly a security release fixing a dozen CVEs, three of them rated High (http2 header memory accounting, http2 rst stream deferral, and permission model radix split nodes), plus Medium-severity fixes in https, sqlite, dns, and zlib. The two later releases are additive SEMVER-MINOR features and bug fixes with no breaking changes or migration steps called out. The security content alone makes this worth applying immediately.

## What it will take

Nothing beyond the normal update process - it stays within the v24 major line and the notes flag no config, API, or CLI breaks; if Node runs in containers, it's just pulling the new image tag and recreating.

## Source

Raw release notes this verdict was drawn from: https://github.com/nodejs/node/releases/tag/v24.20.0

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._