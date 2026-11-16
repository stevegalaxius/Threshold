-- Made in the Shipyard (F2), Icons tab. Art for Nitrates: a white crate; a heap of white salt granules floats on it in the hold.
icon {
	id = "icon_nitrates", item = "nitrates",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "crate", x = 0, y = 0, z = 0, w = 1, d = 0.6, h = 0.7, color = { 0.7, 0.72, 0.74 } },
		{ name = "lid", x = -0.03, y = -0.03, z = 0.7, w = 1.06, d = 0.66, h = 0.1, color = { 0.8, 0.82, 0.84 } },
		{ name = "handle", x = 0.3, y = 0.24, z = 0.8, w = 0.4, d = 0.12, h = 0.04, color = { 0.36, 0.37, 0.4 }, layer = "detail" },
		{ name = "band", x = 0, y = -0.01, z = 0.3, w = 1, d = 0.01, h = 0.12, color = { 0.3, 0.45, 0.7 }, layer = "detail" },
	},
	parts = {
		{ name = "heap", shape = { 1.8, 7.6, 3.2, 5.2, 5, 3.6, 6.8, 5.2, 8.2, 7.6 }, color = { 0.92, 0.94, 0.97 }, badge = true },
		{ name = "granule", shape = { 3.05, 6.8, 2.83, 7.19, 2.38, 7.19, 2.15, 6.8, 2.38, 6.41, 2.83, 6.41 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 3.85, 4.8, 3.62, 5.19, 3.17, 5.19, 2.95, 4.8, 3.17, 4.41, 3.62, 4.41 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 5.05, 5.6, 4.83, 5.99, 4.38, 5.99, 4.15, 5.6, 4.38, 5.21, 4.83, 5.21 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 6.05, 4.2, 5.83, 4.59, 5.38, 4.59, 5.15, 4.2, 5.38, 3.81, 5.83, 3.81 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 7.05, 5.4, 6.83, 5.79, 6.38, 5.79, 6.15, 5.4, 6.38, 5.01, 6.83, 5.01 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 7.85, 7.1, 7.62, 7.49, 7.17, 7.49, 6.95, 7.1, 7.17, 6.71, 7.62, 6.71 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
		{ name = "granule", shape = { 5.65, 6.4, 5.42, 6.79, 4.98, 6.79, 4.75, 6.4, 4.97, 6.01, 5.42, 6.01 }, color = { 0.45, 0.47, 0.5 }, layer = "glow", badge = true },
	},
}
