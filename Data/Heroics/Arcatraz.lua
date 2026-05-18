-- L3FTools - The Arcatraz
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Arcatraz",
    location = "Tempest Keep - The Arcatraz",
    npcs = {
        { id = 20870, name = "Zereketh the Unbound", marks = {8},
          level = 72, type = "Demon",
          spells = { 36383, 36382, 36380 },
          notes = "Void Zones on the ground - MOVE OUT (heavy shadow DoT). Seed of Corruption on a random target spreads to nearby allies - spread. Shadow Nova knockback.",
          drops = {} },
        { id = 20885, name = "Dalliah the Doomsayer", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 36408, 36405, 36407 },
          notes = "Whirlwind every ~25s - melee BACK OFF. Heals herself after Whirlwind - INTERRUPT. Shadow Wave hits whole party.",
          drops = {} },
        { id = 20886, name = "Wrath-Scryer Soccothrates", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 36402, 36401, 36400, 36399 },
          notes = "Knocks tank back, then Charges across in a line - DON'T STAND IN THE PATH. Felfire Line damages everything in its path.",
          drops = {} },
        { id = 20912, name = "Harbinger Skyriss", marks = {8},
          level = 73, type = "Demon",
          spells = { 36924, 36927, 36930, 36931 },
          notes = "Splits into Mirror Images at 66% and 33% (each half HP). Mind Control on a random player - CC. Preceded by Warden Mellichar escort waves (Millhouse Manastorm).",
          drops = {} },
    },
})
