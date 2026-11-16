-- Made in the Shipyard (F2), Icons tab. Art for missile_s_base: its retail box (front left blank to draw on).
icon {
	id = "icon_missile_s_base", item = "missile_s_base",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 5.455 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 4.364, w = 3, d = 0.01, h = 0.436, shade = 0.55, layer = "detail" },
	},
	parts = {
	},
}
