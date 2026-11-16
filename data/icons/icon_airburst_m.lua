-- Made in the Shipyard (F2), Icons tab. Art for airburst_m: a large ammo can with a fuse band.
icon {
	id = "icon_airburst_m", item = "airburst_m",
	paint = "Olive Drab",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "can", x = 0, y = 0, z = 0, w = 1, d = 0.55, h = 0.75 },
		{ name = "lid", x = -0.03, y = -0.03, z = 0.75, w = 1.06, d = 0.61, h = 0.1, light = 0.25 },
		{ name = "handle", x = 0.25, y = 0.215, z = 0.85, w = 0.5, d = 0.12, h = 0.04, shade = 0.6 },
		{ name = "latch", x = 1, y = 0.175, z = 0.5, w = 0.05, d = 0.2, h = 0.32, shade = 0.6 },
		{ name = "rib", x = 0, y = -0.02, z = 0.6, w = 1, d = 0.02, h = 0.04, shade = 0.6 },
		{ name = "fuse band", x = 0, y = -0.025, z = 0.35, w = 1, d = 0.02, h = 0.1, light = 0.45 },
		{ name = "stencil", x = 0.15, y = -0.03, z = 0.12, w = 0.35, d = 0.02, h = 0.18, light = 0.45 },
		{ name = "size mark", x = 0.6, y = -0.03, z = 0.12, w = 0.2, d = 0.02, h = 0.18, shade = 0.6 },
	},
	parts = {},
}
