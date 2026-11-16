-- Made in the Shipyard (F2), Icons tab. Art for torp_m: a sealed crate.
icon {
	id = "icon_torp_m", item = "torp_m",
	paint = "Tanker",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0.25, y = 0, z = 0, w = 2.5, d = 1, h = 0.75 },
		{ name = "band", x = 0.925, y = -0.02, z = -0.02, w = 0.15, d = 1.04, h = 0.79, shade = 0.6 },
		{ name = "band", x = 1.925, y = -0.02, z = -0.02, w = 0.15, d = 1.04, h = 0.79, shade = 0.6 },
		{ name = "lid seam", x = 0.3, y = 0.47, z = 0.75, w = 2.4, d = 0.06, h = 0.01, light = 0.45 },
		{ name = "end cap left", x = 0, y = -0.04, z = -0.04, w = 0.3, d = 1.08, h = 0.83, shade = 0.6 },
		{ name = "end cap right", x = 2.7, y = -0.04, z = -0.04, w = 0.3, d = 1.08, h = 0.83, shade = 0.6 },
		{ name = "stencil", x = 1.15, y = -0.04, z = 0.25, w = 0.5, d = 0.02, h = 0.25, light = 0.45 },
		{ name = "arrow", x = 1.75, y = -0.04, z = 0.32, w = 0.6, d = 0.02, h = 0.1, light = 0.45 },
	},
	parts = {},
}
