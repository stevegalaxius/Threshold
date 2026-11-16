-- Made in the Shipyard (F2), Icons tab. Art for gun_m_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_m_base", item = "gun_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.072 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.857, w = 3, d = 0.01, h = 0.086, shade = 0.55, layer = "detail" },
	},
	boxView = { 39.824, 1.595, -0.389 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print drum", shape = { -16.655, 9.667, -17.081, 7.803, -18.273, 6.308, -19.996, 5.478, -21.909, 5.478, -23.632, 6.308, -24.824, 7.803, -25.25, 9.667, -24.824, 11.532, -23.632, 13.027, -21.909, 13.857, -19.996, 13.857, -18.273, 13.027, -17.081, 11.532 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print receiver", shape = { -34.458, 5.984, -32.003, 9.053, -9.902, 9.053, -7.447, 6.598, -7.447, -0.769, -11.13, -3.224, -29.547, -3.224, -34.458, 0.459 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print top rail", shape = { -29.547, -3.224, -13.586, -3.224, -13.586, -4.452, -29.547, -4.452 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print ejection port", shape = { -18.497, 3.528, -12.358, 3.528, -12.358, 0.459, -18.497, 0.459 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print panel line", shape = { -25.864, 9.053, -25.25, 9.053, -25.25, -3.224, -25.864, -3.224 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print ready lamp", shape = { -31.389, 2.301, -29.547, 2.301, -29.547, 0.459, -31.389, 0.459 }, color = { 1, 0.75, 0.3 }, layer = "glow" },
		{ name = "print barrel", shape = { 3.603, 5.125, 22.02, 4.695, 22.02, 2.362, 3.603, 1.932 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print shroud", shape = { -5.912, 7.212, 2.069, 7.212, 3.603, 5.677, 3.603, 0.766, 2.069, -0.769, -5.912, -0.769, -7.447, 0.766, -7.447, 5.677 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print cooling slot", shape = { -5.605, 5.677, -4.377, 5.677, -4.377, 0.766, -5.605, 0.766 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print cooling slot", shape = { -2.536, 5.677, -1.308, 5.677, -1.308, 0.766, -2.536, 0.766 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print cooling slot", shape = { 0.534, 5.677, 1.762, 5.677, 1.762, 0.766, 0.534, 0.766 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print muzzle brake", shape = { 22.143, 6.291, 26.195, 6.291, 26.931, 5.554, 26.931, 1.503, 26.195, 0.766, 22.143, 0.766, 21.406, 1.503, 21.406, 5.554 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print brake slot", shape = { 23.248, 5.37, 24.169, 5.37, 24.169, 1.687, 23.248, 1.687 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
	},
}
