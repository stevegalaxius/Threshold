hull {
	id = "wasp_drone", name = "Wasp", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 14, armor = 30, turn = 160, sideThrust = 260, retroThrust = 260, hold = 4, drag = 0.12, radius = 8,
	shape = { 22,0, 2,-4, -12,-8, -8,0, -12,8, 2,4 },
	slots = {
		{ family = "hardpoint", size = "S", x = 8,  y = 0 },
		{ family = "engine",  size = "S", x = -10, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "pulse_s_base", "flit_engine", "ember_reactor" },
}
