# n8n — 2.26.0 → n8n@2.37.11

_Assessment written 2026-09-07, run `20260907-080001`._

| Field | Value |
|---|---|
| Component | `n8n` |
| Installed version | `2.26.0` |
| Current version (installed's own major line) | `n8n@2.37.11` |
| Releases behind | 42 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | high |

## Verdict: `schedule`

Nothing in these 42 releases claims a security fix - the bulk is routine bug fixes (editor UI, AI Agent behavior, task runner recovery, proxy/TLS handling). However, 2.36.7 makes real API behavior changes (removing the offset query param from the workflow history endpoint and requiring a JSON content type on decorator routes), and 2.34.6/2.35.3 migrate the Google Ads node off the sunset v21 API, so anything scripting the API or using Google Ads workflows is broken or will break on the current version. The task runner resilience and recovery fixes (2.33.4, 2.35.5) are also worth having on a heavily used automation instance.

## What it will take

Nothing unusual per the notes - a normal container recreation, though jumping several minor lines means n8n will likely run its automatic startup migrations, so pick a planned window. If Matt scripts against the public API, grep for the removed offset param on the workflow history endpoint first.

## Source

Raw release notes this verdict was drawn from: https://github.com/n8n-io/n8n/releases/tag/n8n%402.37.11

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._