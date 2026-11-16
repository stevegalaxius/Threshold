-- Made in the Shipyard (F2), Icons tab. Art for Fertilizer: a brown crate; a seedling in soil floats on it in the hold.
icon {
	id = "icon_fertilizer", item = "fertilizer",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 1, d = 0.6, h = 0.7, color = { 0.5, 0.4, 0.25 } },
		{ name = "lid", x = -0.03, y = -0.03, z = 0.7, w = 1.06, d = 0.66, h = 0.1, color = { 0.6, 0.48, 0.3 } },
		{ name = "handle", x = 0.3, y = 0.24, z = 0.8, w = 0.4, d = 0.12, h = 0.04, color = { 0.36, 0.37, 0.4 }, layer = "detail" },
	},
	parts = {
		{ name = "soil", shape = { 1.8, 8, 2.6, 6.6, 5, 6, 7.4, 6.6, 8.2, 8 }, color = { 0.65, 0.45, 0.25 }, badge = true },
		{ name = "stem", shape = { 4.7, 3.8, 5.3, 3.8, 5.3, 6.4, 4.7, 6.4 }, color = { 0.5, 0.9, 0.3 }, badge = true },
		{ name = "leaf", shape = { 5, 4.2, 3.8, 2.4, 2, 2.2, 2.8, 4 }, color = { 0.5, 0.9, 0.3 }, badge = true },
		{ name = "leaf", shape = { 5, 4.8, 6.2, 3, 8, 3.2, 7, 4.8 }, color = { 0.5, 0.9, 0.3 }, badge = true },
	},
}
