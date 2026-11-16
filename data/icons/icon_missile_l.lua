-- Made in the Shipyard (F2), Icons tab. Art for missile_l: a heavy capped crate.
icon {
	id = "icon_missile_l", item = "missile_l",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 3, d = 1, h = 0.9 },
		{ name = "band", x = 0.9, y = -0.02, z = -0.02, w = 0.2, d = 1.04, h = 0.94, shade = 0.6 },
		{ name = "band", x = 1.9, y = -0.02, z = -0.02, w = 0.2, d = 1.04, h = 0.94, shade = 0.6 },
		{ name = "end cap left", x = -0.04, y = -0.04, z = -0.04, w = 0.2, d = 1.08, h = 0.98, shade = 0.6 },
		{ name = "end cap right", x = 2.84, y = -0.04, z = -0.04, w = 0.2, d = 1.08, h = 0.98, shade = 0.6 },
		{ name = "stencil", x = 1.1, y = -0.04, z = 0.27, w = 0.8, d = 0.02, h = 0.342, light = 0.45 },
	},
	parts = {},
}
