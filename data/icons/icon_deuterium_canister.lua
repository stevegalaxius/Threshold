-- Made in the Shipyard (F2), Icons tab. Art for Deuterium canister.
icon {
	id = "icon_deuterium_canister", item = "deuterium_canister",
	boxes = {   -- editable solids: x across, y depth, z up
		{ d = 0.7, glow = 0.7, h = 1.1, material = "crystal", name = "tank", primitive = "cylinder", w = 0.7, },
		{ d = 0.76, h = 0.1, material = "metal", name = "lower rim", primitive = "ring", w = 0.76, x = -0.028, y = -0.03, z = -0.03, },
		{ color = { 0.9, 0.5, 0.12 }, d = 0.4, h = 0.12, material = "painted", name = "valve", primitive = "bevel", w = 0.4, x = 0.107, y = 0.2, z = 1.137, },
		{ d = 0.76, h = 0.1, inner = 0.27, material = "metal", name = "lower rim copy", primitive = "ring", w = 0.76, x = -0.039, y = -0.03, z = 1.07, },
	},
	boxView = { 16.5548, 0.456412, -0.427123 },   -- art units per cell, centre x, y (Refit recomputes)
}
