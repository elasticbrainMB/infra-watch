# OpenClaw — 2026.7.1 → v2026.9.1

_Assessment written 2026-09-04, run `20260904-053532`._

| Field | Value |
|---|---|
| Component | `openclaw` |
| Installed version | `2026.7.1` |
| Current version (installed's own major line) | `v2026.9.1` |
| Releases behind | 3 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | medium |

## Verdict: `do-now`

The 2026.8.2 notes literally say the managed Sharp dependency update is "fixing vulnerabilities in image decoding," which is an explicit security fix, and 2026.9.1 adds further hardening around ingress, token, and secret-redaction boundaries. On top of that, 2026.8.1 ships two labeled breaking migrations (removal of the bundled OpenProse plugin and the codex/openai-codex to openai/* route migration) that require `openclaw doctor --fix` to complete.

## What it will take

Back up configuration and state first, then run the update followed by `openclaw doctor --fix` to complete the OpenProse cleanup and OpenAI route migration (flagged conflicts need manual repair), and verify the Gateway starts cleanly - effectively a deliberate migration window, not a routine container recreation.

## Source

Raw release notes this verdict was drawn from: https://github.com/openclaw/openclaw/releases/tag/v2026.9.1

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._