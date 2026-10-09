# Git hooks that travel

`.git/hooks/` is per-clone and is never cloned — a hook installed there protects
exactly one working copy on one machine. That is how the tile-pipeline gate was
first wired (2026-08-11) and an independent certification caught it the same day: the
countermeasure to a *propagation* failure was itself unpropagated.

Enable them once per clone:

    git config core.hooksPath .githooks

`pre-commit` does not carry the tile-pipeline gate itself. When `tool/*.py`,
`tool/requirements.txt` or `assets/tiles/*.mbtiles` are staged, it runs a gate
script kept outside this repository, the one `TILE_PIPELINE_GATE` names or a
default path under `$HOME`; where no such script is found, it prints a warning
and does not block (`.githooks/pre-commit:7-14`). On a machine without that
script, the hook checks nothing. It is quiet on every other path.
CI runs the same guards' `--self-test` from `tool/`, so a clone that never
enables hooks is still covered at the CI seam.

(2026-08-11: this sentence was FALSE when first written. The CI steps resolved
the guards through a path inside a different, private repo that a runner never
checks out, so both steps were permanent no-ops that always passed — measured by
a reproduction review with a clean $HOME. The guards are now vendored into `tool/` beside the
sibling guards that actually run, and the CI step exits 1 rather than skipping
if they are absent.)
