-- Made in the Shipyard (F2).
station {
	id = "shipyard_cruciform", name = "Cruciform Fleet Pavilion",
	role = "shipyard",
	color = { 0.72, 0.70, 0.66 },
	services = { "market", "shipyard", "hangar", "repair" },
	rotors = {
		center_beacon = { over = true, spin = 0.8, x = 0, y = 0 },
	},
	berths = {
		-- North Pier Berths (facing East / 0 and West / 180)
		{ heading = 180, size = 200, x = -280, y = -1200 },
		{ heading = 0,   size = 200, x = 280,  y = -1200 },
		{ heading = 180, size = 200, x = -280, y = -750 },
		{ heading = 0,   size = 200, x = 280,  y = -750 },
		-- South Pier Berths
		{ heading = 180, size = 200, x = -280, y = 750 },
		{ heading = 0,   size = 200, x = 280,  y = 750 },
		{ heading = 180, size = 200, x = -280, y = 1200 },
		{ heading = 0,   size = 200, x = 280,  y = 1200 },
		-- West Pier Berths (facing North / 270 and South / 90)
		{ heading = 270, size = 200, x = -1200, y = -280 },
		{ heading = 90,  size = 200, x = -1200, y = 280 },
		{ heading = 270, size = 200, x = -750,  y = -280 },
		{ heading = 90,  size = 200, x = -750,  y = 280 },
		-- East Pier Berths
		{ heading = 270, size = 200, x = 750,  y = -280 },
		{ heading = 90,  size = 200, x = 750,  y = 280 },
		{ heading = 270, size = 200, x = 1200, y = -280 },
		{ heading = 90,  size = 200, x = 1200, y = 280 },
	},
	parts = {
		-- Central Octagonal Atrium Pavilion
		{ name = "central atrium", shape = { -300, -120, -120, -300, 120, -300, 300, -120, 300, 120, 120, 300, -120, 300, -300, 120 }, shade = 1.1, tint = { 0.04, 0.02, -0.02 }, lights = {
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = -180, y = -180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = 180, y = -180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = 180, y = 180 },
			{ color = { 1, 0.95, 0.85 }, kind = "window", size = 8, x = -180, y = 180 },
		} },

		-- North Promenade Pier
		{ name = "north pier", shape = { -70, -1500, 70, -1500, 70, -300, -70, -300 }, shade = 0.85 },
		{ name = "north pier head", shape = { -160, -1580, 160, -1580, 160, -1500, -160, -1500 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1.0, size = 10, x = 0, y = -1570 },
		} },

		-- South Promenade Pier
		{ name = "south pier", shape = { -70, 300, 70, 300, 70, 1500, -70, 1500 }, shade = 0.85 },
		{ name = "south pier head", shape = { -160, 1500, 160, 1500, 160, 1580, -160, 1580 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1.0, size = 10, x = 0, y = 1570 },
		} },

		-- West Promenade Pier
		{ name = "west pier", shape = { -1500, -70, -300, -70, -300, 70, -1500, 70 }, shade = 0.85 },
		{ name = "west pier head", shape = { -1580, -160, -1500, -160, -1500, 160, -1580, 160 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1.0, size = 10, x = -1570, y = 0 },
		} },

		-- East Promenade Pier
		{ name = "east pier", shape = { 300, -70, 1500, -70, 1500, 70, 300, 70 }, shade = 0.85 },
		{ name = "east pier head", shape = { 1500, -160, 1580, -160, 1580, 160, 1500, 160 }, shade = 1.15, lights = {
			{ color = { 1, 0.75, 0.3 }, kind = "strobe", rate = 1.0, size = 10, x = 1570, y = 0 },
		} },

		-- Central Rotating Radar / Beacon Array
		{ name = "central beacon hub", shape = { -45, -45, 45, -45, 45, 45, -45, 45 }, shade = 1.25, rotor = "center_beacon", lights = {
			{ color = { 0.4, 0.85, 1.0 }, kind = "strobe", rate = 2.0, size = 10, x = -40, y = 0 },
			{ color = { 0.4, 0.85, 1.0 }, kind = "strobe", rate = 2.0, size = 10, x = 40, y = 0 },
		} },

		-- Internal Delivery Dock (integrated at the base of the South Pier)
		{ name = "delivery dock", shape = { -120, 350, 120, 350, 120, 600, -120, 600 }, shade = 0.7, lights = {
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.7, size = 6, x = -110, y = 590 },
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", rate = 0.7, size = 6, x = 110, y = 590 },
		}, dock = true, dockHeading = 90 },
	},
}