-- L3FTools - The Botanica
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Botanica",
    location = "Tempest Keep - The Botanica",
    npcs = {
        { id = 17976, name = "Commander Sarannis", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 34971, 34972, 34974 },
          notes = "Arcane Resonance debuff - SPREAD when target. Summons 3 Bloodwarder adds at 50% HP. Burn before adds overwhelm.",
          drops = {} },
        { id = 17975, name = "High Botanist Freywinn", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 34906, 34896, 34903 },
          notes = "Tree form at 75/50/25% - heals self with Tranquility (INTERRUPT). Color seedlings explode (move away from your color). Summons Frayer Protector adds.",
          drops = {} },
        { id = 17978, name = "Thorngrin the Tender", marks = {8},
          level = 72, type = "Demon",
          spells = { 34924, 34926, 34927 },
          notes = "Hellfire AoE periodically (raid damage). Sacrifice stuns + drains a target. Enrages periodically for increased damage.",
          drops = {} },
        { id = 17980, name = "Laj", marks = {8},
          level = 72, type = "Elemental",
          spells = { 34698, 34697, 34701 },
          notes = "Changes elemental school every ~10s - swap DPS spec or stop casting that school. Teleports to platform center; summons Lasher adds.",
          drops = {} },
        { id = 17977, name = "Warp Splinter", marks = {8},
          level = 73, type = "Elemental",
          spells = { 34835, 34803, 34780 },
          notes = "Spawns 6 Saplings every 30s - they run to him to give a damage buff stack. AoE them down FAST. Stomp AoE knockback.",
          drops = {} },
    },
})
