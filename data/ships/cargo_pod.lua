-- A surface shuttle (src/shuttles.lua): a cargo-container-sized pod with an
-- engine on the back, lifting a crate or two from the surface to its station.
hull {
	id = "cargo_pod", name = "Cargo Pod", maker = "Ferrous Collective", class = "pod", playable = false, mount = "fixed",
	mass = 30, armor = 40, turn = 120, sideThrust = 0, retroThrust = 120, hold = 8, drag = 0.16, radius = 12,
	shape = { 14,-9, 14,9, -12,9, -16,5, -16,-5, -12,-9 },
	slots = {
		{ family = "engine",  size = "S", x = -16, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "flit_engine", "ember_reactor" },
}
