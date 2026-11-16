-- Made in the Shipyard (F2), Icons tab. Art for Industrial acids: a steel barrel, shared with water; a bubbling flask floats on it in the hold.
icon {
	id = "icon_industrial_acids", item = "industrial_acids",
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
		{ name = "flask", shape = { 4.3, 1.8, 5.7, 1.8, 5.7, 3.7, 6.2, 3.82, 6.84, 4.36, 7.26, 5.08, 7.4, 5.9, 7.26, 6.72, 6.84, 7.44, 6.2, 7.98, 5.42, 8.26, 4.58, 8.26, 3.8, 7.98, 3.16, 7.44, 2.74, 6.72, 2.6, 5.9, 2.74, 5.08, 3.16, 4.36, 3.8, 3.82, 4.3, 3.7 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "acid", shape = { 7.4, 5.9, 7.26, 6.72, 6.84, 7.44, 6.2, 7.98, 5.42, 8.26, 4.58, 8.26, 3.8, 7.98, 3.16, 7.44, 2.74, 6.72, 2.6, 5.9 }, color = { 0.55, 0.85, 0.1 }, layer = "glow", badge = true },
		{ name = "bubble", shape = { 6, 4.4, 5.85, 4.75, 5.5, 4.9, 5.15, 4.75, 5, 4.4, 5.15, 4.05, 5.5, 3.9, 5.85, 4.05 }, color = { 0.45, 0.7, 0.1 }, layer = "glow", badge = true },
		{ name = "fume", shape = { 6.8, 0.6, 6.62, 1.02, 6.2, 1.2, 5.78, 1.02, 5.6, 0.6, 5.78, 0.18, 6.2, 0, 6.62, 0.18 }, color = { 0.35, 0.55, 0.1 }, layer = "glow", badge = true },
	},
}
