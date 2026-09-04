# n8n — 2.26.0 → n8n@2.37.9

_Assessment written 2026-09-03, run `20260903-222833`._

| Field | Value |
|---|---|
| Component | `n8n` |
| Installed version | `2.26.0` |
| Current version (installed's own major line) | `n8n@2.37.9` |
| Releases behind | 40 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | high |

## Verdict: `defer`

Across all 40 releases the notes are almost entirely bug fixes and small features - nothing is labeled a security fix and nothing is described as broken in a way that demands immediate action. The only behavior changes worth noting are minor public-API tweaks (the offset query param removed from the workflow history endpoint, JSON content type now required on decorator routes) and the Google Ads node migrating from the sunset v21 API to v25, none of which the notes flag as requiring user migration.

## What it will take

Nothing beyond the normal update process - no config format change, migration step, or manual intervention is called for in any of the release notes.

## Source

Raw release notes this verdict was drawn from: https://github.com/n8n-io/n8n/releases/tag/n8n%402.37.9

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._