-- Made in the Shipyard (F2).
station {
	id = "zhuhai_strip_mine", name = "Zhuhai Strip Mine",
	color = { 0.55, 0.63, 0.74 },
	parts = {
		{ name = "processing deck", shape = { -260, 70, 340, 70, 340, 115, -260, 115 }, shade = 0.85 },
		{ name = "left footing", shape = { -240, 115, -180, 115, -180, 175, -240, 175 }, shade = 0.7 },
		{ name = "right footing", shape = { 260, 115, 320, 115, 320, 175, 260, 175 }, shade = 0.7 },
		{ name = "gantry upper rail", shape = { -470, -40, -220, -40, -220, -20, -470, -20 }, shade = 0.8 },
		{ name = "gantry lower rail", shape = { -470, 45, -220, 45, -220, 65, -470, 65 }, shade = 0.8 },
		{ name = "gantry brace outer", shape = { -470, -20, -450, -20, -365, 45, -385, 45 }, shade = 0.75 },
		{ name = "gantry brace inner", shape = { -350, -20, -330, -20, -245, 45, -265, 45 }, shade = 0.75 },
		{ name = "cutter drop", shape = { -470, -20, -440, -20, -440, 140, -470, 140 }, shade = 0.8 },
		{ name = "cutting shoe", shape = { -495, 140, -415, 140, -415, 165, -430, 180, -440, 165, -455, 180, -465, 165, -480, 180, -495, 165 }, shade = 0.95, tint = { 0.025, 0, -0.025 } },
		{ name = "ore container 1", shape = { -250, -100, -140, -100, -140, 65, -250, 65 }, shade = 0.9, tint = { 0.025, 0, -0.025 } },
		{ name = "ore container 2", shape = { 170, -45, 245, -45, 245, 65, 170, 65 }, shade = 0.9, tint = { 0.025, 0, -0.025 } },
		{ name = "ore container 3", shape = { 260, -45, 335, -45, 335, 65, 260, 65 }, shade = 0.9, tint = { 0.025, 0, -0.025 } },
		{ name = "crusher housing", shape = { -130, -90, -20, -90, -20, 65, -130, 65 }, shade = 1.05 },
		{ name = "control cabin", shape = { 190, -115, 315, -115, 315, -60, 190, -60 }, shade = 1.08, tint = { -0.015, 0, 0.02 }, lights = {
			{ kind = "window", size = 3, x = 205, y = -102 },
			{ kind = "window", size = 3, x = 235, y = -102 },
			{ kind = "window", size = 3, x = 265, y = -102 },
			{ kind = "window", size = 3, x = 295, y = -102 },
		} },
		{ name = "cabin support", shape = { 245, -60, 265, -60, 265, 70, 245, 70 }, shade = 0.8 },
		{ name = "tractor dock", shape = { -150, -240, 150, -240, 150, -40, -150, -40 }, lights = {
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.625, size = 3, x = -130, y = -230 },
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.625, size = 3, x = 130, y = -230 },
		}, dock = true },
		{ name = "dock neck", shape = { -15, -40, 65, -40, 65, 70, -15, 70 }, shade = 0.85 },
	},
}
