-- Made in the Shipyard (F2), Icons tab. Art for Missile L.
icon {
	id = "icon_missile_l", item = "missile_l",
	w = 4, h = 1,   -- the item's grid size (cells); also its size in space
	boxes = {   -- editable solids: x across, y depth, z up
		{ color = { 0.28, 0.36, 0.55 }, d = 1, h = 0.9, name = "crate", w = 4, x = -0.5, y = 0, z = 0 },
		{ color = { 0.28, 0.36, 0.55 }, d = 1.08, h = 0.98, hide = { side = true }, name = "end cap left", shade = 0.6, w = 0.2, x = -0.04, y = -0.04, z = -0.04, },
		{ color = { 0.28, 0.36, 0.55 }, d = 1.08, h = 0.98, hide = { side = true }, name = "end cap right", shade = 0.6, w = 0.2, x = 2.84, y = -0.04, z = -0.04, },
		{ d = 0.05, h = 0.342, light = 0.45, name = "stencil", w = 0.8, x = 1.1, y = -0.04, z = 0.27 },
	},
	boxView = { 13.742, 1.658, -0.405 },   -- art units per cell, centre x, y (Refit recomputes)
}
