-- A surface shuttle (src/shuttles.lua): a cargo-container-sized pod with an
-- engine on the back, lifting a crate or two from the surface to its station.
hull {
	id = "cargo_pod", name = "Cargo Pod", maker = "Ferrous Collective", class = "pod", playable = false, mount = "fixed",
	mass = 45, armor = 60, turn = 120, sideThrust = 0, retroThrust = 120, hold = 8, drag = 0.16, radius = 22,
	shape = { 26,-16, 26,16, -22,16, -30,9, -30,-9, -22,-16 },
	slots = {
		{ family = "engine",  size = "S", x = -30, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "flit_engine", "ember_reactor" },
}
