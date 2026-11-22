-- Made in the Shipyard (F2), Icons tab. Art for Torpedo M.
icon {
	id = "icon_torp_m", item = "torp_m",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.75, name = "crate", w = 2.5, x = 0.25, y = 0, z = 0 },
		{
			d = 1.04,
			h = 0.79,
			hide = { side = true },
			name = "band",
			shade = 0.6,
			w = 0.15,
			x = 0.925,
			y = -0.02,
			z = -0.02,
		},
		{
			d = 1.04,
			h = 0.79,
			hide = { side = true },
			name = "band",
			shade = 0.6,
			w = 0.15,
			x = 1.925,
			y = -0.02,
			z = -0.02,
		},
		{
			d = 1.08,
			h = 0.83,
			hide = { side = true },
			name = "end cap left",
			shade = 0.6,
			w = 0.3,
			x = 0,
			y = -0.04,
			z = -0.04,
		},
		{ d = 1.08, h = 0.83, name = "end cap right", shade = 0.6, w = 0.3, x = 2.7, y = -0.04, z = -0.04 },
		{ d = 0.02, h = 0.25, light = 0.45, name = "stencil", w = 0.5, x = 1.15, y = -0.04, z = 0.25 },
	},
	boxView = { 14.071, 1.658, -0.364 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
	},
}
