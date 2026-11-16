-- Made in the Shipyard (F2), Icons tab. Art for Water tank: a steel barrel, shared with acids; a water drop floats on it in the hold.
icon {
	id = "icon_water", item = "water",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "chime", x = 0.24, y = 0.04, z = 0, w = 0.52, d = 0.52, h = 0.08, color = { 0.36, 0.37, 0.4 } },
		{ name = "lower body", x = 0.2, y = 0, z = 0.08, w = 0.6, d = 0.6, h = 0.42, color = { 0.42, 0.44, 0.48 } },
		{ name = "rolling hoop", x = 0.17, y = -0.03, z = 0.5, w = 0.66, d = 0.66, h = 0.08, color = { 0.55, 0.57, 0.62 } },
		{ name = "middle body", x = 0.19, y = -0.01, z = 0.58, w = 0.62, d = 0.62, h = 0.5, color = { 0.42, 0.44, 0.48 } },
		{ name = "rolling hoop", x = 0.17, y = -0.03, z = 1.08, w = 0.66, d = 0.66, h = 0.08, color = { 0.55, 0.57, 0.62 } },
		{ name = "upper body", x = 0.2, y = 0, z = 1.16, w = 0.6, d = 0.6, h = 0.42, color = { 0.42, 0.44, 0.48 } },
		{ name = "top chime", x = 0.22, y = 0.02, z = 1.58, w = 0.56, d = 0.56, h = 0.08, color = { 0.55, 0.57, 0.62 } },
		{ name = "bung", x = 0.6, y = 0.38, z = 1.66, w = 0.1, d = 0.1, h = 0.05, color = { 0.36, 0.37, 0.4 } },
		{ name = "vent", x = 0.3, y = 0.38, z = 1.66, w = 0.07, d = 0.07, h = 0.04, color = { 0.36, 0.37, 0.4 } },
		{ name = "sheen", x = 0.3, y = -0.02, z = 0.1, w = 0.08, d = 0.01, h = 0.38, color = { 0.18, 0.19, 0.21 }, layer = "glow" },
		{ name = "shade", x = 0.68, y = -0.02, z = 0.1, w = 0.12, d = 0.01, h = 0.38, color = { 0.3, 0.31, 0.34 }, layer = "detail" },
		{ name = "sheen", x = 0.3, y = -0.02, z = 0.6, w = 0.08, d = 0.01, h = 0.46, color = { 0.18, 0.19, 0.21 }, layer = "glow" },
		{ name = "shade", x = 0.68, y = -0.02, z = 0.6, w = 0.12, d = 0.01, h = 0.46, color = { 0.3, 0.31, 0.34 }, layer = "detail" },
		{ name = "sheen", x = 0.3, y = -0.02, z = 1.18, w = 0.08, d = 0.01, h = 0.38, color = { 0.18, 0.19, 0.21 }, layer = "glow" },
		{ name = "shade", x = 0.68, y = -0.02, z = 1.18, w = 0.12, d = 0.01, h = 0.38, color = { 0.3, 0.31, 0.34 }, layer = "detail" },
	},
	parts = {
		{ name = "drop", shape = { 5, 2, 6.73, 4.9, 6.97, 5.55, 6.97, 6.25, 6.73, 6.9, 6.29, 7.43, 5.68, 7.78, 5, 7.9, 4.32, 7.78, 3.71, 7.43, 3.27, 6.9, 3.03, 6.25, 3.03, 5.55, 3.27, 4.9 }, color = { 0.4, 0.75, 1 }, badge = true },
		{ name = "drop shine", shape = { 4, 5.4, 4.5, 4.3, 4.7, 6.6 }, color = { 0.3, 0.55, 0.8 }, layer = "glow", badge = true },
	},
}
