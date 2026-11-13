hull {
	id = "warden_drone", name = "Warden", maker = "Nova Syndicate", class = "drone", playable = false, mount = "turret", turretTurn = 200,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20,
	shape = { 48,0, 20,-16, -26,-20, -36,0, -26,20, 20,16 },
	slots = {
		{ family = "hardpoint", size = "M", x = 14, y = -8 },
		{ family = "hardpoint", size = "M", x = 14, y = 8 },
		{ family = "engine",  size = "M", x = -34, y = 0 },
		{ family = "reactor", size = "L" },
	},
	loadout = { "pulse_m_base", "pulse_m_base", "mule_engine", "forge_reactor" },
}
