-- Made in the Shipyard (F2), Icons tab. Art for missile_l_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_l_base", item = "missile_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.37 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.096, w = 3, d = 0.01, h = 0.11, shade = 0.55, layer = "detail" },
	},
	boxView = { 49.859, 1.595, -0.471 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -67.534, 19.517, -58.559, 19.517, -34.627, 11.851, -34.627, -0.925, -58.559, -8.59, -67.534, -8.59 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -61.551, 11.851, 25.204, 11.851, 49.136, 5.463, 25.204, -0.925, -61.551, -0.925 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -4.712, 11.851, 1.271, 11.851, 1.271, -0.925, -4.712, -0.925 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 25.204, 11.851, 49.136, 5.463, 25.204, -0.925 }, color = { 1, 0.4, 0.3 } },
	},
}
