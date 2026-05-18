-- L3FTools - Mana-Tombs
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Mana-Tombs",
    location = "Auchindoun - Mana-Tombs",
    npcs = {
        { id = 18341, name = "Pandemonius", marks = {8},
          level = 72, type = "Voidwalker",
          spells = { 32325, 32358 },
          notes = "Pure shadow damage. Stop ALL attacks during Dark Shell (reflects spells, deals heavy damage to melee). Tank near a pillar to mitigate Void Blast knockback.",
          drops = {} },
        { id = 18343, name = "Tavarok", marks = {8},
          level = 72, type = "Giant",
          spells = { 33919, 32361, 38761 },
          notes = "Tank and spank with crystal-puzzle. Healer + ranged stay outside 35yd Earthquake AoE. Heal Crystal Prison target. Heroic adds Arcing Smash frontal cone.",
          drops = {} },
        { id = 18344, name = "Nexus-Prince Shaffar", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 20420, 32365, 32370, 33546 },
          notes = "Mage-style boss with 3 starting Ethereal Beacons (non-elite). Kill beacons FAST or they spawn Apprentice adds. Boss blinks + frost-novas.",
          drops = {} },
        { id = 22930, name = "Yor", marks = {8},
          level = 72, type = "Demon",
          spells = {},
          notes = "Heroic-only summoned boss (requires Eye of Haramad). Tank-and-spank. Face away from group for fire breath; watch AoE stomp.",
          drops = {} },
    },
})
