-- =============================================================
-- L3FTools - Tabs/Guild.lua
-- =============================================================
-- "Guild" is the parent of the brick-wall sub-tab row. Clicking it
-- in row 1 routes to its last-active sub-tab (or the first one).
-- The Guild parent itself has no own content frame - a sub-tab is
-- always what actually renders.
--
-- Sub-tabs (in registration order, left to right in row 2):
--   Tabs/Guild/Composer.lua    - Raid composer (wowtbc.gg-style)
--   Tabs/Guild/Crafts.lua      - Guild recipe registry (GuildCrafts-style)
--   Tabs/Guild/RaidPlanner.lua - In-raid strategy plans (raidplan.io-style)
--   Tabs/Guild/Planner.lua     - Free-form planner (Morpheours scoping)
-- =============================================================

local addonName, L3F = ...

L3F.RegisterTab("guild", "Guild", nil, nil)
