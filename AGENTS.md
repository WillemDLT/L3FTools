# L3FTools — Agent Instructions

> Codex reads this file automatically at session start. Claude reads `CLAUDE.md`, which has more depth — the conventions below are mirrored there so both AIs share the same rules. If `CLAUDE.md` and this file ever drift, treat `CLAUDE.md` as the longer reference and this file as the canonical short summary for Codex.

## What L3FTools is

Multi-tool successor to AutomarkerL3F for WoW TBC Classic (Interface 20505). Bundles the Automarker plus an Atlas/encyclopedia of NPCs, drops, heroic dungeons. Lua addon, Bundled via the GitHub Actions `package.yml` workflow into a `beta` (tracks `dev`) and `live` (tracks `main`) release asset.

See `CLAUDE.md` for the full file layout, schemas, and project status. The essentials Codex needs:

- `Core.lua`, `Engine.lua`, `Sections.lua` — bootstrap + automarker engine
- `Sections/<Raid>.lua` — per-raid spatial wing data
- `Data/<Raid>.lua`, `Data/Drops/<Raid>.lua`, `Data/Heroics/`, `Data/Consumables/`, `Data/Factions.lua`, `Data/Collections.lua`, `Data/Professions*.lua` — Atlas data
- `Tabs/*.lua` — per-tab UI
- `L3FTools.toc` — load order. New `.lua` files must be added or they won't load
- `verify.sh` — pre-commit checker (must pass before any commit)

## Who works on this repo

- **Willem** (Anthropic Claude). Branch prefix: `willem/<short-description>`.
- **Kerweek** (OpenAI Codex). Branch prefix: `kerweek/<short-description>`.
- **Morphéours** (a.k.a. Kerweek above) is the sole in-game beta tester. He pulls the `beta` release asset, verifies, reports back.

## Git workflow — feature branches, never direct push to dev

Both Willem+Claude and Kerweek+Codex push to this repo. To avoid overwriting each other, all non-trivial work goes through feature branches off `dev`, with PRs to merge back. Direct push to `dev` only for the rare trivial single-line tweak where collision risk is zero.

**Standard flow per change:**

```bash
# 1. Sync dev first
git checkout dev
git pull origin dev

# 2. Branch off dev with your owner prefix
git checkout -b kerweek/<short-description>   # for Codex
# (Willem's Claude uses willem/<short-description>)

# 3. Do the work (multiple commits OK)
# Run bash verify.sh — must pass before any commit

# 4. Push the branch
git push -u origin kerweek/<short-description>

# 5. Open a PR against dev
gh pr create --base dev --title "..." --body "..."

# 6. Merge via PR (squash-merge for clean history)
gh pr merge --squash --delete-branch

# 7. Sync local dev
git checkout dev && git pull origin dev
```

**If push fails because dev moved:**
```bash
git fetch origin
git rebase origin/dev
# resolve conflicts if any
git push --force-with-lease
```

**If a PR shows merge conflicts on GitHub:** pull `dev` into your feature branch, resolve locally, push.

## Branch model

- `main` = stable; `dev` = WIP (both AIs land work here via PR).
- Squash `dev` → `main` only after Morphéours verifies in-game.
- `.github/workflows/package.yml` repackages a release zip on every push — `beta` asset tracks `dev`, `live` asset tracks `main`.
- Morphéours installs from `github.com/WillemDLT/L3FTools/releases/download/beta/L3FTools.zip` — **never** the raw archive zip (wrapper folder name won't match the `.toc`).

## Critical conventions

- **Run `bash verify.sh` after every edit pass** — checks brace/paren balance, NULL bytes, suspicious last line, Lua block balance, key-function presence, TOC load order, duplicate NPC id/name, Sections-vs-Data cross-check, and `luac5.1 -p` syntax. Must report 0 file failures.
- **Symmetric editing with AutomarkerL3F** — raid `Data/<Raid>.lua`, `Sections/`, and the Automarker / wing engine mirror between the two addons. Any change to a raid's NPC registry, mark assignments, wing layout, or engine behavior must land in both projects.
- **`L3FTools.toc` load order matters** — new `.lua` files must be added there or they won't load. `verify.sh` catches this.
- **Long-write protocol** — Edit/Write tools can silently truncate files >3KB on Windows mounts. For large rewrites use bash heredoc. Run `verify.sh` after every edit pass.
- **`.toc` Interface number is 20505** (TBC Classic / Anniversary). Don't change without coordination.

## Tools & ops

- **`gh` CLI** for GitHub ops. On Willem's machine it's at `C:\Program Files\GitHub CLI\gh.exe` (not on Bash PATH there). On Kerweek's machine, use wherever his `gh` lives.
- **Author info:** Willem (`willem-YT@hotmail.com`, GitHub `WillemDLT`). Kerweek is a collaborator with push access.
- **No GitHub MCP** — use the `gh` CLI directly.
