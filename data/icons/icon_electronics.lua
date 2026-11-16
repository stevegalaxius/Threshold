-- Made in the Shipyard (F2), Icons tab. Art for Electronics: a green crate; a microchip floats on it in the hold.
icon {
	id = "icon_electronics", item = "electronics",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 1, d = 0.6, h = 0.7, color = { 0.25, 0.5, 0.35 } },
		{ name = "lid", x = -0.03, y = -0.03, z = 0.7, w = 1.06, d = 0.66, h = 0.1, color = { 0.3, 0.6, 0.42 } },
		{ name = "handle", x = 0.3, y = 0.24, z = 0.8, w = 0.4, d = 0.12, h = 0.04, color = { 0.36, 0.37, 0.4 } },
		{ name = "skid", x = 0.08, y = -0.02, z = -0.02, w = 0.84, d = 0.04, h = 0.08, color = { 0.36, 0.37, 0.4 } },
	},
	parts = {
		{ name = "pin", shape = { 3.4, 1.8, 4, 1.8, 4, 2.8, 3.4, 2.8 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 3.4, 7.2, 4, 7.2, 4, 8.2, 3.4, 8.2 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 1.8, 3.4, 2.8, 3.4, 2.8, 4, 1.8, 4 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 7.2, 3.4, 8.2, 3.4, 8.2, 4, 7.2, 4 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 4.7, 1.8, 5.3, 1.8, 5.3, 2.8, 4.7, 2.8 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 4.7, 7.2, 5.3, 7.2, 5.3, 8.2, 4.7, 8.2 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 1.8, 4.7, 2.8, 4.7, 2.8, 5.3, 1.8, 5.3 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 7.2, 4.7, 8.2, 4.7, 8.2, 5.3, 7.2, 5.3 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 6, 1.8, 6.6, 1.8, 6.6, 2.8, 6, 2.8 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 6, 7.2, 6.6, 7.2, 6.6, 8.2, 6, 8.2 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 1.8, 6, 2.8, 6, 2.8, 6.6, 1.8, 6.6 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "pin", shape = { 7.2, 6, 8.2, 6, 8.2, 6.6, 7.2, 6.6 }, color = { 0.75, 0.75, 0.8 }, badge = true },
		{ name = "chip", shape = { 2.8, 2.8, 7.2, 2.8, 7.2, 7.2, 2.8, 7.2 }, color = { 0.55, 0.58, 0.62 }, badge = true },
		{ name = "dot", shape = { 4.2, 3.8, 4.08, 4.08, 3.8, 4.2, 3.52, 4.08, 3.4, 3.8, 3.52, 3.52, 3.8, 3.4, 4.08, 3.52 }, color = { 0.4, 0.95, 0.55 }, layer = "glow", badge = true },
	},
}
