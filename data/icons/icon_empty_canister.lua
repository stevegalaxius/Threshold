-- Made in the Shipyard (F2), Icons tab. Art for Empty canister: an upright gas canister like the full ones, its clear glass core empty.
icon {
	id = "icon_empty_canister", item = "empty_canister",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "base cap", x = 0, y = 0, z = 0, w = 1, d = 0.5, h = 0.4, color = { 0.5, 0.5, 0.5 } },
		{ name = "core", x = 0.07, y = 0.03, z = 0.4, w = 0.86, d = 0.44, h = 0.8, color = { 0.09, 0.1, 0.12 }, layer = "glow" },
		{ name = "top cap", x = 0, y = 0, z = 1.2, w = 1, d = 0.5, h = 0.36, color = { 0.5, 0.5, 0.5 } },
		{ name = "valve", x = 0.3, y = 0.17, z = 1.56, w = 0.4, d = 0.16, h = 0.12, color = { 0.85, 0.85, 0.88 }, layer = "detail" },
		{ name = "base rim", x = 0, y = -0.01, z = 0.33, w = 1, d = 0.01, h = 0.07, color = { 0.62, 0.62, 0.64 }, layer = "detail" },
		{ name = "top rim", x = 0, y = -0.01, z = 1.2, w = 1, d = 0.01, h = 0.07, color = { 0.62, 0.62, 0.64 }, layer = "detail" },
		{ name = "label", x = 0.12, y = -0.01, z = 0.1, w = 0.4, d = 0.01, h = 0.14, color = { 0.6, 0.62, 0.65 }, layer = "detail" },
		{ name = "glass glint", x = 0.14, y = -0.01, z = 0.5, w = 0.06, d = 0.01, h = 0.55, color = { 0.25, 0.27, 0.3 }, layer = "glow" },
	},
	parts = {
	},
}
