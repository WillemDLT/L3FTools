-- Automarker L3F - Magtheridon's Lair (with spell IDs and notes)
local _, L3F = ...

local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Magtheridon's Lair",
    sections = {
        {
            name = "Boss & Channelers",
            npcs = {
                { id = 17257, name = "Magtheridon",         kind = "boss", marks = {8},
                  spells = { 30571, 30616, 30619, 42869 },
                  notes = "Phase 1 is killing the 5 Hellfire Channelers spread around the room. Mag unbanishes after 2 minutes and Blast Nova will wipe the raid unless all 5 Manticron Cubes are clicked simultaneously every ~60 seconds. At 30% he Cave-Ins the ceiling - spread out and move out of the falling debris circles or instant death." },
                { id = 17256, name = "Hellfire Channeler",  kind = "boss", marks = {8, 7, 6, 5, 4},
                  spells = { 39175, 30528, 30531 },
                  notes = "Five of them, each tank-and-spank with Shadow Bolt Volley interrupts and Dark Mending kicks (Curse of Tongues / Mind-Numbing slow the casts). Every kill stacks Soul Transfer (+30% damage and cast speed) on survivors, so save best gear for the last two. Warlocks/mages control the Burning Abyssals they summon." },
            },
        },
        {
            name = "Trash & Summons",
            npcs = {
                { id = 18829, name = "Hellfire Warder",   kind = "trash", marks = TRASH,
                  spells = { 39175, 34441, 39176 },
                  notes = "Pre-Magtheridon trash, comes in linked packs of 3 (4 packs total, all must be cleared before pulling Mag). Casts Shadow Bolt Volley (~2k shadow AoE, 45yd, interruptable), Rain of Fire (instant, uninterruptible - move out!), Shadow Word: Pain and Unstable Affliction (do NOT dispel UA, it deals 3k + silences). Immune to all CC and Silence; only Curse of Tongues and Mind-Numbing Poison stick. Can land crushing blows on level 70 tanks, so misdirect-pull, spread for Rain of Fire, and burn one at a time." },
                { id = 17454, name = "Burning Abyssal",   kind = "boss", marks = TRASH,
                  spells = {},
                  notes = "Summoned by Hellfire Channelers during the boss fight (not real trash). Small infernal-style adds that leave a small fire pool on death; can be banished, feared, or kited. Assign warlocks/mages to lock them down so they don't reach the cube clickers. Cap of 5 simultaneous; despawn after ~1 minute. Per Icy-Veins / warcrafttavern, Burning Abyssal does cast a ranged Fire Blast (~3000 dmg / 20yd) but the exact TBC spell ID could not be pinned via Wowhead." },
            },
        },
    },
})
