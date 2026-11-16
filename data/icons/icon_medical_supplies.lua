-- Made in the Shipyard (F2), Icons tab. Art for Medical supplies: a white climate case with a red cross and status light.
icon {
	id = "icon_medical_supplies", item = "medical_supplies",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "case", x = 0, y = 0, z = 0, w = 1, d = 0.6, h = 0.6, color = { 0.92, 0.93, 0.9 } },
		{ name = "lid", x = -0.02, y = -0.02, z = 0.6, w = 1.04, d = 0.64, h = 0.08, color = { 0.8, 0.82, 0.85 } },
		{ name = "cross bar", x = 0.3, y = -0.03, z = 0.25, w = 0.4, d = 0.02, h = 0.12, color = { 0.85, 0.2, 0.2 } },
		{ name = "cross post", x = 0.44, y = -0.03, z = 0.11, w = 0.12, d = 0.02, h = 0.4, color = { 0.85, 0.2, 0.2 } },
		{ name = "cold light", x = 0.82, y = -0.03, z = 0.45, w = 0.08, d = 0.02, h = 0.08, color = { 0.4, 0.8, 1 }, layer = "glow" },
	},
	parts = {},
}
