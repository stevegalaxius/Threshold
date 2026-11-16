-- Made in the Shipyard (F2), Icons tab. Art for shot_l: a long scatter shell crate.
icon {
	id = "icon_shot_l", item = "shot_l",
	paint = "Taupe",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 2, d = 1, h = 0.7 },
		{ name = "lid seam", x = 0.05, y = 0.33, z = 0.7, w = 1.9, d = 0.04, h = 0.01, shade = 0.6 },
		{ name = "lid seam", x = 0.05, y = 0.66, z = 0.7, w = 1.9, d = 0.04, h = 0.01, shade = 0.6 },
		{ name = "rope end left", x = -0.06, y = 0.3, z = 0.25, w = 0.06, d = 0.4, h = 0.12, light = 0.45 },
		{ name = "rope end right", x = 2, y = 0.3, z = 0.25, w = 0.06, d = 0.4, h = 0.12, light = 0.45 },
		{ name = "skid", x = 0.1, y = -0.02, z = -0.02, w = 1.8, d = 0.04, h = 0.1, shade = 0.6 },
		{ name = "dot", x = 0.2, y = -0.03, z = 0.28, w = 0.12, d = 0.02, h = 0.12, light = 0.45 },
		{ name = "dot", x = 0.64, y = -0.03, z = 0.28, w = 0.12, d = 0.02, h = 0.12, light = 0.45 },
		{ name = "dot", x = 1.08, y = -0.03, z = 0.28, w = 0.12, d = 0.02, h = 0.12, light = 0.45 },
	},
	parts = {},
}
