-- Made in the Shipyard (F2), Icons tab. Art for Gold ore.
icon {
	id = "icon_gold_ore", item = "gold_ore",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.43, 0.29, 0.17 }, d = 0.8, h = 0.8, material = "painted", name = "ore", primitive = "rock", w = 1, },
		{ color = { 1, 0.7, 0.2 }, d = 0.4, h = 0.45, material = "metal", name = "gold seam", primitive = "rock", w = 0.4, x = 0.2, y = -0.05, z = 0.3, },
	},
	boxView = { 17.3585, 0.666679, -0.364953 },   -- art units per cell, centre x, y (Refit recomputes)
}
