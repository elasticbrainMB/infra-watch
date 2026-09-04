# {{display}} — {{installed_version}} → {{current_version}}

_Assessment written {{date}}, run `{{run_id}}`._

| Field | Value |
|---|---|
| Component | `{{id}}` |
| Installed version | `{{installed_version}}` |
| Current version (installed's own major line) | `{{current_version}}` |
| Releases behind | {{releases_behind}} |
| Minor boundary crossed | {{minor_boundary_crossed}} |
| Newer major/track exists (uncounted) | {{newer_major_line_exists}} |
| `blast_radius` | {{blast_radius}} |

## Verdict: `{{do-now | schedule | defer}}`

{{Two or three plain sentences on why. What in the release notes drove this
call — a security fix, a breaking change, a migration step, nothing of
consequence. State it, don't hedge it.}}

## What it will take

{{Concrete: a config change, a migration step, a container recreation, or
"nothing — same as any routine bump." If a container recreation is implied,
say so plainly; this tool does not perform it.}}

## Source

Raw release notes this verdict was drawn from: {{release_url}}

---

_This verdict is a model's reading of the release notes, not a substitute for
Matt's own judgment. `blast_radius` was declared by Matt in `inventory.json`;
everything else on this page is the model's assessment of the change itself._
