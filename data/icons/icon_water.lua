-- Made in the Shipyard (F2), Icons tab. Art for Water tank: a steel barrel, shared with acids; a water drop floats on it in the hold.
icon {
	id = "icon_water", item = "water",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "drum", x = 0.2, y = 0, z = 0, w = 0.6, d = 0.6, h = 1.66, color = { 0.42, 0.44, 0.48 } },
		{ name = "hoop", x = 0.2, y = -0.01, z = 0.52, w = 0.6, d = 0.01, h = 0.07, color = { 0.62, 0.64, 0.68 }, layer = "detail" },
		{ name = "hoop", x = 0.2, y = -0.01, z = 1.08, w = 0.6, d = 0.01, h = 0.07, color = { 0.62, 0.64, 0.68 }, layer = "detail" },
		{ name = "sheen", x = 0.3, y = -0.01, z = 0.1, w = 0.08, d = 0.01, h = 1.46, color = { 0.14, 0.15, 0.17 }, layer = "glow" },
		{ name = "bung", x = 0.6, y = 0.38, z = 1.66, w = 0.1, d = 0.1, h = 0.05, color = { 0.62, 0.64, 0.68 }, layer = "detail" },
	},
	parts = {
		{ name = "drop", shape = { 5, 2, 6.73, 4.9, 6.97, 5.55, 6.97, 6.25, 6.73, 6.9, 6.29, 7.43, 5.68, 7.78, 5, 7.9, 4.32, 7.78, 3.71, 7.43, 3.27, 6.9, 3.03, 6.25, 3.03, 5.55, 3.27, 4.9 }, color = { 0.4, 0.75, 1 }, badge = true },
		{ name = "drop shine", shape = { 4, 5.4, 4.5, 4.3, 4.7, 6.6 }, color = { 0.3, 0.55, 0.8 }, layer = "glow", badge = true },
	},
}
