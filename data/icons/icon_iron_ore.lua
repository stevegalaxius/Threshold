-- Made in the Shipyard (F2), Icons tab. Art for Iron ore.
icon {
	id = "icon_iron_ore", item = "iron_ore",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.55, 0.36, 0.23 }, d = 0.8, h = 0.65, material = "metal", name = "ore", primitive = "rock", w = 1, },
		{ color = { 0.72, 0.42, 0.19 }, d = 0.24, h = 0.28, material = "crystal", name = "mineral facet", primitive = "rock", w = 0.3, x = 0.4, y = 0.3, z = 0.25, },
	},
	boxView = { 17.3585, 0.666679, -0.311328 },   -- art units per cell, centre x, y (Refit recomputes)
}
