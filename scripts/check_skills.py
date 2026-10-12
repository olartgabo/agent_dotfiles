#!/usr/bin/env python3
"""Fail if a skill is malformed or leaks a machine-specific path.

Checks every claude/skills/*/SKILL.md: front matter present, `name` matches
the directory, `description` non-empty. Checks every file under claude/ for
absolute home-directory paths, which only work on one machine.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
errors = []

for skill_dir in sorted((root / "claude" / "skills").iterdir()):
    if not skill_dir.is_dir():
        continue
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        errors.append(f"{skill_dir.name}: missing SKILL.md")
        continue
    text = skill_md.read_text()
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        errors.append(f"{skill_md}: missing front matter")
        continue
    front = match.group(1)
    name = re.search(r"^name:\s*(\S+)\s*$", front, re.M)
    if not name or name.group(1) != skill_dir.name:
        errors.append(f"{skill_md}: name must be '{skill_dir.name}'")
    if not re.search(r"^description:\s*(>\s*\n\s+\S|\S)", front, re.M):
        errors.append(f"{skill_md}: description is empty")

home_path = re.compile(r"/(home|Users)/[A-Za-z0-9._-]+/")
for path in sorted((root / "claude").rglob("*")):
    if path.is_file():
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            if home_path.search(line):
                errors.append(f"{path.relative_to(root)}:{lineno}: absolute home path; use ~ or an env var")

for error in errors:
    print(error)
sys.exit(1 if errors else 0)
