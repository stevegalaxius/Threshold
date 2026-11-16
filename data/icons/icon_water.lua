-- Made in the Shipyard (F2), Icons tab. Art for Water tank: a steel barrel, shared with acids; a water drop floats on it in the hold.
icon {
	id = "icon_water", item = "water",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "drum", x = 0.15, y = 0, z = 0, w = 0.7, d = 0.7, h = 1.1, color = { 0.42, 0.44, 0.48 } },
		{ name = "hoop", x = 0.13, y = -0.02, z = 0.3, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "hoop", x = 0.13, y = -0.02, z = 0.75, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "rim", x = 0.13, y = -0.02, z = 1.04, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "bung", x = 0.62, y = 0.42, z = 1.1, w = 0.12, d = 0.12, h = 0.06, color = { 0.36, 0.37, 0.4 } },
		{ name = "vent", x = 0.3, y = 0.42, z = 1.1, w = 0.08, d = 0.08, h = 0.04, color = { 0.36, 0.37, 0.4 } },
	},
	parts = {
		{ name = "drop", shape = { 5, 2, 6.73, 4.9, 6.97, 5.55, 6.97, 6.25, 6.73, 6.9, 6.29, 7.43, 5.68, 7.78, 5, 7.9, 4.32, 7.78, 3.71, 7.43, 3.27, 6.9, 3.03, 6.25, 3.03, 5.55, 3.27, 4.9 }, color = { 0.4, 0.75, 1 }, badge = true },
		{ name = "drop shine", shape = { 4, 5.4, 4.5, 4.3, 4.7, 6.6 }, color = { 0.3, 0.55, 0.8 }, layer = "glow", badge = true },
	},
}
