--[[
	Enemies are ships built from the same hulls and modules as the player,
	plus an AI. They carry real ammo too, and drop part of what's left.

	ai.style     rush (close in, brawl or ram), orbit (circle at range),
	             kite (hold range, back off when approached)
	ai.range     preferred distance in pixels
	ai.accuracy  0..1, how well it leads its shots
	ai.throttle  0..1, how hard it uses its engines
	ai.ram       true = keeps pushing into you instead of stopping at range
	ai.burstOn, ai.burstOff  seconds of firing, then of pause (default 1.2, 0.9)
	             trader (neutral: flies its route, and only shoots back at
	             whoever attacked it)
	team         2 = hostile (default), 3 = neutral (never in waves; only
	             spawned by playing fields)
	livery       faction paint { primary = { r, g, b }, secondary = { r, g, b }? }
	             (secondary defaults to a shade of the primary); leave it
	             out and the ship flies its hull's factory preset
	salvage      { min, max } salvage left in its husk (along with its
	             whole hold)
]]

enemy {
	id = "swarmer", livery = { primary = { 0.95, 0.5, 0.32 } }, name = "Scrap Drone", hull = "scrap_drone",
	cargo = { rounds_s = 150 },
	ai = { style = "rush", range = 350, accuracy = 0.35, throttle = 0.6, burstOn = 0.8, burstOff = 1.8 },
	salvage = { 1, 2 },
}

enemy {
	id = "gunner", livery = { primary = { 0.95, 0.8, 0.3 } }, name = "Raider Wisp", hull = "intaki_wisp",
	loadout = { "gun_s_base", "gun_s_base", "flit_engine", "ember_reactor", false, false },
	cargo = { rounds_s = 300 },
	ai = { style = "orbit", range = 600, accuracy = 0.55, throttle = 0.75 },
	salvage = { 2, 3 },
}

enemy {
	id = "brawler", livery = { primary = { 0.95, 0.3, 0.3 } }, name = "Raider Anvil", hull = "brute_anvil",
	loadout = { "gun_m_base", "gun_m_base", false, false, "mule_engine", "kiln_reactor", false },
	cargo = { rounds_m = 100 },
	ai = { style = "rush", range = 500, accuracy = 0.55, throttle = 0.85 },
	salvage = { 3, 5 },
}

enemy {
	id = "sniper", livery = { primary = { 0.75, 0.45, 0.95 } }, name = "Raider Mortar", hull = "brute_anvil",
	loadout = { "gun_m_base", false, "artillery_m_base", false, "mule_engine", "kiln_reactor", false },
	cargo = { shell_m = 24, rounds_m = 150 },
	ai = { style = "kite", range = 1500, accuracy = 0.6, throttle = 0.7, burstOn = 2, burstOff = 2 },
	salvage = { 3, 5 },
}

-- Harasser: the fast, hard-to-hit one. Shows up from wave 3.
enemy {
	id = "interceptor", livery = { primary = { 0.5, 0.95, 0.45 } }, name = "Dart", hull = "nova_dart",
	cargo = { rounds_s = 100 },
	ai = { style = "orbit", range = 450, accuracy = 0.6, throttle = 1.0, burstOn = 0.8, burstOff = 1.2 },
	salvage = { 1, 3 },
}

-- Neutral trader: hauls cargo between stations. Leave it alone and it
-- leaves you alone. It leaves port with only its own ammunition; anything
-- else in its hold is real cargo it loaded for a dispatch job.
enemy {
	id = "freighter", team = 3, name = "Hauler", hull = "ferrous_freighter",
	cargo = { rounds_m = 200 },
	ai = { style = "trader", range = 1400, accuracy = 0.5, throttle = 0.85, burstOn = 1.5, burstOff = 0.8 },
	salvage = { 4, 8 },
}

-- A courier in a Runner: small hold, quick, and it runs rather than fights.
enemy {
	id = "runner_trader", team = 3, name = "Runner", hull = "ferrous_runner",
	cargo = { rounds_s = 100 },
	ai = { style = "trader", range = 900, accuracy = 0.5, throttle = 1.0, cruise = 900, horizon = 2.5, burstOn = 1.0, burstOff = 1.0 },
	salvage = { 1, 3 },
}

-- The everyday trader in a Packhorse: a fair hold and enough guns to
-- make a lone pirate think twice.
enemy {
	id = "packhorse_trader", team = 3, name = "Packhorse", hull = "ferrous_mule",
	cargo = { rounds_m = 100 },
	ai = { style = "trader", range = 1200, accuracy = 0.55, throttle = 0.9, cruise = 700, horizon = 3.5, burstOn = 1.2, burstOff = 0.9 },
	salvage = { 2, 5 },
}

-- Persistent A-Life roles. Role/duty live in the NPC record, while these
-- definitions expose their hull, equipment and combat handling for variants.
enemy {
 id = "patrol_wisp", team = 3, name = "Independent Patrol", hull = "intaki_wisp",
 livery = { primary = { 0.4, 0.75, 1 } },
 loadout = { "gun_s_base", "gun_s_base", "flit_engine", "ember_reactor", false, false },
 cargo = { rounds_s = 400 },
 ai = { style = "orbit", range = 900, accuracy = 0.65, throttle = 0.85, cruise = 750 },
 salvage = { 2, 3 },
}
enemy {
 id = "pirate_wisp", team = 2, name = "Independent Pirate", hull = "intaki_wisp",
 livery = { primary = { 1, 0.4, 0.25 } },
 loadout = { "gun_s_base", "gun_s_base", "flit_engine", "ember_reactor", false, false },
 cargo = { rounds_s = 300, scrap = 3 },
 ai = { style = "orbit", range = 700, accuracy = 0.55, throttle = 0.8, cruise = 650 },
 salvage = { 2, 4 },
}

-- A civilian mining fit using the same contact drills as the player.
enemy {
 id="miner_packhorse",team=3,name="Independent Miner",hull="ferrous_mule",
 loadout={"drill_m_base","drill_m_base",false,"mule_engine","kiln_reactor","tug_beam",false,false},
 cargo={},ai={style="trader",cruise=500,range=2500,accuracy=.7,throttle=.9},salvage={1,2},
}

-- Civilian loose-cargo collector. It trades salvage, not generated manifests.
enemy {
 id="salvager_packhorse",team=3,name="Independent Salvager",hull="ferrous_mule",
 loadout={false,false,false,"mule_engine","kiln_reactor","tug_beam",false,false},
 cargo={},ai={style="trader",cruise=600,range=1200,accuracy=.5,throttle=.9},salvage={1,2},
}
