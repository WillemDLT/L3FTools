-- L3FTools - Magisters' Terrace
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Magisters' Terrace",
    location = "Isle of Quel'Danas - Magisters' Terrace",
    npcs = {
        { id = 24723, name = "Selin Fireheart", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 44215, 44214, 44219 },
          notes = "Drains Fel Crystals around the room for huge Fel Explosion AoE. Tank pulls boss off the crystal he runs to; DPS smashes the crystal before he finishes draining. Crystals stun on death.",
          drops = {
              { id = 34339, name = "Crown of Anasterian", chance = 18.5 },
              { id = 34342, name = "Belt of Gale Force", chance = 17.9 },
              { id = 34343, name = "Greaves of the Penitent Knight", chance = 17.7 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 24744, name = "Vexallus", marks = {8},
          level = 70, type = "Elemental",
          spells = { 44321, 44319 },
          notes = "Pure DPS race - Energy Feedback ticks raid-wide and stacks. At 20% spawns Pure Energy adds that fixate; mage Nova them and burn. Healer must drink between trash and pull.",
          drops = {
              { id = 34345, name = "Cord of Reconstruction", chance = 19.0 },
              { id = 34348, name = "Vanir's Right Fist of Brutality", chance = 18.3 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 24560, name = "Priestess Delrissa", marks = {8},
          level = 70, type = "Humanoid",
          spells = {},
          notes = "Five-person PvP fight - Delrissa plus 4 random adds from a class pool. Crowd-control the dangerous ones (priest, mage), burn healer first.",
          drops = {
              { id = 34351, name = "Wrist Wraps of Quickening", chance = 19.0 },
              { id = 34352, name = "Quickening Belt", chance = 18.7 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 24664, name = "Kael'thas Sunstrider", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 44191, 44239, 44190, 44869 },
          notes = "Phase 1: dodge Pyroblast (line up behind tank), kill Phoenix adds quickly + destroy their Eggs. Phase 2: Gravity Lapse lifts everyone - kill Arcane Spheres mid-air before landing.",
          drops = {
              { id = 34601, name = "Cowl of Gul'dan", chance = 11.5 },
              { id = 34605, name = "Phaseshifter Bracers", chance = 10.5 },
              { id = 35280, name = "Phoenix Hatchling", chance = 2.0 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
    },
})
