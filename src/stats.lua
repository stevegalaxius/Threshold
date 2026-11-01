--[[
	The stat pipeline: hull + modules -> final ship stats.

	    final = (hull base + sum of modules) * hull bonus

	The one exception is the hullMass bonus, which only scales the hull's own
	mass (a light frame shouldn't make your armor plates lighter).

	Hold contents (ammo, salvage) add mass on top, computed in ship.lua as
	the hold changes.
]]

local data = require("src.data")

local stats = {}

-- Stats that come straight from summing fields.
local SUMMED = { "thrust", "sideThrust", "retroThrust", "turn", "armor", "hold", "powerOut", "powerCap", "powerDraw", "tractorRange" }

function stats.compute(hull, loadout)
	local s = { mass = hull.mass * (hull.bonuses.hullMass or 1) }
	for _, k in ipairs(SUMMED) do s[k] = hull[k] or 0 end

	for i in ipairs(hull.slots) do
		local m = loadout[i] and data.modules[loadout[i]]
		if m then
			-- a module with byMass scales with the hull's mass (side jets):
			-- k = (hull mass / ref) ^ exp
			local k = 1
			if m.byMass then k = (hull.mass / m.byMass.ref) ^ m.byMass.exp end
			s.mass = s.mass + m.mass * k
			for _, f in ipairs(SUMMED) do s[f] = s[f] + (m[f] or 0) * k end
		end
	end

	-- Hull bonuses on summed stats.
	local b = hull.bonuses
	for _, k in ipairs(SUMMED) do
		if b[k] then s[k] = s[k] * b[k] end
	end
	if b.mass then s.mass = s.mass * b.mass end

	-- Bonuses that apply to weapons or collisions rather than a summed stat.
	s.mult = {
		primaryFireRate = b.primaryFireRate or 1,
		primaryDamage = b.primaryDamage or 1,
		missileDamage = b.missileDamage or 1,
		ramDamage = b.ramDamage or 1,
	}

	s.powerNet = s.powerOut - s.powerDraw   -- what's left to recharge with
	return s
end

-- Mass and volume of what's in a hold.
function stats.cargo(cargo)
	local volume, mass = 0, 0
	for id, count in pairs(cargo) do
		local item = data.items[id]
		if item and count > 0 then
			volume = volume + item.volume * count
			mass = mass + item.mass * count
		end
	end
	return volume, mass
end

return stats
