-- Made in the Shipyard (F2), Icons tab. Art for Explosives: a red charge crate with a warning lamp.
icon {
	id = "icon_explosives", item = "explosives",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 1, d = 0.8, h = 0.55, color = { 0.75, 0.2, 0.15 } },
		{ name = "stripe", x = -0.01, y = -0.02, z = 0.2, w = 1.02, d = 0.02, h = 0.1, color = { 0.95, 0.8, 0.2 } },
		{ name = "lid", x = 0, y = 0, z = 0.55, w = 1, d = 0.8, h = 0.05, color = { 0.6, 0.15, 0.12 } },
		{ name = "lamp", x = 0.45, y = 0.35, z = 0.6, w = 0.12, d = 0.12, h = 0.08, color = { 1, 0.5, 0.15 }, layer = "glow" },
	},
	parts = {},
}
