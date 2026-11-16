-- Trade-buoy hub: the larger satellite that sits on every trade buoy
-- (src/satellites.lua, kind "hub"). A mini station for ships passing
-- through: fuel and supplies off its shelf, docking for the player.
-- Edit freely in the Shipyard.
prop {
	id = "trade_hub", name = "Trade hub",
	armor = 900, mass = 12000,
	parts = {
		{ name = "hub", shape = { 138.58, 57.4, 57.4, 138.58, -57.4, 138.58, -138.58, 57.4, -138.58, -57.4, -57.4, -138.58, 57.4, -138.58, 138.58, -57.4 }, color = { 0.3, 0.31, 0.35 }, core = true, lights = { { x = -90, y = -40, size = 4 }, { x = -60, y = -40, size = 4 }, { x = -30, y = -40, size = 4 }, { x = 30, y = -40, size = 4 }, { x = 60, y = -40, size = 4 }, { x = 90, y = -40, size = 4 }, { x = -90, y = 40, size = 4 }, { x = -60, y = 40, size = 4 }, { x = -30, y = 40, size = 4 }, { x = 30, y = 40, size = 4 }, { x = 60, y = 40, size = 4 }, { x = 90, y = 40, size = 4 } } },
		{ name = "spine", shape = { -520, -10, 520, -10, 520, 10, -520, 10 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "cross spar", shape = { -10, -300, 10, -300, 10, 300, -10, 300 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "panel", shape = { -520, -170, -360, -170, -360, -16, -520, -16 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.3, lights = { { color = { 0.35, 0.9, 1 }, kind = "strobe", phase = 0.0, rate = 0.5, size = 9, x = -520, y = -171 } } },
		{ name = "panel", shape = { -520, 16, -360, 16, -360, 170, -520, 170 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.3, lights = { { color = { 0.35, 0.9, 1 }, kind = "strobe", phase = 0.25, rate = 0.5, size = 9, x = -520, y = 171 } } },
		{ name = "panel", shape = { 360, -170, 520, -170, 520, -16, 360, -16 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.3, lights = { { color = { 0.35, 0.9, 1 }, kind = "strobe", phase = 0.5, rate = 0.5, size = 9, x = 520, y = -171 } } },
		{ name = "panel", shape = { 360, 16, 520, 16, 520, 170, 360, 170 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.3, lights = { { color = { 0.35, 0.9, 1 }, kind = "strobe", phase = 0.75, rate = 0.5, size = 9, x = 520, y = 171 } } },
		{ name = "fuel tank", shape = { 70.0, -235.0, 64.67, -215.1, 49.5, -198.23, 26.79, -186.96, 0.0, -183.0, -26.79, -186.96, -49.5, -198.23, -64.67, -215.1, -70.0, -235.0, -64.67, -254.9, -49.5, -271.77, -26.79, -283.04, -0.0, -287.0, 26.79, -283.04, 49.5, -271.77, 64.67, -254.9 }, color = { 0.55, 0.42, 0.22 }, mass = 2 },
		{ name = "tank band", shape = { -70, -240, 70, -240, 70, -230, -70, -230 }, color = { 0.4, 0.3, 0.16 }, layer = "detail", collide = false },
		{ name = "fuel tank", shape = { 70.0, 235.0, 64.67, 254.9, 49.5, 271.77, 26.79, 283.04, 0.0, 287.0, -26.79, 283.04, -49.5, 271.77, -64.67, 254.9, -70.0, 235.0, -64.67, 215.1, -49.5, 198.23, -26.79, 186.96, -0.0, 183.0, 26.79, 186.96, 49.5, 198.23, 64.67, 215.1 }, color = { 0.55, 0.42, 0.22 }, mass = 2 },
		{ name = "tank band", shape = { -70, 230, 70, 230, 70, 240, -70, 240 }, color = { 0.4, 0.3, 0.16 }, layer = "detail", collide = false },
		{ name = "deck", shape = { 99.78, 41.33, 41.33, 99.78, -41.33, 99.78, -99.78, 41.33, -99.78, -41.33, -41.33, -99.78, 41.33, -99.78, 99.78, -41.33 }, color = { 0.36, 0.37, 0.41 }, layer = "detail", collide = false },
		{ name = "shop sign", shape = { -70, -14, 70, -14, 70, 14, -70, 14 }, color = { 0.75, 0.55, 0.2 }, layer = "detail", collide = false, lights = { { x = -60, y = 0, size = 5, color = { 1, 0.75, 0.3 } }, { x = 60, y = 0, size = 5, color = { 1, 0.75, 0.3 } } } },
		{ name = "docking arm", shape = { -300, -26, -150, -26, -150, 26, -300, 26 }, color = { 0.42, 0.45, 0.5 } },
		{ name = "berth pad", shape = { -340, -60, -300, -60, -300, 60, -340, 60 }, color = { 0.5, 0.52, 0.56 }, lights = { { kind = "nav", color = { 1, 0.25, 0.2 }, x = -340, y = -60 }, { kind = "nav", color = { 1, 0.25, 0.2 }, x = -340, y = 60 } } },
		{ name = "docking arm", shape = { 150, -26, 300, -26, 300, 26, 150, 26 }, color = { 0.42, 0.45, 0.5 } },
		{ name = "berth pad", shape = { 300, -60, 340, -60, 340, 60, 300, 60 }, color = { 0.5, 0.52, 0.56 }, lights = { { kind = "nav", color = { 0.3, 1, 0.4 }, x = 340, y = -60 }, { kind = "nav", color = { 0.3, 1, 0.4 }, x = 340, y = 60 } } },
	},
}
