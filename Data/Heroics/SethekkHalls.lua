-- L3FTools - Sethekk Halls
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Sethekk Halls",
    location = "Auchindoun - Sethekk Halls",
    npcs = {
        { id = 18472, name = "Darkweaver Syth", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 37865, 34354, 30138, 39945 },
          notes = "Summons 4 elementals (fire/frost/shadow/arcane) at 90/55/10% HP. Kill or fear adds; each elemental is immune to its own school. Tank uses Spell Reflect on Chain Lightning.",
          drops = {} },
        { id = 18473, name = "Talon King Ikiss", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 38245, 35950, 33256, 38197 },
          notes = "Blinks to a random player then channels Arcane Explosion (~6k+ AoE) - hide behind pillars/doorway. Polymorphs DPS. Mage can Spellsteal Mana Shield.",
          drops = {} },
        { id = 23035, name = "Anzu", marks = {8},
          level = 72, type = "Beast",
          spells = { 40327, 40321, 40251 },
          notes = "Heroic druid-summoned boss (epic flight form quest). Summons bird waves at 75% and 35% - AoE them. Three Spirits of the Brood around room - Rank 1 Rejuv on each for buffs.",
          drops = {} },
    },
})
