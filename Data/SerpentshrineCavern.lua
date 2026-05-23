-- Automarker L3F - Serpentshrine Cavern (with spell IDs and notes)
local _, L3F = ...

local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Serpentshrine Cavern",
    sections = {
        {
            name = "Bosses",
            npcs = {
                { id = 21216, name = "Hydross the Unstable",   kind = "boss", marks = {8},
                  spells = { 38215, 38219, 38235, 38246, 36461 },
                  notes = "Two-phase elemental: Frost-pure inside the water beams, Nature-tainted when dragged out, with Mark of Hydross/Mark of Corruption stacking every 15s on the tank. Switch phases at 3-4 stacks by moving him across the line; each transition spawns 4 Pure or Tainted Spawns that must be CC'd/AoE'd/off-tanked. Two MTs in frost-resist and nature-resist gear take turns; stop DoTs before transitions or warlocks pull aggro." },
                { id = 21217, name = "The Lurker Below",       kind = "boss", marks = {8},
                  spells = { 37433, 37478, 37138 },
                  notes = "Fish him from the Strange Pool. 60s rotation: Spout raid-wide jet (everyone jumps into surrounding water to avoid it), Whirl (melee knockback), Geyser on random ranged. Every 2 minutes he submerges and 9 adds spawn on the 3 outer platforms - kill or sheep them before he resurfaces. Keep someone in melee at all times to prevent Water Bolt." },
                { id = 21215, name = "Leotheras the Blind",    kind = "boss", marks = {8},
                  spells = { 37640, 37676, 37675 },
                  notes = "Alternates 60s Human form (Whirlwind aggro-resets and bleeds - spread out, pause DPS at transitions) with 60s Demon form (tanked by a fire-resist warlock soaking Chaos Blast). Demon phase: Insidious Whisper spawns Inner Demons that each target one player who must kill their own before phase ends or get MC'd. At 15% he splits into both forms - burn fast." },
                { id = 21875, name = "Shadow of Leotheras",    kind = "boss", marks = {7},
                  spells = { 37675 },
                  notes = "The demon-form copy that splits off from Leotheras at 15% HP. Both forms are tankable separately; raid uses bloodlust/heroism and burst to finish before mechanics overlap." },
                { id = 21214, name = "Fathom-Lord Karathress", kind = "boss", marks = {8},
                  spells = { 38441, 38455, 38452, 38451 },
                  notes = "Council fight with 3 Fathom-Guards (hunter, shaman, priest). Karathress is mostly tank-and-spank with Cataclysmic Bolt (50% max-HP shadow bolt every 10s on a random target). Each guard you kill empowers him with their signature ability, so kill order matters: typically Sharkkis or Tidalvess first, Caribdis last, Karathress finally. Spread guards to corners so AoEs don't overlap." },
                { id = 21213, name = "Morogrim Tidewalker",    kind = "boss", marks = {8},
                  spells = { 37730, 38049, 37764, 37854 },
                  notes = "Hard-hitting giant. Watery Grave teleports 4 random players under the waterfalls for 3.2k frost damage every 30s. Earthquake (4k raid AoE) is followed by two packs of 6 murloc adds spawning from N/S entrances - a Righteous Fury paladin (or feral druid) AoE-tanks while mages/locks burn them. At 25% he stops Graves and spawns roaming Water Globules that explode on the targeted player." },
                { id = 21212, name = "Lady Vashj",             kind = "boss", marks = {8},
                  spells = { 38509, 38280, 38310, 38316, 38145 },
                  notes = "Three phases. P1 ranged-only tanking (Shock Blast stuns and dumps aggro, Static Charge requires moving away, Entangle roots melee). At 70% P2: kill Tainted Elementals to loot Tainted Cores, throw them to players near the four shield generators while stopping Enchanted Elementals from reaching her and kiting fearing Coilfang Striders. P3 (50%): P1 plus increasing Toxic Spore Bats - soft DPS race before poison clouds overwhelm the floor." },
            },
        },
        {
            name = "Karathress Adds",
            npcs = {
                { id = 21965, name = "Fathom-Guard Tidalvess", kind = "boss", marks = {7},
                  spells = { 38229, 38234, 38236, 38306, 38304 },
                  notes = "Enhancement shaman add - Windfury procs and 6k Frost Shocks make his tank's damage extremely spiky. Top kill priority is his Spitfire Totem (25k HP, AoE fire damage) the moment it drops - everyone needs a /target Spitfire macro. Poison Cleansing and Earthbind totems can be ignored." },
                { id = 21966, name = "Fathom-Guard Sharkkis",  kind = "boss", marks = {6},
                  spells = { 29576, 29436, 38373 },
                  notes = "Beast-Mastery hunter add who summons an uncontrollable pet (Fathom Lurker or Fathom Sporebat) that needs its own offtank. Leeching Throw is a Viper Sting clone that drains mana and ticks health - heal mana-hungry classes. Beware The Beast Within enrage on him and the pet." },
                { id = 21964, name = "Fathom-Guard Caribdis",  kind = "boss", marks = {5},
                  spells = { 38335, 33144, 38358, 38337 },
                  notes = "Priest add with a fast 22-30k Heal that ignores LoS/range - interrupting it is mandatory (melee Earth Shock/Kick + backup shaman outside Tidal Surge range). Tidal Surge ice-blocks all melee in 10 yards every 15-20s; Summon Cyclone spawns roaming tornadoes that toss raiders. Curse of Tongues helps." },
                { id = 22119, name = "Fathom Lurker",          kind = "boss", marks = TRASH,
                  spells = { 25778, 38419 },
                  notes = "Sharkkis's beast pet - off-tankable. Hits hard with melee + bleed; share tank cooldowns with the Karathress group. Tranq Shot if it enrages." },
                { id = 22120, name = "Fathom Sporebat",        kind = "boss", marks = TRASH,
                  spells = { 25778 },
                  notes = "Alternate Sharkkis pet (random pick). Flies and applies a Nature DoT; second-priority over Lurker. Kite if not tanked." },
            },
        },
        {
            name = "Hydross Adds",
            npcs = {
                { id = 22036, name = "Tainted Spawn of Hydross", kind = "boss", marks = TRASH,
                  spells = {},
                  notes = "Spawns on the Nature-phase transition (4 per swap). Nature DoT melee adds - AoE-tankable; mages/locks burn them while Hydross is being shifted. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
                { id = 22035, name = "Pure Spawn of Hydross",    kind = "boss", marks = TRASH,
                  spells = {},
                  notes = "Spawns on the Frost-phase transition. Frost-melee adds; same handling as Tainted Spawns but cast Frostbolt at range. AoE down promptly to prevent piling stacks. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
            },
        },
        {
            name = "Leotheras / Vashj Adds",
            npcs = {
                { id = 22056, name = "Coilfang Strider",       kind = "boss", marks = TRASH,
                  spells = { 38257 },
                  notes = "Vashj P2 spore-walker add. Panic Periodic (38257) aura pulses Panic every 2s (4s fear) on anyone in melee - so melee can't touch them. Kited and DoT'd by ranged/DoT classes (warlocks, hunters, shadow priests); also casts Mind Blast." },

                { id = 22140, name = "Toxic Sporebat",         kind = "boss", marks = TRASH,
                  spells = { 38575 },
                  notes = "Vashj Phase 3 add - flies around the room dropping Toxic Spore puddles (~1.5k Nature/sec on impact). Ranged focuses them on kill-order so puddles spread predictably; hunters/locks priority." },

                { id = 21958, name = "Enchanted Elemental",      kind = "boss", marks = TRASH,
                  spells = { 38044 },
                  notes = "Vashj P2 add - walks slowly toward Vashj; if it reaches her she heals 4%. Slow them with Frost effects and burst them before contact. Immune to most CC." },

                { id = 22009, name = "Tainted Elemental",        kind = "boss", marks = TRASH,
                  spells = { 38253 },
                  notes = "Vashj P2 add casting Poison Bolt (38253) at range; drops the Tainted Core on death which the raid throws to disable Vashj's shield generators. Kill priority, but stagger kills so cores arrive when shield generators are ready." },

                { id = 21857, name = "Inner Demon",          kind = "boss", marks = TRASH,
                  spells = { 39309 },
                  notes = "Spawned by Leotheras's Insidious Whisper during Demon phase. Fixates a specific player who MUST kill their own demon via Shadow Bolt (39309) pressure before phase ends or be Mind-Controlled. Burst your own; don't help others." },
                { id = 21218, name = "Vashj'ir Honor Guard", kind = "trash", marks = TRASH,
                  spells = { 38572, 38576, 38947, 38945, 38959 },
                  notes = "Pre-Vashj patrol naga - Mortal Cleave (38572) frontal cone + healing debuff is the headline threat, plus Knockback (38576), Frightening Shout (38945) fear and Execute (38959) below 20%. Tank facing away; Enrage (38947) at low HP is Tranq Shot-able." },
                { id = 22055, name = "Coilfang Elite",       kind = "trash", marks = TRASH,
                  spells = { 38260, 38262 },
                  notes = "Vashj-room hard-hitting melee in packs - Cleave (38260) frontal and Hamstring (38262) slow. AoE-tank with cooldowns and face away from raid; burn the casters first then clean these up." },
            },
        },
        {
            name = "Pre-Hydross Trash",
            npcs = {
                { id = 21253, name = "Tainted Water Elemental",  kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Pre-Hydross room ambient elemental - Frost-school caster, sheepable. Pull singly and tank-and-spank. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
                { id = 21260, name = "Purified Water Elemental", kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Frost water elemental in the entrance area near Hydross. Ranged frost caster - pull to line of sight; banishable if a warlock is available. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },

                { id = 21221, name = "Coilfang Beast-Tamer",   kind = "trash", marks = TRASH,
                  spells = { 38371 },
                  notes = "Immune to CC; Bestial Wrath enrages all nearby Serpentshrine Sporebats, making them uncontrollable. Pull him 30+ yards away from sporebats so they can be CC'd first - and kill sporebats first." },
                { id = 21339, name = "Coilfang Hate-Screamer", kind = "trash", marks = TRASH,
                  spells = { 38496 },
                  notes = "Immune to all CC; spams a 30yd Sonic Scream (~1.8k Arcane + silence). Tank in place away from casters and burn FIRST - kill priority over companions." },
                { id = 21246, name = "Serpentshrine Sporebat", kind = "trash", marks = TRASH,
                  spells = { 38461 },
                  notes = "Charges a random target for ~1k physical + 5s stun, plus Spore Burst Nature DoT in melee. Sheep/Trap on the pull; once the Beast-Tamer enrages them they're CC-immune so kill Sporebats first." },
                { id = 21251, name = "Underbog Colossus",      kind = "trash", marks = TRASH,
                  spells = { 38718, 38971, 38976, 39015, 39044, 39031 },
                  notes = "Toxic Pool (38718), Acid Geyser (38971), Spore Quake (38976) knockdown, Atrophic Blow (39015) STR debuff, Serpentshrine Parasite (39044) and Frenzy (39031) enrage - random subset per spawn, immune to interrupts/CC. Tank facing away and spread 30yd; expect random death effects (mushrooms, Ragers, Lurkers)." },
                { id = 22352, name = "Colossus Rager",         kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Small adds spawned on Underbog Colossus death (one random outcome). Low HP but numerous - AoE down quickly before they reach raid. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
                { id = 22347, name = "Colossus Lurker",        kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Two adds spawned on Underbog Colossus death (another random outcome). Heavier hitters than Ragers - off-tank pickup and burn before re-engaging the next pull. Ability spell IDs unresolved: Wowhead /tbc/ page is a stub, retail page returns modern Timewalking IDs only. Likely pure-melee trash; if any IDs are needed, in-game combat-log capture is the path." },
            },
        },
        {
            name = "Pre-Lurker Trash (Platforms)",
            npcs = {
                { id = 21220, name = "Coilfang Priestess",     kind = "trash", marks = TRASH,
                  spells = { 2060 },
                  notes = "Casts Greater Heal (~22-30k) on allies - TOP kill priority; must be silenced/kicked/CC'd (sheep, fear, stuns all work). Drops an instant Holy Nova on death." },
                { id = 21301, name = "Coilfang Shatterer",     kind = "trash", marks = TRASH,
                  spells = { 38591 },
                  notes = "Hits tanks hard in melee and casts Shatter Armor (3s cast, -50% armor for 15s) - warriors can Spell Reflect. Tank with two physical tanks or use Shield Block timing; stunnable." },
                { id = 21263, name = "Greyheart Technician",   kind = "trash", marks = TRASH,
                  spells = { 38995 },
                  notes = "Lurker-platform utility mob - only Hamstring (38995) slow on top of melee. Low priority; sheep on the pull and kill after dangerous casters." },
                { id = 21865, name = "Coilfang Ambusher",      kind = "trash", marks = TRASH,
                  spells = { 37770, 37790 },
                  notes = "Lurker-intermission ranged add (2 per platform) - Spread Shot (37790) cone volley up to ~6.3k is the threat, plus regular Shoot (37770). Sheep/Trap/Banish on pre-assigned platforms during the dive." },
                { id = 21873, name = "Coilfang Guardian",      kind = "trash", marks = TRASH,
                  spells = { 28168, 9080, 39700 },
                  notes = "Lurker-intermission heavy melee (3) - Arcing Smash (28168) frontal cleave, Hamstring (9080) slow, and a short-range Teleport (39700). Off-tanks pick up immediately and face away from raid; stunnable to reduce tank damage." },
                { id = 21508, name = "Coilfang Frenzy",        kind = "trash", marks = TRASH,
                  spells = {},
                  notes = "Small piranha-like beasts swarming anyone swimming on Lurker platforms (Scalding Water active). Stay out of water until platforms cleared; AoE down if pulled." },
            },
        },
        {
            name = "Pre-Leotheras Trash",
            npcs = {
                { id = 21229, name = "Greyheart Tidecaller",    kind = "trash", marks = TRASH,
                  spells = { 32690 },
                  notes = "Caster with Arcane Lightning - chain-lightning that silences up to 5 targets for 4s; also drops a Water Elemental Totem (~5k HP) spawning elite Water Elementals. KILL THE TOTEM ON SIGHT and interrupt Arcane Lightning. Poison Shield reflects nature damage." },
                { id = 22236, name = "Water Elemental Totem",   kind = "trash", marks = TRASH,
                  spells = { 38622 },
                  notes = "Totem dropped by Greyheart Tidecaller - about 5k HP, summons elite Water Elementals. Kill it on sight before it spawns adds." },
                { id = 21230, name = "Greyheart Nether-Mage",   kind = "trash", marks = TRASH,
                  spells = { 37109 },
                  notes = "Comes in Fire/Frost/Arcane variants per pull - Fireball Volley/Rain of Fire/Scorch, or Cone of Cold/Frostbolt Volley, or Arcane Volley/Arcane Lightning. TOP interrupt priority - kick the volleys and burn before the Tidecaller." },
                { id = 21232, name = "Greyheart Skulker",       kind = "trash", marks = TRASH,
                  spells = { 38625 },
                  notes = "Rogue-style add with a Kick (38625) interrupt that locks the spell school. Pull to melee range so it can't pick off healers; cleave/burn after dangerous casters." },
                { id = 21231, name = "Greyheart Shield-Bearer", kind = "trash", marks = TRASH,
                  spells = { 38631, 38630 },
                  notes = "Paladin-style add - ranged Avenger's Shield (38631) and Shield Charge (38630) that knockbacks and damages a random target. Tank in melee and pre-position so the charge can't yank players into adjacent packs." },
                { id = 21806, name = "Greyheart Spellbinder",   kind = "trash", marks = TRASH,
                  spells = { 37531, 37527, 39076 },
                  notes = "Caster with Mind Blast (37531), Banish (37527) (10s incapacitate on a raid member - cleanse the affected player) and Spell Shock (39076) (locks a school for 6s). Interrupt or kill priority; dispel Banish so the player can resume DPS." },
                { id = 21863, name = "Serpentshrine Lurker",    kind = "trash", marks = TRASH,
                  spells = { 38655, 38650 },
                  notes = "HIGHEST kill priority - Poison Bolt Volley (38655) hits the whole raid as a Nature DoT, and Rancid Mushroom (38650) seeds explosive sporelings. Banishable; kill first, then step out of any seeded mushroom radii." },
                { id = 21298, name = "Coilfang Serpentguard",   kind = "trash", marks = TRASH,
                  spells = { 38599, 38603 },
                  notes = "Naga warrior with Spell Reflection (38599) (8s, reflects next hardcast - stop casts) and Corrupt Devotion Aura (38603) (-25% armor on enemies within 8 yards). Immune to CC; tank facing away from raid." },
                { id = 21299, name = "Coilfang Fathom-Witch",   kind = "trash", marks = TRASH,
                  spells = { 39175 },
                  notes = "Casts Shadow Bolt Volley (~1.3-1.7k raid-wide Shadow) and a Shadow Nova knockback (~3k) - dangerous on narrow ramps where it can punt players into water. Mind-controls one player at a time. Immune to CC; interrupt the volley and dispel MC." },
                { id = 22250, name = "Rancid Mushroom",         kind = "trash", marks = TRASH,
                  spells = { 38652, 38653 },
                  notes = "Stationary mushroom seeded by Serpentshrine Lurkers - grows then detonates Spore Cloud (38652) (instant hit) plus stacking Nature DoT (38653). Move out of its radius; AoE it down before it pops if positioning permits." },
            },
        },
        {
            name = "Pre-Morogrim Trash",
            npcs = {
                { id = 21225, name = "Tidewalker Warrior",     kind = "trash", marks = TRASH,
                  spells = { 39070, 39071, 39069, 38664 },
                  notes = "Murloc melee - Bloodthirst (39070/39071) hits, Uppercut (39069) knockup, and Frenzy (38664) periodic enrage that hunters should Tranq Shot. Tank facing away from raid; immune to stuns." },
                { id = 21226, name = "Tidewalker Shaman",      kind = "trash", marks = TRASH,
                  spells = { 39065, 39066, 39067 },
                  notes = "Murloc caster - Chain Lightning (39066) is the biggest threat (can bounce 5 targets), plus Lightning Bolt (39065) single-target and self-buff Lightning Shield (39067). Interrupt or kill priority; Curse of Tongues helps." },
                { id = 21920, name = "Tidewalker Lurker",      kind = "trash", marks = TRASH,
                  spells = { 41932 },
                  notes = "Small murloc add summoned by Morogrim during the encounter (not patrols). Carnivorous Bite (41932) physical DoT (~1.5-2k/3s for 15s) on top of melee; AoE down with the murloc waves." },
                { id = 21228, name = "Tidewalker Hydromancer", kind = "trash", marks = TRASH,
                  spells = { 39064, 39063, 39062 },
                  notes = "Murloc mage - hardcasts Frostbolt (39064, ~2.7-3.4k), Frost Shock (39062) instant, and AoE Frost Nova (39063, ~1.7k + root) so spread out. Stunnable, silenceable, fully interruptible." },
                { id = 21227, name = "Tidewalker Harpooner",   kind = "trash", marks = TRASH,
                  spells = { 39061, 38661 },
                  notes = "Murloc with Impale (39061) physical DoT every 3s for 12s and Net (38661) - an 8s root that DROPS HIS AGGRO, so the tank must immediately re-taunt. Immune to all CC and snares; melee from behind." },
                { id = 21224, name = "Tidewalker Depth-Seer",  kind = "trash", marks = TRASH,
                  spells = { 38657, 38658, 38659 },
                  notes = "Murloc druid - dispellable Rejuvenation (38657) HoT and Healing Touch (38658) on allies, plus a sub-30% UNINTERRUPTIBLE Tranquility (38659) that fully heals the pack if not burst through. Interrupt early heals; save burst CDs for the Tranquility window." },
            },
        },
        {
            name = "Misc",
            npcs = {
            },
        },
    },
})

-- Atlas Bosses-leaf tree (Morpheours-spec; Spitfire Totem dropped).
L3F:RegisterBossTree("Serpentshrine Cavern", {
    { name = "Hydross the Unstable", npcID = 21216, subs = {
        { npcID = 22036 },  -- Tainted Spawn of Hydross
        { npcID = 22035 },  -- Pure Spawn of Hydross
    } },
    { name = "The Lurker Below", npcID = 21217, subs = {} },
    { name = "Leotheras the Blind", npcID = 21215, subs = {
        { npcID = 21875 },  -- Shadow of Leotheras
        { npcID = 21857 },  -- Inner Demon
    } },
    { name = "Fathom-Lord Karathress", npcID = 21214, subs = {
        { npcID = 21965 },  -- Fathom-Guard Tidalvess
        { npcID = 21964 },  -- Fathom-Guard Caribdis
        { npcID = 21966 },  -- Fathom-Guard Sharkkis
        { npcID = 22119 },  -- Fathom Lurker
        { npcID = 22120 },  -- Fathom Sporebat
    } },
    { name = "Morogrim Tidewalker", npcID = 21213, subs = {} },
    { name = "Lady Vashj", npcID = 21212, subs = {
        { npcID = 22056 },  -- Coilfang Strider (Morpheours: "Coilfand")
        { npcID = 21958 },  -- Enchanted Elemental
        { npcID = 22009 },  -- Tainted Elemental
        { npcID = 22140 },  -- Toxic Sporebat
    } },
})
