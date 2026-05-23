-- L3FTools - Auchenai Crypts
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Auchenai Crypts",
    location = "Auchindoun - Auchenai Crypts",
    npcs = {
        { id = 18371, name = "Shirrak the Dead Watcher", kind = "boss", marks = {8},
          level = 72, type = "Aberration",
          spells = { 32264, 32265, 41092 },
          notes = "Aura Inhibit Magic stacks up to 4x (+200% cast time). Healers stay at max range. Run from Focus Fire flares immediately. Use instant/channeled spells.",
          drops = {
              { id = 29434, difficulty = "heroic" },
              { id = 30587, difficulty = "heroic" },
              { id = 30588, difficulty = "heroic" },
              { id = 30586, difficulty = "heroic" },
              { id = 27866, difficulty = "heroic" },
              { id = 27493, difficulty = "heroic" },
              { id = 27865, difficulty = "heroic" },
              { id = 27845, difficulty = "heroic" },
              { id = 27847, difficulty = "heroic" },
              { id = 27846, difficulty = "heroic" },} },
        { id = 18373, name = "Exarch Maladaar", kind = "boss", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 36778, 32424, 32422, 32421 },
          notes = "Soul Steal creates a non-elite clone of a random player every ~30s - DPS them down (often go for healer). At 25% summons Avatar of the Martyred. AoE Soul Scream fear.",
          drops = {
              { id = 29434, difficulty = "heroic" },
              { id = 29354, difficulty = "heroic" },
              { id = 29257, difficulty = "heroic" },
              { id = 29244, difficulty = "heroic" },
              { id = 27867, difficulty = "heroic" },
              { id = 27871, difficulty = "heroic" },
              { id = 27869, difficulty = "heroic" },
              { id = 27523, difficulty = "heroic" },
              { id = 27872, difficulty = "heroic" },
              { id = 21525, difficulty = "heroic" },
              { id = 33836, difficulty = "heroic" },
              { id = 30587, difficulty = "heroic" },
              { id = 30588, difficulty = "heroic" },
              { id = 30586, difficulty = "heroic" },
              { id = 27870, difficulty = "heroic" },} },
    },
})
