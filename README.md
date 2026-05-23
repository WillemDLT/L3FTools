# L3FTools

Multi-tool suite for TBC Classic (TBC Anniversary): a preset-based Automarker, an Atlas / encyclopedia of raid and heroic-dungeon NPCs with their drops and tactics, and more. Open it with the minimap button or `/l3f`.

## Install

**Download from the [Releases page](https://github.com/WillemDLT/L3FTools/releases)** - open the latest release and grab the **`L3FTools.zip`** asset, then extract it into:

`World of Warcraft\_classic_\Interface\AddOns\`

That zip already contains a correctly-named `L3FTools` folder, so extracting it there is all you need. Restart WoW or `/reload` afterwards.

> **Important - do not use the green "Code -> Download ZIP" button**, and do not use the "Source code (zip)" links on the Releases page. GitHub wraps those downloads in a folder named `L3FTools-main` (or `-dev`), which does **not** match the addon's `.toc` file - so WoW silently ignores the addon, with no error message. If you already did this, just rename the extracted folder to exactly `L3FTools` (remove the `-main` / `-dev` suffix).

## Usage

- The **minimap button** or **`/l3f`** opens the main window.
- `/l3f automarker`, `/l3f atlas`, `/l3f settings` open a specific tab.
- `/l3f toggle` flips the Automarker on or off; `/l3f switcher` shows/hides the wing switcher; `/l3f minimap` hides/shows the minimap button; `/l3f help` lists every command.
