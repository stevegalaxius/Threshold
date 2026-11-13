-- Harasser: tiny, twitchy, strong side thrusters. Hard to hit on purpose.
hull {
	id = "nova_dart", name = "Dart", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11,
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11,
	shape = { 28,0, 4,-5, -16,-10, -10,0, -16,10, 4,5 },
	slots = {
		{ family = "hardpoint", size = "S", x = 10,  y = 0 },
		{ family = "engine",  size = "S", x = -14, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "gun_s_base", "flit_engine", "ember_reactor" },
}
