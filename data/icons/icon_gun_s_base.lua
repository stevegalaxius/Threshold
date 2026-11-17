-- Made in the Shipyard (F2), Icons tab. Art for Gun S.
icon {
	id = "icon_gun_s_base", item = "gun_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.5, h = 0.55, material = "metal", name = "breech", primitive = "bevel", w = 0.8 },
		{ d = 0.3, h = 1.2, material = "metal", name = "barrel", primitive = "cylinder", ry = 90, w = 0.3, x = 0.8, y = 0.1, z = 0.42, },
		{ d = 0.35, h = 0.12, material = "recess", name = "muzzle", primitive = "ring", ry = 90, w = 0.35, x = 2, y = 0.075, z = 0.445, },
		{ d = 0.3, h = 0.3, material = "recess", name = "mount", primitive = "wedge", w = 0.5, x = 0.2, y = 0.1, z = -0.25, },
	},
	boxView = { 35.4471, 1.13954, -0.177 },   -- art units per cell, centre x, y (Refit recomputes)
}
