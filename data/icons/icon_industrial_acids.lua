-- Made in the Shipyard (F2), Icons tab. Art for Industrial acids: a steel barrel, shared with water; a bubbling flask floats on it in the hold.
icon {
	id = "icon_industrial_acids", item = "industrial_acids",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "drum", x = 0.15, y = 0, z = 0, w = 0.7, d = 0.7, h = 1.1, color = { 0.42, 0.44, 0.48 } },
		{ name = "hoop", x = 0.13, y = -0.02, z = 0.3, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "hoop", x = 0.13, y = -0.02, z = 0.75, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "rim", x = 0.13, y = -0.02, z = 1.04, w = 0.74, d = 0.74, h = 0.06, color = { 0.62, 0.62, 0.64 } },
		{ name = "bung", x = 0.62, y = 0.42, z = 1.1, w = 0.12, d = 0.12, h = 0.06, color = { 0.36, 0.37, 0.4 } },
		{ name = "vent", x = 0.3, y = 0.42, z = 1.1, w = 0.08, d = 0.08, h = 0.04, color = { 0.36, 0.37, 0.4 } },
	},
	parts = {
		{ name = "flask", shape = { 4.3, 1.8, 5.7, 1.8, 5.7, 3.7, 6.2, 3.82, 6.84, 4.36, 7.26, 5.08, 7.4, 5.9, 7.26, 6.72, 6.84, 7.44, 6.2, 7.98, 5.42, 8.26, 4.58, 8.26, 3.8, 7.98, 3.16, 7.44, 2.74, 6.72, 2.6, 5.9, 2.74, 5.08, 3.16, 4.36, 3.8, 3.82, 4.3, 3.7 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "acid", shape = { 7.4, 5.9, 7.26, 6.72, 6.84, 7.44, 6.2, 7.98, 5.42, 8.26, 4.58, 8.26, 3.8, 7.98, 3.16, 7.44, 2.74, 6.72, 2.6, 5.9 }, color = { 0.55, 0.85, 0.1 }, layer = "glow", badge = true },
		{ name = "bubble", shape = { 6, 4.4, 5.85, 4.75, 5.5, 4.9, 5.15, 4.75, 5, 4.4, 5.15, 4.05, 5.5, 3.9, 5.85, 4.05 }, color = { 0.45, 0.7, 0.1 }, layer = "glow", badge = true },
		{ name = "fume", shape = { 6.8, 0.6, 6.62, 1.02, 6.2, 1.2, 5.78, 1.02, 5.6, 0.6, 5.78, 0.18, 6.2, 0, 6.62, 0.18 }, color = { 0.35, 0.55, 0.1 }, layer = "glow", badge = true },
	},
}
