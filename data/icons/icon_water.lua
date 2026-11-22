-- Made in the Shipyard (F2), Icons tab. Art for Water tank.
icon {
	id = "icon_water", item = "water",
	w = 1, h = 2,   -- the item's grid size (cells); also its size in space
	boxes = {   -- editable solids: x across, y depth, z up
		{ color = { 0.42, 0.44, 0.48 }, d = 0.6, h = 1.66, material = "painted", name = "drum", primitive = "box", w = 0.6, x = 0.2, y = 0, z = 0, },
		{ color = { 0.62, 0.64, 0.68 }, d = 0.65, h = 0.07, material = "painted", name = "hoop", primitive = "box", w = 0.62, x = 0.186, y = -0.01, z = 1.081, },
		{ color = { 0.62, 0.64, 0.68 }, d = 0.1, h = 0.05, material = "painted", name = "bung", primitive = "box", w = 0.1, x = 0.6, y = 0.38, z = 1.66, },
		{ color = { 0.62, 0.64, 0.68 }, d = 0.65, h = 0.07, material = "painted", name = "hoop copy", primitive = "box", w = 0.62, x = 0.189, y = -0.01, z = 0.447, },
	},
	boxView = { 18.1288, 0.596406, -0.551 },   -- art units per cell, centre x, y (Refit recomputes)
}
