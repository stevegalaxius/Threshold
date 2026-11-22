-- Made in the Shipyard (F2).
station {
	id = "shipyard_cruciform", name = "Cruciform Fleet Pavilion",
	berths = {
		{ heading = 180, size = 200, x = -280, y = -1200 },
		{ size = 200, x = 280, y = -1200 },
		{ heading = 180, size = 200, x = -280, y = -750 },
		{ size = 200, x = 280, y = -750 },
		{ heading = 180, size = 200, x = -280, y = 750 },
		{ size = 200, x = 280, y = 750 },
		{ heading = 180, size = 200, x = -280, y = 1200 },
		{ size = 200, x = 280, y = 1200 },
		{ heading = 270, size = 200, x = -1200, y = -280 },
		{ heading = 90, size = 200, x = -1200, y = 280 },
		{ heading = 270, size = 200, x = -750, y = -280 },
		{ heading = 90, size = 200, x = -750, y = 280 },
		{ heading = 270, size = 200, x = 750, y = -280 },
		{ heading = 90, size = 200, x = 750, y = 280 },
		{ heading = 270, size = 200, x = 1200, y = -280 },
		{ heading = 90, size = 200, x = 1200, y = 280 },
	},
	color = { 0.72, 0.7, 0.66 },
	hangar = { h = 5, w = 5 },
	role = "shipyard",
	rotors = { center_beacon = { over = true, spin = 0.8, x = 0, y = 0 } },
	services = { "market", "shipyard", "hangar", "repair" },
	parts = {
		{ name = "delivery dock", shape = { -120, 1438, 120, 1438, 120, 1688, -120, 1688 }, shade = 0.7, mirror = true, lights = {
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.7, size = 6, x = -110, y = 1678 },
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.7, size = 6, x = 110, y = 1678 },
		}, dock = true, dockHeading = 90 },
		{ name = "central atrium", shape = { -300, -120, -120, -300, 120, -300, 300, -120, 300, 120, 120, 300, -120, 300, -300, 120 }, shade = 1.1, tint = { 0.04, 0.02, -0.02 }, lights = {
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = -180, y = -180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = 180, y = -180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = 180, y = 180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = -180, y = 180 },
		} },
		{ name = "north pier", shape = { -70, -1500, 70, -1500, 70, -300, -70, -300 }, shade = 0.85 },
		{ name = "north pier head", shape = { -160, -1580, 160, -1580, 160, -1500, -160, -1500 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1, size = 10, x = 0, y = -1570 },
		} },
		{ name = "south pier", shape = { -70, 300, 70, 300, 70, 1500, -70, 1500 }, shade = 0.85 },
		{ name = "south pier head", shape = { -160, 1500, 160, 1500, 160, 1580, -160, 1580 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1, size = 10, x = 0, y = 1570 },
		} },
		{ name = "west pier", shape = { -1500, -70, -300, -70, -300, 70, -1500, 70 }, shade = 0.85 },
		{ name = "west pier head", shape = { -1580, -160, -1500, -160, -1500, 160, -1580, 160 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1, size = 10, x = -1570, y = 0 },
		} },
		{ name = "east pier", shape = { 300, -70, 1500, -70, 1500, 70, 300, 70 }, shade = 0.85 },
		{ name = "east pier head", shape = { 1500, -160, 1580, -160, 1580, 160, 1500, 160 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1, size = 10, x = 1570, y = 0 },
		} },
		{ name = "central beacon hub", shape = { -45, -45, 45, -45, 45, 45, -45, 45 }, shade = 1.25, lights = {
			{ color = { 0.4, 0.85, 1 }, kind = "strobe", rate = 2, size = 10, x = -40, y = 0 },
			{ color = { 0.4, 0.85, 1 }, kind = "strobe", rate = 2, size = 10, x = 40, y = 0 },
		}, rotor = "center_beacon" },
	},
}
