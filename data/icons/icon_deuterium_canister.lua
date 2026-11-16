-- Made in the Shipyard (F2), Icons tab. Art for Deuterium canister: an upright gas canister, steel caps around a glowing blue deuterium core.
icon {
	id = "icon_deuterium_canister", item = "deuterium_canister",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "base cap", x = 0, y = 0, z = 0, w = 1, d = 0.5, h = 0.4, color = { 0.5, 0.5, 0.5 } },
		{ name = "core", x = 0.07, y = 0.03, z = 0.4, w = 0.86, d = 0.44, h = 0.8, color = { 0.43, 0.5, 1 }, layer = "glass" },
		{ name = "top cap", x = 0, y = 0, z = 1.2, w = 1, d = 0.5, h = 0.36, color = { 0.5, 0.5, 0.5 } },
		{ name = "valve", x = 0.3, y = 0.17, z = 1.56, w = 0.4, d = 0.16, h = 0.12, color = { 0.85, 0.85, 0.88 }, layer = "detail" },
		{ name = "base rim", x = 0, y = -0.01, z = 0.33, w = 1, d = 0.01, h = 0.07, color = { 0.62, 0.62, 0.64 }, layer = "detail" },
		{ name = "top rim", x = 0, y = -0.01, z = 1.2, w = 1, d = 0.01, h = 0.07, color = { 0.62, 0.62, 0.64 }, layer = "detail" },
		{ name = "label", x = 0.12, y = -0.01, z = 0.1, w = 0.4, d = 0.01, h = 0.14, color = { 0.95, 0.8, 0.25 }, layer = "detail" },
	},
	parts = {
	},
}
