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
	}

	Kinds (Sat.kinds in src/satellites.lua) give each one its design and
	its default levers:
	  passive  closed: dock = "none", no actions. Quests open them.
	  fuel     a fuel buoy: dock = "anyone", vend = { "fuel" }
	  vendor   a vending sat: dock = "anyone", vend = ammo and supplies

	Every satellite gets a stable id (<field>_sat_<n>) so quests can name it.
]]

local common = { passive = 10, fuel = 2, vendor = 2 }
for _, f in ipairs({ "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune" }) do
	satellites { field = f, count = { 12, 20 }, mix = common }
end
for _, f in ipairs({ "luna", "io", "europa", "ganymede", "callisto", "titan", "enceladus", "titania", "triton", "pluto" }) do
	satellites { field = f, count = { 4, 8 }, mix = { passive = 6, fuel = 1, vendor = 1 } }
end
