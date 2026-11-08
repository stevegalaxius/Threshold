--[[
	Moons, and getting to them. Each moon is its own small map (Fields.moons
	in src/fields.lua lists them); you don't take a mass driver there.

	  ways out  every planet with moons has a stretch of its map's edge for
	            each one (T.departArc wide), at a fixed corridor bearing. The
	            corridor stays put while the moon orbits. A moon's map has
	            one return corridor toward
	            its planet, plus one toward each sister moon of the
	            same planet (Fields.moonLink gives its bearing and length). The map's edge lets you through there.
	  departure fly out past the edge there and it plays like a mass
	            driver's coast: you swing onto the bearing at your own
	            speed while the camera pulls wide, then you're in
	            transit (Game:launchTrip, a short lane, the moon's gap). You
	            come out of it into the moon's map flying as you were.

	Everything comes from a moon's data entry (parent, period, phase,
	gap), so a new moon needs no code here.

	Added to Game by src/game.lua: require("src.moons")(Game).
]]

local T = require("src.tuning")
local Fields = require("src.fields")
local Locations = require("src.locations")

local sqrt, cos, sin, pi, abs = math.sqrt, math.cos, math.sin, math.pi, math.abs


return function(Game)

-- Fixed corridor exits: { to, label, a, x, y, length }.
-- x, y is the edge of the map in the direction of the moon (or planet).
function Game:spawnMoonGates()
	self.moonGates = {}
	local id, F = self.fieldId, self.field
	local function add(to, length)
		table.insert(self.moonGates, { to = to, label = Fields[to].name, locationId = id .. "/to_" .. to, length = length })
	end
	for _, m in ipairs(Fields.moonsOf(id)) do
		add(m, Fields.moons[m].gap)
	end
	local moon = Fields.moons[id]
	if moon then
		add(moon.parent, moon.gap)
		-- sister moons: a direct highway, no stop at the planet
		for _, sister in ipairs(Fields.siblingMoons(id)) do
			local _, length = Fields.moonLink(id, sister)
			add(sister, length)
		end
	end
	self:placeMoonGates()
end

function Game:placeMoonGates()
	local clock = self.universe and self.universe.clock or 0
	for _, g in ipairs(self.moonGates or {}) do
		g.x, g.y, g.a = Locations.position(g.locationId, clock)
	end
end

-- Which way out (x, y) is heading for, if it's off the map's edge toward
-- a moon (or back toward the planet).
function Game:moonGateAt(x, y)
	local a = math.atan2(y, x)
	local arc = T.departArc / 2 / self.arenaRadius
	for _, g in ipairs(self.moonGates or {}) do
		if abs((a - g.a + pi) % (2 * pi) - pi) < arc then return g end
	end
end

function Game:onMoonRoad(x, y) return self:moonGateAt(x, y) ~= nil end

-- Crossing a moon exit is a scene handoff, not a scripted launch.
-- The retained origin and translated camera preserve the view.
function Game:updateMoonGates(dt)
 if not self.moonGates or #self.moonGates==0 then return end
 self:placeMoonGates()
 local p=self.player
 if not p or p.dead or p.dockState or self.state~="playing" or self.lane then return end
 -- a mass-driver shot is already bound for another planet; flying out
 -- through a moon exit on the way must not hijack it
 if p.launch or p.driverTractor or self.driverMenu or self.pendingFlight then return end
 local x,y=p.body:getPosition()
 if x*x+y*y<self.arenaRadius^2 then return end
 local vx,vy=p.body:getLinearVelocity()
 if vx*x+vy*y<=0 then return end
 local g=self:moonGateAt(x,y)
 if not g then return end
 self:launchTrip(g.to,{bearing=math.atan2(y,x),length=g.length})
 self:toast(("TRANSIT TO %s"):format(Fields[g.to].name:upper()),2.5)
end

end
