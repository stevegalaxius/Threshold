-- Made in the Shipyard (F2), Icons tab. Art for gun_l_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_l_base", item = "gun_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.37 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.096, w = 3, d = 0.01, h = 0.11, shade = 0.55, layer = "detail" },
	},
	boxView = { 49.859, 1.595, -0.471 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -72.021, 15.233, -28.644, 15.233, -19.669, 12.227, -19.669, -5.81, -72.021, -5.81 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print upper barrel", shape = { -19.669, 2.457, 50.632, 2.457, 50.632, -2.052, -19.669, -2.052 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print lower barrel", shape = { -19.669, 10.724, 50.632, 10.724, 50.632, 6.215, -19.669, 6.215 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 50.632, 12.227, 59.606, 12.227, 59.606, -3.555, 50.632, -3.555 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print mount", shape = { -60.055, 15.233, -34.627, 15.233, -39.114, 21.245, -55.568, 21.245 }, color = { 0.95, 0.95, 0.9 } },
	},
}
