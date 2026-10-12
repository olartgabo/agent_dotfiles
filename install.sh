#!/usr/bin/env bash
# Symlink every skill in this repo into ~/.claude/skills, so a `git pull` here
# updates the installed skills. An existing non-symlink skill of the same name
# is left alone and reported.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/claude/skills"
dest="$HOME/.claude/skills"
mkdir -p "$dest"

for skill in "$src"/*/; do
  name="$(basename "$skill")"
  target="$dest/$name"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "skip $name: $target exists and is not a symlink"
    continue
  fi
  ln -sfn "${skill%/}" "$target"
  echo "linked $name"
done
