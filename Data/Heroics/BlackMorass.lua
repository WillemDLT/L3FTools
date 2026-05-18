-- L3FTools - The Black Morass
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Black Morass",
    location = "Caverns of Time - The Black Morass",
    npcs = {
        { id = 17879, name = "Chrono Lord Deja", marks = {8},
          level = 72, type = "Elemental",
          spells = { 31898, 31897, 31901 },
          notes = "First boss (after portal 6). Time Lapse halves player HP. Attraction pulls party in. Arcane Blast knockback - tank near a wall.",
          drops = {} },
        { id = 17880, name = "Temporus", marks = {8},
          level = 72, type = "Dragonkin",
          spells = { 31893, 31872, 31874 },
          notes = "Second boss (after portal 12). Hasten increases attack speed - tank cooldowns. Wing Buffet knockback in frontal arc; face him away.",
          drops = {} },
        { id = 17881, name = "Aeonus", marks = {8},
          level = 73, type = "Dragonkin",
          spells = { 31889, 31891, 31886 },
          notes = "Final boss (after portal 18). Time Stop AoE stun 3s. Sand Breath frontal cone. Enrages at 30% - burn through it.",
          drops = {} },
    },
})
