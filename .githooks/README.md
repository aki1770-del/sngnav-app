# Git hooks that travel

`.git/hooks/` is per-clone and is never cloned — a hook installed there protects
exactly one working copy on one machine. That is how the tile-pipeline gate was
first wired (2026-08-11) and CT's certification caught it the same day: the
countermeasure to a *propagation* failure was itself unpropagated.

Enable them once per clone:

    git config core.hooksPath .githooks

`pre-commit` runs the tile-pipeline gate when `tool/*.py`, `tool/requirements.txt`
or `assets/tiles/*.mbtiles` are staged. It is quiet on every other path.
CI runs the same guards' `--self-test`, so a clone that never enables hooks is
still covered at the CI seam.
