# n8n — 2.26.0 → n8n@2.37.10

_Assessment written 2026-09-04, run `20260904-053532`._

| Field | Value |
|---|---|
| Component | `n8n` |
| Installed version | `2.26.0` |
| Current version (installed's own major line) | `n8n@2.37.10` |
| Releases behind | 41 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | high |

## Verdict: `defer`

Across all 41 releases the notes describe only bug fixes and small features - nothing labeled a security fix, no config or API breaking change, and no migration steps. The closest to notable are the Google Ads node moving from the sunset v21 API to v25 and assorted proxy/TLS handling fixes, but these are handled internally by n8n rather than requiring action from Matt. Nothing here is broken on his instance or actively causing problems per the notes.

## What it will take

Nothing beyond the normal update process - a container recreation with the new image tag; the notes call for no config changes or migrations.

## Source

Raw release notes this verdict was drawn from: https://github.com/n8n-io/n8n/releases/tag/n8n%402.37.10

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._