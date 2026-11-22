-- Made in the Shipyard (F2), Icons tab. Art for Missile M.
icon {
	id = "icon_missile_m", item = "missile_m",
	boxes = {   -- editable solids: x across, y depth, z up
		{ color = { 0.28, 0.36, 0.55 }, d = 1, h = 0.8, name = "crate", w = 3, x = 0, y = 0, z = 0 },
		{ color = { 0.28, 0.36, 0.55 }, d = 1.04, h = 0.84, hide = { side = true }, name = "band left", shade = 0.6, w = 0.2, x = 0.6, y = -0.02, z = -0.02, },
		{ color = { 0.28, 0.36, 0.55 }, d = 1.04, h = 0.84, hide = { side = true }, name = "band right", shade = 0.6, w = 0.2, x = 2.2, y = -0.02, z = -0.02, },
		{ d = 0.05, h = 0.3, light = 0.45, name = "stencil", shade = 1, w = 0.8, x = 1.1, y = -0.04, z = 0.25, },
	},
	boxView = { 14.178, 1.658, -0.377 },   -- art units per cell, centre x, y (Refit recomputes)
}
