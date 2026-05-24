# L3FTools Agent Guide

L3FTools is the active WoW addon suite. It is collaborative work with Willem and Kerweek, so GitHub history and the current branch are the shared truth.

## Working Branch

- Use `dev` for all normal work.
- `main` is stable/release-oriented.
- Keep changes small enough for another collaborator to review.

## Before Editing

- Read `CLAUDE.md` for project facts, but treat it as inherited context.
- Check current Git status.
- Identify whether a change must also apply to `../AutomarkerL3F`.
- Do not rewrite large Lua files unless the task truly requires it.

## Mirrored Work

Mirror changes with AutomarkerL3F when touching:

- Automarker engine behavior
- raid NPC registries in `Data/<Raid>.lua`
- wing layouts in `Sections/<Raid>.lua`
- mark assignment defaults

L3FTools-only tabs, Atlas data, Guild tools, Crafts, Raid Planner, Planner, and map features do not need AutomarkerL3F changes unless they touch shared automarker behavior.

## Verification

Preferred on Windows:

```powershell
./verify.ps1
```

Git Bash / Linux:

```bash
./verify.sh
```

The verifier must pass before handoff. It checks Lua structure, required functions, TOC load order, duplicate NPC IDs, section/data consistency, and Lua 5.1 syntax when `luac` is available.

## Release Packaging

`.github/workflows/package.yml` builds the correctly named addon zip from Git archives. Dev-only files are excluded through `.gitattributes`; keep `AGENTS.md` and verification wrappers out of release zips.

## AI Usage

Any AI may work here if it follows this file. Do not depend on Claude-specific or ChatGPT-specific behavior. Prefer explicit tasks, local verification, and concise diffs.
