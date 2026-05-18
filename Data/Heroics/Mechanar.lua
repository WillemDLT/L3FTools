-- L3FTools - The Mechanar
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Mechanar",
    location = "Tempest Keep - The Mechanar",
    npcs = {
        { id = 19219, name = "Mechano-Lord Capacitus", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 35158, 36169, 36158, 36161 },
          notes = "Polarity Shift assigns positive/negative charges - same-charge players stack together. Reflective shields - swap DPS type. Nether Charges explode at 0 HP.",
          drops = {} },
        { id = 19221, name = "Nethermancer Sepethrea", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 39511, 35181, 35149, 35147 },
          notes = "Summons 2 Ragin' Flames adds - kite, do not tank (Inferno DoT in melee). Dragon's Breath frontal cone. Solarium Reflections swap spell schools.",
          drops = {} },
        { id = 19220, name = "Pathaleon the Calculator", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 35139, 35138, 35160 },
          notes = "Mind Controls healer/DPS - CC the controlled player. Summons Nether Wraiths at 75/50/25%. Silence boss when possible. Heroic adds Frenzy at 20%.",
          drops = {} },
    },
})
