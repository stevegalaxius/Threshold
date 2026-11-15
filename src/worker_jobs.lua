--[[
	The jobs the background thread can do (src/worker.lua). Each takes plain
	data and returns plain data; none of them can see the game. They run in
	the thread when there is one and on the main thread when there isn't,
	so they must give the same answer either way.
]]
local J = {}

-- A route between two locations (src/travelgraph.lua). The map layout is
-- the thread's own copy, read from the same files; `version` is the
-- caller's navigation versions for the two areas, and if they aren't the
-- thread's (the layout was edited in this session) it says so instead of
-- answering from an old map.
function J.route(source, target, clock, exact, version)
	local G = require("src.travelgraph")
	if version and version ~= G.versionOf(source, target) then return "stale" end
	return G.plan(source, target, clock, exact or nil) or false
end

-- A way round scenery for one ship (src/local_navigation.lua): the search
-- over a grid of points between it and where it's going. `flat` is the
-- obstacles as numbers (src/pathsearch.lua packs and unpacks them).
function J.path(x, y, gx, gy, radius, padding, direct, flat)
	local P = require("src.pathsearch")
	return P.search(x, y, gx, gy, radius, padding, direct, P.unpack(flat))
end

return J
