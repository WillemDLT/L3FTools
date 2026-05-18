-- L3FTools - Old Hillsbrad Foothills
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Old Hillsbrad Foothills",
    location = "Caverns of Time - Old Hillsbrad",
    npcs = {
        { id = 17848, name = "Lieutenant Drake", marks = {8},
          level = 71, type = "Humanoid",
          spells = { 16508, 31408, 31909, 31910 },
          notes = "First boss. Mortal Strike reduces healing 50%. Intimidating Shout fear breaks CC on adds. Tank with back to a wall.",
          drops = {} },
        { id = 17862, name = "Captain Skarloc", marks = {8},
          level = 71, type = "Humanoid",
          spells = {},
          notes = "Second boss - escort phase ends. Interrupts Holy Light heals on himself. Comes with 2 Sergeants - kill adds first.",
          drops = {} },
        { id = 18096, name = "Epoch Hunter", marks = {8},
          level = 72, type = "Dragonkin",
          spells = { 33706, 33707, 38530 },
          notes = "Final boss. Sand Breath frontal cone - tank sideways. Knockdown stuns tank 3s. Three phases (humanoid -> draconic).",
          drops = {} },
    },
})
