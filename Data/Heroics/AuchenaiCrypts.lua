-- L3FTools - Auchenai Crypts
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Auchenai Crypts",
    location = "Auchindoun - Auchenai Crypts",
    npcs = {
        { id = 18371, name = "Shirrak the Dead Watcher", marks = {8},
          level = 72, type = "Aberration",
          spells = { 32264, 32265, 41092 },
          notes = "Aura Inhibit Magic stacks up to 4x (+200% cast time). Healers stay at max range. Run from Focus Fire flares immediately. Use instant/channeled spells.",
          drops = {} },
        { id = 18373, name = "Exarch Maladaar", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 36778, 32424, 32422, 32421 },
          notes = "Soul Steal creates a non-elite clone of a random player every ~30s - DPS them down (often go for healer). At 25% summons Avatar of the Martyred. AoE Soul Scream fear.",
          drops = {} },
    },
})
