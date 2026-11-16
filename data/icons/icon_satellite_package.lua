-- Made in the Shipyard (F2), Icons tab. Art for Satellite package: a folded satellite: bus, stowed panels and dish.
icon {
	id = "icon_satellite_package", item = "satellite_package",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "bus", x = 0.25, y = 0.1, z = 0, w = 0.5, d = 0.5, h = 0.6, color = { 0.85, 0.7, 0.3 } },
		{ name = "panel left", x = 0, y = 0.15, z = 0.05, w = 0.22, d = 0.4, h = 0.5, color = { 0.2, 0.3, 0.6 } },
		{ name = "panel right", x = 0.78, y = 0.15, z = 0.05, w = 0.22, d = 0.4, h = 0.5, color = { 0.2, 0.3, 0.6 } },
		{ name = "dish", x = 0.32, y = 0.18, z = 0.6, w = 0.36, d = 0.34, h = 0.08, color = { 0.92, 0.93, 0.9 } },
		{ name = "antenna", x = 0.47, y = 0.3, z = 0.68, w = 0.06, d = 0.06, h = 0.2, color = { 0.45, 0.47, 0.52 } },
		{ name = "beacon", x = 0.46, y = 0.29, z = 0.88, w = 0.08, d = 0.08, h = 0.05, color = { 1, 0.3, 0.3 }, layer = "glow" },
	},
	parts = {},
}
