-- Made in the Shipyard (F2), Icons tab. Art for gun_l_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_l_base", item = "gun_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.37 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.096, w = 3, d = 0.01, h = 0.11, shade = 0.55, layer = "detail" },
	},
	boxView = { 49.859, 1.595, -0.471 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print mount", shape = { -40.239, 11.1, -18.922, 11.1, -22.475, 20.87, -36.686, 20.87 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print receiver", shape = { -49.12, 6.659, -45.568, 11.1, -13.593, 11.1, -10.041, 7.547, -10.041, -3.111, -15.37, -6.664, -42.015, -6.664, -49.12, -1.335 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print top rail", shape = { -42.015, -6.664, -18.922, -6.664, -18.922, -8.44, -42.015, -8.44 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print ejection port", shape = { -26.028, 3.106, -17.146, 3.106, -17.146, -1.335, -26.028, -1.335 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print panel line", shape = { -36.686, 11.1, -35.798, 11.1, -35.798, -6.664, -36.686, -6.664 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print ready lamp", shape = { -44.68, 1.33, -42.015, 1.33, -42.015, -1.335, -44.68, -1.335 }, color = { 1, 0.75, 0.3 }, layer = "glow" },
		{ name = "print barrel", shape = { 2.394, 1.241, 33.48, 0.708, 33.48, -2.489, 2.394, -3.022 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print barrel", shape = { 2.394, 9.235, 33.48, 8.702, 33.48, 5.504, 2.394, 4.971 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print shroud", shape = { -7.376, 10.212, 3.282, 10.212, 5.946, 7.547, 5.946, -2.223, 3.282, -4.887, -7.376, -4.887, -10.041, -2.223, -10.041, 7.547 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print cooling slot", shape = { -7.376, 7.547, -5.6, 7.547, -5.6, -2.223, -7.376, -2.223 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print cooling slot", shape = { -2.935, 7.547, -1.159, 7.547, -1.159, -2.223, -2.935, -2.223 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print cooling slot", shape = { 1.506, 7.547, 3.282, 7.547, 3.282, -2.223, 1.506, -2.223 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print muzzle brake", shape = { 33.924, 10.212, 38.365, 10.212, 39.697, 8.879, 39.697, -2.667, 38.365, -3.999, 33.924, -3.999, 32.592, -2.667, 32.592, 8.879 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print brake slot", shape = { 34.812, 8.435, 36.144, 8.435, 36.144, -2.223, 34.812, -2.223 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
	},
}
