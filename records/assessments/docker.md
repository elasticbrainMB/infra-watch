# Docker Engine — 29.6.1 → docker-v29.8.0

_Assessment written 2026-09-04, run `20260904-053532`._

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

29.6.2 fixes five CVEs in BuildKit (command injection via Git bundle checkout, /tmp content removal, destination directory validation bypass, and more), and 29.7.0 fixes CVE-2026-17106 in go-archive. These are explicitly labeled security fixes affecting Docker Engine itself, so this shouldn't sit behind other work.

## What it will take

Nothing unusual beyond the normal update process (package upgrade plus a daemon restart, which will restart running containers unless live-restore is on). One optional config tweak: 29.7.0 now honors daemon-wide concurrent download/upload limits, so set "max-concurrent-downloads"/"max-concurrent-uploads" to 0 if you want the old unlimited behavior.

## Source

Raw release notes this verdict was drawn from: https://github.com/moby/moby/releases/tag/docker-v29.8.0

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._