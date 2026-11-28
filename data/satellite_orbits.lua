--[[
	Satellites (src/satellites.lua): owned, persistent props in a planet's
	orbit, kept on the map for quests and for a few small utility services.
	Each one is a satellite design in data/satellites/ (edit them in the Shipyard):
	the panels and truss are drawn only, the bus collides and is heavy.

	satellites {
	  field  = field id (a planet or moon)
	  count  = how many, or { min, max } (rolled once per field, seeded)
	  mix    = { kind = weight, ... }   kinds below
	  band   = { inner, outer } as fractions of the way from the surface
	           (0) to the map's edge (1); default { 0.08, 0.85 }
	  names  = name prefix for the satellites ("Earth" -> "Earth sat 07")
	  hubs   = how many hub satellites (kind "hub") on top of the mix: put
	           them where ships need a stop between stations
	  broadcasts = how many broadcast satellites (kind "broadcast"), also
	           on top of the mix
	}

	Kinds (Sat.kinds in src/satellites.lua) give each one its design and
	its default levers:
	  passive  closed: dock = "none", no actions. Quests open them.
	  hub      a mini station: dock = "anyone", fuel and supplies shelf.
	           Placed with hubs = n, not through the mix.
	  broadcast  hails the passing player with its owner's news and price
	           watch (src/dialogs/sat_broadcast.lua). Placed with
	           broadcasts = n, so adding them never reshuffles the rest.

	Every satellite gets a stable id (<field>_sat_<n>) so quests can name it.
	Who they belong to isn't set here: they answer to whoever holds the
	planet (Sat.faction), and the player's own are the player's.
]]

-- Hubs go to the quiet edges, where there's no market station at all:
-- Neptune and Pluto. (The hub kind is meant to be reused, for instances
-- and the like: add hubs = n wherever one should be.)
local hubs = { neptune = 2, pluto = 1 }
local common = { passive = 1 }
-- Broadcast satellites: one over every planet, and over the busy moons.
local broadcasts = { luna = 1, europa = 1, ganymede = 1, titan = 1 }
for _, f in ipairs({ "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune" }) do
	satellites { field = f, count = { 12, 20 }, mix = common, hubs = hubs[f], broadcasts = 1 }
end
for _, f in ipairs({ "luna", "io", "europa", "ganymede", "callisto", "titan", "enceladus", "titania", "triton", "pluto" }) do
	satellites { field = f, count = { 4, 8 }, mix = { passive = 1 }, hubs = hubs[f], broadcasts = broadcasts[f] }
end
