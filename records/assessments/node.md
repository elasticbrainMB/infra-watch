# Node.js — 24.18.0 → v24.20.0

_Assessment written 2026-09-03, run `20260903-222833`._

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

v24.18.1 is explicitly a security release fixing twelve CVEs, including three rated High (http2 header memory accounting, http2 RST stream handling, and a permission-model radix split issue). The remaining releases (v24.19.0, v24.20.0) are routine semver-minor features and bug fixes with no breaking changes or migrations called out.

## What it will take

Nothing beyond the normal update process - no config format changes, API removals, or migration steps appear in the notes; just recreate the container/restart services on the new runtime.

## Source

Raw release notes this verdict was drawn from: https://github.com/nodejs/node/releases/tag/v24.20.0

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._