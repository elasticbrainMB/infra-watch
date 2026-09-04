# Docker Engine — 29.6.1 → docker-v29.8.0

_Assessment written 2026-09-03, run `20260903-222833`._

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

29.6.2 is an explicit security release fixing five CVEs in Docker Engine and BuildKit, including command injection via Git bundle checkout (CVE-2026-15793) and a malicious client bypassing destination directory validation on source uploads. 29.7.0 adds another CVE fix (CVE-2026-17106 in go-archive), and 29.8.0 further hardens things with AppArmor/SELinux rules blocking the 32-bit socketcall path to AF_VSOCK sockets. Going straight to 29.8.0 also skips over the 29.7.0 pull regressions that 29.7.1 and 29.7.2 had to patch.

## What it will take

Nothing beyond the normal update process - a package upgrade plus a dockerd restart, which restarts containers unless live-restore is enabled. One config note from 29.7.0: daemon-wide max-concurrent-downloads/uploads limits are now actually enforced, so set both to 0 in daemon.json if the previous unlimited behavior is desired.

## Source

Raw release notes this verdict was drawn from: https://github.com/moby/moby/releases/tag/docker-v29.8.0

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`; everything else on this page is the model's assessment of the change itself._