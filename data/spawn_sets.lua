--[[
	Spawn sets (src/spawn.lua): what is placed in an area the first time a
	save sees it. Nothing restocks on its own; events place more later with
	Spawn.place(game, setId, area).

	  place = { { item = crate item id | container = object id,
	              count = { min, max }, loot = table id (else the object's),
	              zone = "field" (anywhere clear) | { x, y, r } }, ... }
]]

-- Cargo lost along the trade routes: a few crates drifting in every area.
spawn_set {
	id = "lost_cargo", areas = "all",
	place = {
		{ item = "cargo_container", count = { 4, 7 }, loot = "lost_cargo", zone = "field" },
	},
}
