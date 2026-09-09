# Ollama — 0.32.6 → v0.33.3

_Assessment written 2026-09-07, run `20260907-080001`._

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

Nothing here is a security fix - the notes are dominated by new model support (Muse Glimmer, Nemotron 3.5 Lightning, Qwen 3.8, gemma4 multimodal) and features like the Claude Desktop gateway. But there are real stability fixes worth having on a high-traffic inference server: chat/generate could wedge after a mid-stream parser error (0.32.15), cancelled long prefills could hang and resumed prefills reprocessed ~46k tokens from zero (0.33.0), and metadata caching roughly halves time-to-first-token. No breaking config, API, or CLI changes are called out, so nothing demands immediate action.

## What it will take

Nothing beyond the normal update process - no migration or config changes are mentioned, just a binary swap or container recreation. One caveat: 0.33.0 notes that default packaging was broken on Linux/Windows by macOS-specific assumptions, so updating directly to 0.33.3 rather than stepping through intermediate releases avoids that.

## Source

Raw release notes this verdict was drawn from: https://github.com/ollama/ollama/releases/tag/v0.33.3

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._