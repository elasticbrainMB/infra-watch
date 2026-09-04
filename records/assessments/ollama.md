# Ollama — 0.32.6 → v0.33.3

_Assessment written 2026-09-04, run `20260904-053532`._

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

No security fixes and no breaking config or API changes across the 12 releases - the bulk is new model support (Muse Glimmer, Nemotron 3.5, Qwen 3.8, gemma4 multimodal) plus launcher integrations. However, v0.32.15 and v0.33.0 fix real operational bugs: chat/generate wedging after mid-stream parser errors, hangs when agent clients cancel long prefills, and a KV-cache-breaking interaction with Claude Code, alongside a caching change that roughly halves time-to-first-token. Those reliability and performance fixes make this worth doing deliberately rather than sitting on.

## What it will take

Nothing beyond the normal update process - no migration steps, config format changes, or CLI behavior changes are mentioned in the notes.

## Source

Raw release notes this verdict was drawn from: https://github.com/ollama/ollama/releases/tag/v0.33.3

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._