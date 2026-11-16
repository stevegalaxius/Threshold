--[[
	Satellites (src/satellites.lua): owned, persistent props in a planet's
	orbit, kept on the map for quests and for a few small utility services.
	Each one is a satellite design in data/satellites/ (edit them in the Shipyard):
	the panels and truss are drawn only, the bus collides and is heavy.

	satellites {
	  field  = field id (a planet or moon)
	  count  = how many, or { min, max } (rolled once per field, seeded)
	  mix    = { kind = weight, ... }   kinds below
	  owner  = who owns them (a faction or station id; nil: nobody)
	  band   = { inner, outer } as fractions of the way from the surface
	           (0) to the map's edge (1); default { 0.08, 0.85 }
	  names  = name prefix for the satellites ("Earth" -> "Earth sat 07")
	  hubs   = how many hub satellites (kind "hub") on top of the mix: put
	           them where ships need a stop between stations
	}

	Kinds (Sat.kinds in src/satellites.lua) give each one its design and
	its default levers:
	  passive  closed: dock = "none", no actions. Quests open them.
	  hub      a mini station: dock = "anyone", fuel and supplies shelf.
	           Placed with hubs = n, not through the mix.

	Every satellite gets a stable id (<field>_sat_<n>) so quests can name it.
]]

-- Hubs go where a ship can be a long way from a market: Neptune and Pluto
-- have no market station at all, Titania only one, and the gas giants'
-- maps are the biggest in the system.
local hubs = { jupiter = 1, saturn = 2, uranus = 1, neptune = 2, titania = 1, pluto = 1 }
local common = { passive = 1 }
for _, f in ipairs({ "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune" }) do
	satellites { field = f, count = { 12, 20 }, mix = common, hubs = hubs[f] }
end
for _, f in ipairs({ "luna", "io", "europa", "ganymede", "callisto", "titan", "enceladus", "titania", "triton", "pluto" }) do
	satellites { field = f, count = { 4, 8 }, mix = { passive = 1 }, hubs = hubs[f] }
end
