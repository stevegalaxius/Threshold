container {
	id = "derelict_tug", name = "Derelict tug",
	armor = 260, hold = 16, mass = 140,
	parts = {
		{ name = "cabin", shape = { 46,-14, 46,14, 20,22, -30,22, -40,10, -40,-10, -30,-22, 20,-22 }, core = true },
		{ name = "cargo pod", shape = { 10,-38, 10,-22, -34,-22, -34,-38 }, cargo = true, mirror = true, shade = 0.8 },
		{ name = "engine", shape = { -40,-12, -40,12, -58,16, -58,-16 }, shade = 0.6 },
		{ name = "mast", shape = { 30,-3, 70,-1, 70,1, 30,3 }, collide = false, layer = "detail" },
	},
}
