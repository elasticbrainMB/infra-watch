# Docker Engine — 29.6.1 → docker-v29.8.0

_Assessment written 2026-09-07, run `20260907-080001`._

| Field | Value |
|---|---|
| Component | `docker` |
| Installed version | `29.6.1` |
| Current version (installed's own major line) | `docker-v29.8.0` |
| Releases behind | 5 |
| Minor boundary crossed | True |
| Newer major/track exists (uncounted) | no |
| `blast_radius` | high |

## Verdict: `do-now`

The notes explicitly flag security fixes: 29.6.2 patches five CVEs including command injection via Git source checkout (CVE-2026-15793) and an LLB file operation that can wipe /tmp contents (CVE-2026-15791), and 29.7.0 fixes CVE-2026-17106 in go-archive. 29.8.0 adds further hardening such as a configurable default AppArmor profile template and fixing a world-writable container root under the btrfs storage driver. Jumping straight to 29.8.0 also sidesteps the image-pull and docker cp regressions that 29.7.0 introduced and 29.7.1/29.7.2 had to patch.

## What it will take

Nothing beyond the normal update process (package upgrade plus daemon restart); the one config wrinkle is that 29.7.0 now honors daemon-wide concurrent download/upload limits, so set "max-concurrent-downloads" and "max-concurrent-uploads" to 0 if the previous unlimited pull/push behavior is wanted.

## Source

Raw release notes this verdict was drawn from: https://github.com/moby/moby/releases/tag/docker-v29.8.0

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._