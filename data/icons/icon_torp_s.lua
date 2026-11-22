-- Made in the Shipyard (F2), Icons tab. Art for Torpedo S.
icon {
	id = "icon_torp_s", item = "torp_s",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.75, name = "crate", w = 1.5, x = 0.25, y = 0, z = 0 },
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
		{ d = 1.08, h = 0.83, name = "end cap right", shade = 0.6, w = 0.3, x = 1.7, y = -0.04, z = -0.04 },
		{ d = 0.05, h = 0.25, light = 0.45, name = "stencil", w = 0.4, x = 0.45, y = -0.04, z = 0.25 },
	},
	boxView = { 13.247, 1.158, -0.364 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
	},
}
