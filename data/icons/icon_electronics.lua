-- Made in the Shipyard (F2), Icons tab. Art for Electronics: a circuit board with chips and a lit LED.
icon {
	id = "icon_electronics", item = "electronics",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "board", x = 0, y = 0, z = 0, w = 1, d = 0.85, h = 0.08, color = { 0.2, 0.55, 0.3 } },
		{ name = "chip", x = 0.1, y = 0.15, z = 0.08, w = 0.35, d = 0.3, h = 0.08, color = { 0.2, 0.2, 0.22 } },
		{ name = "chip", x = 0.55, y = 0.45, z = 0.08, w = 0.3, d = 0.25, h = 0.08, color = { 0.2, 0.2, 0.22 } },
		{ name = "capacitor", x = 0.6, y = 0.1, z = 0.08, w = 0.12, d = 0.12, h = 0.2, color = { 0.3, 0.45, 0.75 } },
		{ name = "trace", x = 0.1, y = 0.55, z = 0.08, w = 0.4, d = 0.05, h = 0.01, color = { 0.85, 0.7, 0.3 }, layer = "detail" },
		{ name = "led", x = 0.15, y = 0.7, z = 0.08, w = 0.08, d = 0.08, h = 0.06, color = { 0.3, 1, 0.4 }, layer = "glow" },
	},
	parts = {},
}
