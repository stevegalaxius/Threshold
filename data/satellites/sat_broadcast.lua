-- Broadcast satellite (data/satellites/sat_broadcast.lua): a passive satellite
-- with a large dish antenna that sends propaganda and alerts to passing ships.
-- Edit in the Shipyard (F2). Panel strips are sensors; the truss is drawn only.
satellite {
	id = "sat_broadcast", name = "Broadcast satellite",
	armor = 300, mass = 3000,
	parts = {
		{ name = "bus", shape = { -42, -42, 42, -42, 42, 42, -42, 42 }, color = { 0.29, 0.3, 0.33 }, core = true },
		{ name = "equipment", shape = { -33, -33, -3, -33, -3, -3, -33, -3 }, color = { 0.36, 0.37, 0.41 }, layer = "detail", collide = false },
		{ name = "equipment", shape = { 3, 3, 33, 3, 33, 33, 3, 33 }, color = { 0.36, 0.37, 0.41 }, layer = "detail", collide = false },
		{ name = "owner stripe", shape = { -42, 27, 42, 27, 42, 42, -42, 42 }, color = { 0.75, 0.59, 0.24 }, layer = "detail", collide = false },
		-- large dish antenna (the defining feature)
		{ name = "dish mast", shape = { -1.5, -108, 1.5, -108, 1.5, -54, -1.5, -54 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "dish", shape = { -42, -132, 42, -132, 30, -114, -30, -114 }, color = { 0.8, 0.82, 0.85 }, layer = "detail", collide = false, lights = { { color = { 1, 0.2, 0.2 }, kind = "strobe", phase = 0, rate = 1, size = 6, x = 0, y = -132 } } },
		{ name = "feed horn", shape = { -4, -120, 4, -120, 4, -108, -4, -108 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		-- smaller secondary dish
		{ name = "dish mast 2", shape = { 1.5, -72, -1.5, -72, -1.5, -42, 1.5, -42 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "dish 2", shape = { -21, -84, 21, -84, 14, -75, -14, -75 }, color = { 0.72, 0.74, 0.77 }, layer = "detail", collide = false },
		{ name = "truss", shape = { -84, -9, 84, -9, 84, -4.5, -84, -4.5 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "truss", shape = { -84, 4.5, 84, 4.5, 84, 9, -84, 9 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "truss", shape = { -84, -4.5, -79.5, -4.5, -79.5, 4.5, -84, 4.5 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "truss", shape = { 79.5, -4.5, 84, -4.5, 84, 4.5, 79.5, 4.5 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "spar", shape = { -324, -2.25, -84, -2.25, -84, 2.25, -324, 2.25 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "spar", shape = { 84, -2.25, 324, -2.25, 324, 2.25, 84, 2.25 }, color = { 0.67, 0.69, 0.74 }, layer = "detail", collide = false },
		{ name = "panel", shape = { -324, -135, -270.75, -135, -270.75, -6, -324, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -324, 6, -270.75, 6, -270.75, 135, -324, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -261.75, -135, -208.5, -135, -208.5, -6, -261.75, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -261.75, 6, -208.5, 6, -208.5, 135, -261.75, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -199.5, -135, -146.25, -135, -146.25, -6, -199.5, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -199.5, 6, -146.25, 6, -146.25, 135, -199.5, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -137.25, -135, -84, -135, -84, -6, -137.25, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { -137.25, 6, -84, 6, -84, 135, -137.25, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 84, -135, 137.25, -135, 137.25, -6, 84, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 84, 6, 137.25, 6, 137.25, 135, 84, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 146.25, -135, 199.5, -135, 199.5, -6, 146.25, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 146.25, 6, 199.5, 6, 199.5, 135, 146.25, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 208.5, -135, 261.75, -135, 261.75, -6, 208.5, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 208.5, 6, 261.75, 6, 261.75, 135, 208.5, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 270.75, -135, 324, -135, 324, -6, 270.75, -6 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
		{ name = "panel", shape = { 270.75, 6, 324, 6, 324, 135, 270.75, 135 }, color = { 0.09, 0.14, 0.29 }, sensor = true, mass = 0.2 },
	},
}
