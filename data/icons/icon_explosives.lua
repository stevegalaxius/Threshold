-- Made in the Shipyard (F2), Icons tab. Art for Explosives: a red crate with a hazard band; a lit dynamite bundle floats on it in the hold.
icon {
	id = "icon_explosives", item = "explosives",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 1, d = 0.6, h = 0.7, color = { 0.7, 0.2, 0.15 } },
		{ name = "lid", x = -0.03, y = -0.03, z = 0.7, w = 1.06, d = 0.66, h = 0.1, color = { 0.8, 0.28, 0.2 } },
		{ name = "handle", x = 0.3, y = 0.24, z = 0.8, w = 0.4, d = 0.12, h = 0.04, color = { 0.36, 0.37, 0.4 }, layer = "detail" },
		{ name = "band", x = 0, y = -0.01, z = 0.3, w = 1, d = 0.01, h = 0.12, color = { 0.95, 0.8, 0.2 }, layer = "detail" },
	},
	parts = {
		{ name = "stick", shape = { 2.4, 4, 4.1, 4, 4.1, 8.4, 2.4, 8.4 }, color = { 0.9, 0.3, 0.25 }, badge = true },
		{ name = "stick", shape = { 5.9, 4, 7.6, 4, 7.6, 8.4, 5.9, 8.4 }, color = { 0.9, 0.3, 0.25 }, badge = true },
		{ name = "stick", shape = { 4.15, 3.6, 5.85, 3.6, 5.85, 8.2, 4.15, 8.2 }, color = { 0.95, 0.35, 0.28 }, badge = true },
		{ name = "tape", shape = { 2.4, 6.1, 7.6, 6.1, 7.6, 6.8, 2.4, 6.8 }, color = { 0.6, 0.6, 0.62 }, layer = "detail", badge = true },
		{ name = "fuse", shape = { 4.8, 3.6, 5.2, 3.6, 6, 2.2, 5.6, 2 }, color = { 0.7, 0.65, 0.55 }, badge = true },
		{ name = "spark", shape = { 5.8, 0.8, 6.2, 1.7, 7, 1.9, 6.3, 2.4, 6.4, 3.2, 5.8, 2.6, 5, 2.8, 5.4, 2 }, color = { 1, 0.75, 0.3 }, layer = "glow", badge = true },
	},
}
