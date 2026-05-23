-- Automarker L3F - Tempest Keep: The Eye (with spell IDs and notes)
local _, L3F = ...

local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Tempest Keep",
    sections = {
        {
            name = "Bosses",
            npcs = {
                { id = 19514, name = "Al'ar",                     kind = "boss", marks = {8},
                  spells = { 34121, 34229, 35383, 35367, 34341 },
                  notes = "Two phases (both start at 100%); immune to fire. P1: rotates clockwise around 4 upper platforms every 30s - 3-4 tanks ready to grab him so Flame Buffet doesn't stack-nuke the raid. Jump off platforms during Flame Quills; phoenix adds explode (Ember Blast) on death. P2: tauntable on the floor - 2-tank rotation for Melt Armor, dodge Flame Patches, intercept Dive Bomb spots which spawn 2 phoenixes." },
                { id = 19516, name = "Void Reaver",               kind = "boss", marks = {8},
                  spells = { 34162, 34190, 25778 },
                  notes = "'Loot Reaver' - pure DPS race with a 10-minute enrage. Ranged spread in a wide circle to dodge Arcane Orbs (6k splash + 6s silence). Melee run out of Pounding (channeled point-blank AoE every 12s) or wear arcane resist. Knock Away on the MT drops threat - run a 3-4 tank rotation. Immune to poisons/drains." },
                { id = 18805, name = "High Astromancer Solarian", kind = "boss", marks = {8},
                  spells = { 39414, 42783, 33009, 39329 },
                  notes = "Stack the raid tight in P1 so when she Wrath of the Astromancer-bombs someone, that player can sprint clear before the explosion launches anyone within 10 yards into the air for fatal fall damage. Every 50s she vanishes and spawns 12-15 Solarium Agents through 3 portals, then returns with 2 Solarium Priests that must be silenced/stunlocked. At 20% she transforms into a giant void walker - tank-and-spank to finish." },
                { id = 19622, name = "Kael'thas Sunstrider",      kind = "boss", marks = {8},
                  spells = { 36805, 36819, 36815, 36797, 35966 },
                  notes = "Five-phase epic. P1-2 kill his 4 advisors one by one, then the 7 legendary weapons (loot and equip them). P3 revives all advisors. P4 starts the real Kael fight: interruptible Fireballs, uninterruptible Pyroblasts behind Shock Barrier (use the Phaseshift Bulwark on first), Phoenix/Egg adds, Flamestrike patches, Arcane Disruption, MC pairs (cleanse with Infinity Blade). P5 (50%): Gravity Lapse flies everyone, dodge Nether Vapor clouds and chain-jumping Netherbeams." },
            },
        },
        {
            name = "Kael'thas Advisors",
            npcs = {
                { id = 20064, name = "Thaladred the Darkener",      kind = "boss", marks = {8},
                  spells = { 36965, 36966 },
                  notes = "Untankable - has no aggro table, instead 'fixes his gaze' on a random raider every ~9s who must kite him while ranged DPS nukes from max distance. Psychic Blow knocks back the gaze target for 4-5k. Silence hits anyone within 8 yards, so casters never let him close." },
                { id = 20060, name = "Lord Sanguinar",              kind = "boss", marks = {7},
                  spells = { 39427 },
                  notes = "Simple tank-and-spank whose only real mechanic is Bellowing Roar - a 30-35 yard AoE fear that doesn't drop threat. Use Berserker Rage / Tremor Totem / Fear Ward and position him near a wall so feared raiders don't run far. Kill him in a corner since he resurrects at his death spot in Phase 3." },
                { id = 20062, name = "Grand Astromancer Capernian", kind = "boss", marks = {6},
                  spells = { 36971, 37018, 36970 },
                  notes = "Warlock-tanked at range - Arcane Burst PBAoE-knocks back and slows anyone in melee, so no melee touches her. Conflagration randomly DoT/disorients a target within 30 yards (also resets aggro on the warlock if it hits), so the tank stays at long range and the raid spreads. Warlock must avoid Nether Protection talent." },
                { id = 20063, name = "Master Engineer Telonicus",   kind = "boss", marks = {5},
                  spells = { 37036, 37027 },
                  notes = "Two key tools: Bomb (4-yard fire splash on the target - raid stays spread, MT pulls him away) and Remote Toy (1-min debuff that periodically stuns the target for 4 seconds). The Staff of Disintegration's Mental Protection Field on-use nullifies Remote Toy stuns for healers/tanks. Tank him against a wall opposite Sanguinar." },
            },
        },
        {
            name = "Kael'thas Weapons (phase 2)",
            npcs = {
                { id = 21272, name = "Warp Slicer",        kind = "boss", marks = {8},
                  spells = { 36991 },
                  notes = "Phase 2 Kael'thas summoned 1H sword tanked by a melee DPS. Applies Rend (36991) - stacking physical bleed - swap aggro if stacks pile high. Despawns 60s after death - loot fast; on-use makes attacks dual-strike." },
                { id = 21271, name = "Infinity Blades",    kind = "boss", marks = {7},
                  spells = { 674 },
                  notes = "Phase 2 twin daggers. Hits hard with Dual Wield melee. The looted Infinity Blade is THE most important weapon: equipping it lets any melee attack dispel Kael'thas's Phase 4 Mind Control on raiders." },
                { id = 21273, name = "Phaseshift Bulwark", kind = "boss", marks = {6},
                  spells = { 36988 },
                  notes = "Phase 2 shield. Casts a Shield Bash that reflects damage on melee attackers - rogues/cats avoid spamming. Looted version has the 100k-absorb on-use the MT pops to eat Kael's first Phase 4 Pyroblast." },
                { id = 21268, name = "Netherstrand Longbow", kind = "boss", marks = {5},
                  spells = { 2643 },
                  notes = "Phase 2 bow - KILL FIRST. Hunter-tank only: Multi-Shot hits 3 nearby targets and it drops aggro the instant any melee/pet touches it. Hunter faces away from raid; ranged-only DPS." },
                { id = 21269, name = "Devastation",          kind = "boss", marks = {4},
                  spells = { 36982 },
                  notes = "Phase 2 Kael'thas animated axe. Channels Whirlwind (36982) - 150% weapon damage in an 8yd AoE, heavy on cloth. Tank it well away from the raid and burn it down." },
                { id = 21274, name = "Staff of Disintegration", kind = "boss", marks = {3},
                  spells = { 36989, 36990 },
                  notes = "Phase 2 animated staff. Ranged Frostbolt (36990, frost damage + heavy slow) and Frost Nova (36989). Stays at range nuking - assign someone to close on it and melee it down." },
                { id = 21270, name = "Cosmic Infuser",       kind = "boss", marks = {2},
                  spells = { 36983, 36985 },
                  notes = "Phase 2 animated mace. Casts Heal (36983) on the other weapons plus Holy Nova (36985) - KILL or lock it down FIRST; its heal must be interrupted." },
            },
        },
        {
            name = "Solarian / Astromancer Trash",
            npcs = {
                { id = 18806, name = "Solarium Priest",        kind = "boss", marks = TRASH,
                  spells = { 25054, 33387 },
                  notes = "Spawns in pairs with Solarian after her vanish phase. HIGHEST priority kill/stunlock/silence - Great Heal (33387) fully tops her off. Holy Smite (25054) is a slow castable nuke that's easy to interrupt; focus the heal." },
                { id = 20034, name = "Star Scryer",            kind = "trash", marks = TRASH,
                  spells = { 37124 },
                  notes = "Sheepable caster patrol in Solarian's hall. Casts Starfall (37124) - instant arcane AoE around the caster ~2k/tick. CC on pull and burn down before melee can stack near it." },
                { id = 20043, name = "Apprentice Star Scryer", kind = "trash", marks = TRASH,
                  spells = { 37129, 37132, 37133, 38725 },
                  notes = "Caster in mixed packs with Novice Astromancers. Arcane Volley (37129) channels heavy arcane at range; stacks Arcane Buffet (37133, +arcane taken per stack) and finishes with Arcane Explosion (38725) PBAoE; also Arcane Shock (37132). Keep melee out; sheep on pull." },
                { id = 20044, name = "Novice Astromancer",     kind = "trash", marks = TRASH,
                  spells = { 37111, 37279, 37282, 38728 },
                  notes = "Fire caster in Solarian-hall packs. Rain of Fire (37279) is the biggest threat (ground AoE fire/tick) plus Fire Nova (38728) PBAoE; permanent Fire Shield (37282) burns melee. Range tank and interrupt Fireball (37111)." },
                { id = 20033, name = "Astromancer",            kind = "trash", marks = TRASH,
                  spells = { 35915, 37109, 37110 },
                  notes = "Caster in Phoenix Hall corridor. Fireball Volley (37109) is the major raid threat (~2-3k fire AoE multi-target) plus instant Fire Blast (37110); self-buffs Molten Armor (35915). Sheepable - CC on pull and interrupt Volley." },
                { id = 20046, name = "Astromancer Lord",       kind = "trash", marks = TRASH,
                  spells = { 37109, 37110, 37289, 38732 },
                  notes = "Mini-boss caster patrolling alone. Dragon's Breath (37289) cone is the dangerous mechanic - fire damage + disorient in front, so tank facing away. Fireball Volley (37109), Fire Blast (37110), unstealable Fire Shield (38732) in the mix." },
                { id = 20045, name = "Nether Scryer",          kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Caster in Crimson Hand packs - retail has reworked all its abilities so no verified TBC spell IDs on Wowhead. Original TBC version cast Mass Mind Control (mass-dispel ready) and a knockback Arcane Blast; immune to all CC so kill last but interrupt MC. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
                { id = 18925, name = "Solarium Agent",         kind = "boss", marks = TRASH,
                  spells = {},
                  notes = "Spawned in waves through Solarian's portals during her vanish phase. High melee damage, no notable casts - a tank gathers them so the raid can AoE them down fast." },
            },
        },
        {
            name = "Bloodwarder Trash",
            npcs = {
                { id = 20036, name = "Bloodwarder Squire",      kind = "trash", marks = TRASH,
                  spells = { 39077 },
                  notes = "Paladin-style trash that opens with Hammer of Justice (39077, 3s stun on the MT, DR applies) and spam-casts Dispel Magic on raid debuffs/CCs - tunnel them down first or keep silenced/swap on stun." },
                { id = 20032, name = "Bloodwarder Vindicator",  kind = "trash", marks = TRASH,
                  spells = { 853 },
                  notes = "Paladin trash. Hammer of Justice on the MT (3s stun, DR applies), Cleanse (removes magic CC on friends), hard-hitting Flash of Light heal. Kick heals; swap on stun." },
                { id = 19633, name = "Bloodwarder Mender",      kind = "trash", marks = TRASH,
                  spells = { 34809 },
                  notes = "Dedicated Bloodwarder healer - TOP kill priority. Holy Fury (34809) buffs an ally's spell power by 295; the dangerous mechanic is the long-range Greater Heal cast that must be kicked on cooldown." },
                { id = 20035, name = "Bloodwarder Marshal",     kind = "trash", marks = TRASH,
                  spells = { 15589, 34996, 35948, 36132 },
                  notes = "Roaming named patrol with RP yell - warrior elite that spins Whirlwind (36132) PBAoE physical, Uppercut-stuns (34996) the tank, and self-heals through Bloodthirst (35948). Sap or pull controlled." },
                { id = 20031, name = "Bloodwarder Legionnaire", kind = "trash", marks = TRASH,
                  spells = { 15284, 15578, 33500, 35948 },
                  notes = "Warrior trash that Whirlwinds (33500) PBAoE physical, Cleaves (15284) the front cone, and Bloodthirst (35948) self-heals. Tank facing away from raid, run out on Whirlwind." },
            },
        },
        {
            name = "Crimson Hand Trash",
            npcs = {
                { id = 20048, name = "Crimson Hand Centurion",   kind = "trash", marks = TRASH,
                  spells = { 37268, 37271 },
                  notes = "Melee elite. Channels Arcane Flurry (37268) - 10s whirl hitting ~4k arcane to everyone in melee. Vulnerable to Polymorph/Incapacitate/Disorient - sheep, gouge, or run melee out the instant the channel starts." },
                { id = 20049, name = "Crimson Hand Blood Knight", kind = "trash", marks = TRASH,
                  spells = { 39077 },
                  notes = "Paladin trash that opens with Hammer of Justice (39077, 3s stun, DR applies). Heals allies and isn't immune to Cyclone in TBC Classic - druid CC works. Interrupt heals and swap on stun." },
                { id = 20050, name = "Crimson Hand Inquisitor",  kind = "trash", marks = TRASH,
                  spells = { 37274, 37275, 37276 },
                  notes = "Shadow priest trash - sheepable, top CC priority. Mind Flay (37276) shadow DoT + slow channel and Shadow Word: Pain (37275) DoT eat through cloth/leather; Power Infusion (37274) buffs an ally's casting speed so kick the buff." },
                { id = 20047, name = "Crimson Hand Battle Mage", kind = "trash", marks = TRASH,
                  spells = { 37263 },
                  notes = "Frost mage trash that drops Blizzard (37263) - large ground AoE 2.4-2.6k frost/tick. Move out of the patch and sheep/banish-trade on pull." },
            },
        },
        {
            name = "Phoenix / Crystalcore / Other",
            npcs = {
                { id = 20037, name = "Tempest Falconer",       kind = "trash", marks = TRASH,
                  spells = { 36907, 37154 },
                  notes = "Hunter-style blood elf. Permanent unstealable Fire Shield on adds (~550 fire/tick on melee); shoots Immolation Arrow for weapon + 3.7-4.3k fire. Tank ranged; Purgers can't strip the shield." },
                { id = 20042, name = "Tempest-Smith",          kind = "trash", marks = TRASH,
                  spells = { 37118, 37120, 35337 },
                  notes = "Engineer caster in Void Reaver's room. Shell Shock (3-5k fire + 3s AoE stun in 10yd), Fragmentation Bomb (fire + armor shred), channels Spell Power to give a Crystalcore +50% damage. SHEEP/SAP/STUN on sight - if the buff completes the raid wipes." },
                { id = 20039, name = "Phoenix-Hawk",           kind = "trash", marks = TRASH,
                  spells = { 31475 },
                  notes = "Beast. Randomly charges the furthest player for up to ~10k damage + knocks back nearby raiders for ~2k. Wing Buffet cone knockback. Vulnerable to all CC including Hibernate/Scare Beast." },
                { id = 20038, name = "Phoenix-Hawk Hatchling", kind = "trash", marks = TRASH,
                  spells = { 31475 },
                  notes = "Smaller beast in packs. Wing Buffet (1s cast melee knockback), Immolation DoT, AoE silence (dispellable). Vulnerable to all CC including Hibernate/Scare Beast - hunter-kite or AoE." },
                { id = 21364, name = "Phoenix Egg",            kind = "boss", marks = TRASH,
                  spells = {},
                  notes = "No active abilities - spawns on Phoenix-Hawk death (and from Al'ar/Kael Phoenixes). Destroy within ~15s or it hatches a fresh Phoenix-Hawk. Tunnel immediately." },
                { id = 19551, name = "Ember of Al'ar",         kind = "boss", marks = TRASH,
                  spells = { 34133 },
                  notes = "Phoenix add during the Al'ar fight. Heavy melee, and explodes on death for big fire damage + knockback in 15yd - kill it spread out, away from melee, never stacked on the raid." },
                { id = 21362, name = "Phoenix",                kind = "boss", marks = TRASH,
                  spells = { 34341, 35369, 41587 },
                  notes = "Kael'thas phase 4 add. Pulses fire damage to nearby players; on death drops a Phoenix Egg that must be killed fast before it hatches a new Phoenix. Tank away from raid, AoE the egg." },
                { id = 20040, name = "Crystalcore Devastator", kind = "trash", marks = TRASH,
                  spells = { 35035, 37106 },
                  notes = "Big arcane construct, Void Reaver area. Countercharge (random-target counterspell locking school 10s, spell-reflectable) and Charged Arcane Explosion (3.7s cast, 5.5-6.5k arcane in 20yd - run out). Immune to all CC." },
                { id = 20041, name = "Crystalcore Sentinel",   kind = "trash", marks = TRASH,
                  spells = { 37104 },
                  notes = "Comes in pairs in Void Reaver area. Overcharge (37104, 1.5-2s cast, 14-15k arcane on MT, reflectable with Spell Reflection) plus Trample melee. Separate the two so casts dont overlap." },
                { id = 20052, name = "Crystalcore Mechanic",   kind = "trash", marks = TRASH,
                  spells = { 35318, 37121 },
                  notes = "BANISHABLE - the priority CC target. Saw Blade (35318) 2.5-2.9k physical + 3k bleed cone hits melee/tank; channels Recharge (37121) heals Devastators/Sentinels 10k/sec, uninterruptible, ignores LoS. Banish on pull." },
            },
        },
    },
})

-- Atlas Bosses-leaf tree (Morpheours-spec). "Legendaries Weapons" is
-- a virtual parent listing the 7 weapons Kael drops in P2 - rendered
-- as items, not NPCs. Item IDs cross-checked against AtlasLoot's
-- DungeonsAndRaids/data-tbc.lua so the canonical TBC IDs ship.
L3F:RegisterBossTree("The Eye: Tempest Keep", {
    { name = "Al'ar", npcID = 19514, subs = {
        { npcID = 19551 },  -- Ember of Al'ar
    } },
    { name = "Void Reaver", npcID = 19516, subs = {} },
    { name = "High Astromancer Solarian", npcID = 18805, subs = {
        { npcID = 18806 },  -- Solarium Priest
        { npcID = 18925 },  -- Solarium Agent
    } },
    { name = "Kael'thas Sunstrider", npcID = 19622, subs = {
        { npcID = 20064 },  -- Thaladred the Darkener
        { npcID = 20060 },  -- Lord Sanguinar
        { npcID = 20062 },  -- Grand Astromancer Capernian
        { npcID = 20063 },  -- Master Engineer Telonicus
        { npcID = 21362 },  -- Phoenix
        { npcID = 21364 },  -- Phoenix Egg
    } },
    { name = "Legendaries Weapons", virtual = true, itemIDs = {
        30312,  -- Infinity Blade
        30311,  -- Warp Slicer
        30317,  -- Cosmic Infuser
        30316,  -- Devastation
        30313,  -- Staff of Disintegration
        30314,  -- Phaseshift Bulwark
        30318,  -- Netherstrand Longbow
    } },
})
