-- Made in the Shipyard (F2), Icons tab. Art for gun_s_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_s_base", item = "gun_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.932 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.545, w = 3, d = 0.01, h = 0.155, shade = 0.55, layer = "detail" },
	},
	boxView = { 24.773, 1.595, -0.626 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print magazine", shape = { -21.109, 5.447, -15.244, 5.447, -16.417, 13.658, -21.696, 13.658 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print receiver", shape = { -31.667, 3.1, -29.321, 6.033, -8.206, 6.033, -5.86, 3.687, -5.86, -3.351, -9.379, -5.697, -26.975, -5.697, -31.667, -2.178 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print top rail", shape = { -26.975, -5.697, -11.725, -5.697, -11.725, -6.87, -26.975, -6.87 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print ejection port", shape = { -16.417, 0.754, -10.552, 0.754, -10.552, -2.178, -16.417, -2.178 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print panel line", shape = { -23.456, 6.033, -22.869, 6.033, -22.869, -5.697, -23.456, -5.697 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print ready lamp", shape = { -28.734, -0.419, -26.975, -0.419, -26.975, -2.178, -28.734, -2.178 }, color = { 1, 0.75, 0.3 }, layer = "glow" },
		{ name = "print barrel", shape = { 0.005, 2.279, 22.293, 1.869, 22.293, -0.36, 0.005, -0.771 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print shroud", shape = { -4.394, 4.274, -1.461, 4.274, 0.005, 2.807, 0.005, -1.885, -1.461, -3.351, -4.394, -3.351, -5.86, -1.885, -5.86, 2.807 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print cooling slot", shape = { -4.101, 2.807, -2.928, 2.807, -2.928, -1.885, -4.101, -1.885 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print cooling slot", shape = { -1.168, 2.807, 0.005, 2.807, 0.005, -1.885, -1.168, -1.885 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print muzzle brake", shape = { 22.41, 3.394, 26.281, 3.394, 26.985, 2.69, 26.985, -1.181, 26.281, -1.885, 22.41, -1.885, 21.706, -1.181, 21.706, 2.69 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print brake slot", shape = { 23.466, 2.514, 24.345, 2.514, 24.345, -1.005, 23.466, -1.005 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
	},
}
