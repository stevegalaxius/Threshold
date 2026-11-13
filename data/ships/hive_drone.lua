hull {
	id = "hive_drone", name = "Hive", maker = "Nova Syndicate", class = "drone", playable = false, mount = "gimbal",
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14,
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14,
	shape = { 34,0, 6,-9, -20,-14, -14,0, -20,14, 6,9 },
	slots = {
		{ family = "hardpoint", size = "M", x = 12, y = 0 },
		{ family = "engine",  size = "M", x = -16, y = 0 },
		{ family = "reactor", size = "M" },
	},
	loadout = { "pulse_m_base", "mule_engine", "kiln_reactor" },
}
