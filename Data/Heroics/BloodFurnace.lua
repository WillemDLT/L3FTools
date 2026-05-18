-- L3FTools - The Blood Furnace
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Blood Furnace",
    location = "Hellfire Citadel - The Blood Furnace",
    npcs = {
        { id = 17381, name = "The Maker", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30923, 30883, 33489 },
          notes = "Casts Acid Spray (frontal cone - face away from group) and Domination (Mind Control on a random player - dispel fast). Tank turns The Maker away on each cast.",
          drops = {
              { id = 27486, name = "Cobra-Lash Boots", chance = 18.6 },
              { id = 27487, name = "Trousers of the Scryers' Retainer", chance = 18.4 },
              { id = 27488, name = "Dreghood Elder's Mantle", chance = 18.2 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 17380, name = "Broggok", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30914, 30880, 30752 },
          notes = "Pre-event: four cages of orcs/felhounds - clear in order, then engage Broggok. He drops Poison Cloud puddles continuously - keep moving. Slimes from puddles need stunning/snaring.",
          drops = {
              { id = 27492, name = "Forestlord Striders", chance = 18.7 },
              { id = 27493, name = "Slaghide Gauntlets", chance = 18.5 },
              { id = 27494, name = "Idol of Ursoc", chance = 18.3 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 17377, name = "Keli'dan the Breaker", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30843, 30970, 30971, 30769 },
          notes = "Pre-event: kill the 5 Shadowmoon Channelers first. Boss casts Burning Nova (instant AoE - run to max range when you see the cast). Interrupt Fire Nova channel on sight.",
          drops = {
              { id = 27497, name = "Beast Lord Handguards", chance = 18.8 },
              { id = 27498, name = "Beast Lord Helm", chance = 18.6 },
              { id = 27499, name = "Beast Lord Cuirass", chance = 18.4 },
              { id = 27500, name = "Beast Lord Mantle", chance = 18.2 },
              { id = 27501, name = "Beast Lord Leggings", chance = 18.0 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
    },
})
