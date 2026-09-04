# Ollama — 0.32.6 → v0.33.3

_Assessment written 2026-09-03, run `20260903-222833`._

| Field | Value |
|---|---|
| Component | `ollama` |
| Installed version | `0.32.6` |
| Current version (installed's own major line) | `v0.33.3` |
| Releases behind | 12 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | high |

## Verdict: `schedule`

Nothing in these notes is a security fix, and no release mentions a config, API, or CLI break or a required migration, so there's no urgency. But the line does fix real operational bugs present in the installed version — chat/generate could wedge after a mid-stream parser error (0.32.15) and agent clients cancelling long prefills could hang (0.33.0) — and the caching work roughly halves time-to-first-token (~995ms to ~524ms) and stops resumed prefills from reprocessing tens of thousands of tokens from zero. For a heavily-used inference service, those stability and performance fixes are worth doing deliberately soon.

## What it will take

Nothing beyond the normal update process — the notes call for no config changes or migrations, just pulling the new version and recreating the container. The only first-run oddity is a new desktop onboarding flow, which shouldn't matter for a headless install.

## Source

Raw release notes this verdict was drawn from: https://github.com/ollama/ollama/releases/tag/v0.33.3

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._