--[[
	Notables: the world's named, unique people (src/notables.lua).

	Not pilots. Each one lives at a seat, rides between a few stations as a
	VIP passenger, and leaders also go to summits at Providence. They
	never respawn. When one dies (or is captured) the world changes for
	good: their role says how, and the numbers below say how much.

	Placeholder cast. Names, offices and lines are meant to be rewritten.

	  id        unique; world-state flags are 'notable.<id>'
	  role      journalist | leader | magnate | ceo (D.roles has the rules)
	  faction   a faction id from src/reputation.lua
	  seat      the station they live at
	  circuit   stations they ride to and back from (leaders: empty, they
	            only travel to summits)
	  outlet    journalist: the paper they edit (data/outlets.lua)
	  rival     journalist: the outlet that takes over their beat
	  works     magnate, ceo: { { station=, facility= } } the lines they own
	  goods     goods their death shocks (leader: its faction's stations;
	            magnate: their works)
	  stances   leader: { { with=faction, to=stance } } relations that
	            change for good when they die
	  extra     optional hand-authored effects on top of the role rules,
	            in the same shape (src/worldstate.lua WS.apply)

	This file is plain data: tools/worldstate_doc.lua reads it with no game
	loaded to write docs/world-state.md.
]]
local D = {}

D.roles = {
	journalist = { name = "journalist", deed = -30 },
	leader = { name = "leader", deed = -50 },
	magnate = { name = "magnate", deed = -40 },
	-- a corporation's head (Ceres Concern, Bowman): their own works, and
	-- the company's security, which answers to them
	ceo = { name = "CEO", deed = -40 },
}

D.cast = {
	-- The Estates -----------------------------------------------------------
	{ id = "estates_leader", role = "leader", faction = "estates",
	  name = "Lord Chancellor Aurelian Vane", office = "Lord Chancellor of the Chancery",
	  seat = "station:venus_1", circuit = {},
	  goods = { "electronics", "medical_supplies" },
	  -- the Chancery freezes the Garden's maintenance contracts while the Houses fight over the seal
	  extra = { { kind = "mul", target = "output", where = "faction:estates", by = 0.85 } } },
	{ id = "estates_journalist", role = "journalist", faction = "estates",
	  name = "Cressida Hale", office = "editor of the Inner Worlds Gazette",
	  seat = "station:luna_3", circuit = { "station:earth_1", "station:venus_1" },
	  outlet = "gazette", rival = "signal" },
	{ id = "estates_magnate", role = "magnate", faction = "estates",
	  name = "Idris Calder", office = "Master Founder of Mercury",
	  seat = "station:mercury_1", circuit = { "station:venus_1" },
	  works = { { station = "station:mercury_1", facility = "roll_steel" }, { station = "station:mercury_2", facility = "ceramic_works" } },
	  goods = { "steel_plate", "thermal_ceramics" } },

	-- Zhuhai ----------------------------------------------------------------
	{ id = "zhuhai_leader", role = "leader", faction = "zhuhai",
	  name = "Delegate Wen Shaoqing", office = "Speaker of the Mandate",
	  seat = "station:mars_4", circuit = {},
	  goods = { "steel_plate", "electronics" },
	  -- the deadlock breaks: the next Speaker gets the crackdown through
	  stances = { { with = "milliways", to = "hostile" } } },
	{ id = "zhuhai_journalist", role = "journalist", faction = "zhuhai",
	  name = "Lin Meirong", office = "editor of Red Signal",
	  seat = "station:mars_5", circuit = { "station:mars_3" },
	  outlet = "signal", rival = "gazette" },
	{ id = "zhuhai_magnate", role = "magnate", faction = "zhuhai",
	  name = "Gao Jiancheng", office = "chairman of the Heaven-Ladder conglomerate",
	  seat = "station:mars_3", circuit = { "station:mars_2" },
	  works = { { station = "station:mars_3", facility = "roll_steel" }, { station = "station:mars_3", facility = "press_canisters" } },
	  goods = { "steel_plate", "empty_canister" } },

	-- Jove ------------------------------------------------------------------
	{ id = "jove_leader", role = "leader", faction = "jove",
	  name = "Councillor Teodor Vey", office = "Presiding Councillor of the Accord",
	  seat = "station:jupiter_2", circuit = {},
	  goods = { "deuterium_canister", "hydrogen_canister" },
	  -- Kyrakos stops looking the other way
	  stances = { { with = "milliways", to = "hostile" } } },
	{ id = "jove_journalist", role = "journalist", faction = "jove",
	  name = "Marisol Achterberg", office = "editor of the Jovian Ledger",
	  seat = "station:callisto_1", circuit = { "station:jupiter_2" },
	  outlet = "ledger", rival = "beltway" },
	{ id = "jove_magnate", role = "magnate", faction = "jove",
	  name = "Hesper Okonkwo", office = "skimmer baron of Olympus",
	  seat = "station:jupiter_1", circuit = { "station:jupiter_2" },
	  works = { { station = "station:jupiter_1", facility = "skim_deuterium" } },
	  goods = { "deuterium_canister" } },

	-- The Diwan -------------------------------------------------------------
	{ id = "diwan_leader", role = "leader", faction = "diwan",
	  name = "Grand Vizier Asher ben-Ephraim", office = "Grand Vizier of the Diwan",
	  seat = "station:saturn_2", circuit = {},
	  goods = { "water_ice", "water" },
	  -- the hardliner is gone; his successor would rather tax the cartel than fight it
	  stances = { { with = "milliways", to = "ambivalent" } } },
	{ id = "diwan_journalist", role = "journalist", faction = "diwan",
	  name = "Tamar Gilad", office = "editor of the Diwan Courier",
	  seat = "station:titan_1", circuit = { "station:saturn_2" },
	  outlet = "courier", rival = "ledger" },
	{ id = "diwan_magnate", role = "magnate", faction = "diwan",
	  name = "Elisheva Dor", office = "mistress of the Enceladus brine works",
	  seat = "station:enceladus_2", circuit = { "station:saturn_3" },
	  works = { { station = "station:enceladus_2", facility = "alkali_works" }, { station = "station:enceladus_1", facility = "produce_nitrates" } },
	  goods = { "alkalines", "nitrates" } },

	-- The cartel ------------------------------------------------------------
	{ id = "cartel_leader", role = "leader", faction = "milliways",
	  name = "Marcus Quell", office = "the Proprietor of Milliways",
	  seat = "station:pluto_1", circuit = {},
	  goods = { "amphetamines", "fentanyl", "cannabinoid_moss" },
	  -- without the Proprietor's handshake deals, Zhuhai's Mandate loses patience
	  stances = { { with = "zhuhai", to = "hostile" } } },
	{ id = "cartel_journalist", role = "journalist", faction = "milliways",
	  name = "Juno Sable", office = "editor of The Black Sheet",
	  seat = "station:shoals_3", circuit = { "station:cordelia_1" },
	  outlet = "blacksheet", rival = "beltway" },
	{ id = "cartel_magnate", role = "magnate", faction = "milliways",
	  name = "Dr. Imre Kasza", office = "the Chemist of Cinder Works",
	  seat = "station:shoals_2", circuit = { "station:shoals_3" },
	  works = { { station = "station:shoals_2", facility = "drug_lab" } },
	  goods = { "amphetamines", "fentanyl" } },

	-- The corporations and the Beltway (smaller: a CEO each, and the Beltway's editor)
	{ id = "ceres_ceo", role = "ceo", faction = "ceres",
	  name = "Valentina Roux", office = "Chief Executive of Ceres Concern",
	  seat = "station:belt_1", circuit = { "station:belt_3" },
	  works = { { station = "station:belt_1", facility = "ice_wells" }, { station = "station:belt_2", facility = "mack_assembly" } },
	  goods = { "water_ice" } },
	{ id = "ceres_journalist", role = "journalist", faction = "ceres",
	  name = "Desmond Achebe", office = "editor of the Beltway",
	  seat = "station:belt_3", circuit = { "station:belt_1" },
	  outlet = "beltway", rival = "ledger" },
	{ id = "bowman_ceo", role = "ceo", faction = "bowman",
	  name = "Ingrid Bowman-Tsai", office = "Chief Executive of Bowman Atmospherics",
	  seat = "station:uranus_3", circuit = { "station:uranus_1" },
	  works = { { station = "station:uranus_1", facility = "skim_deuterium" }, { station = "station:titania_1", facility = "ice_wells" } },
	  goods = { "deuterium_canister", "water_ice" } },
}

D.summit = {
	station = "station:ring_1",
	interval = 3 * 3600,   -- a summit every this long
	grandEvery = 5,        -- every this many'th summit is a grand one: every leader
	small = { 2, 3 },      -- leaders at an ordinary summit
	lead = 1800,           -- announced this long before it opens (their VIP runs go up then)
	length = 1200,         -- in session this long, then everyone goes home
}

D.T = {
	tripEvery = 2 * 3600,  -- a journalist or magnate rides somewhere about this often
	tripJitter = 1800,
	stay = 1800,           -- and stays at least this long wherever they land
	expiry = 1800,         -- a VIP contract nobody takes this long: they miss the trip
	deadline = 2 * 3600,   -- from booking, to have them delivered; overdue, a carrier gives them up,
	                       -- and a player loses standing and has them taken off at the next dock
	lapseStanding = -10,   -- with their faction, for an overdue run
	fareMult = 8,          -- times an ordinary single fare
	comfortMin = 0.5,      -- seats this comfortable or better
	standingMin = -15,     -- their staff won't book a captain their faction is wary of
	deliverStanding = 2,   -- a safe delivery, with their faction
	reportedCap = 15,      -- most a rival faction can warm to you for one death
	-- the role rules
	outletReach = 0.35,    -- a journalist's paper keeps this share of its reach
	worksOutput = 0.4,     -- a magnate's lines keep this share of their output
	worksShock = 0.6,      -- their goods spike this much at their works
	crisisShock = 0.4,     -- a leader's goods spike this much across the faction
	shockLength = 6 * 3600,
	leaderPrices = 1.05,   -- a leaderless faction's markets stay this much dearer
	patrols = 0.7,         -- a leaderless faction (or a headless company) fields this share of its police
	inspections = 0.5,     -- and they hold at each stop of their beat this share as long
	heat = 60,             -- heat at their seat for a witnessed killing
}

-- What a notable's death does to the world, from their role, before
-- `extra`. Each entry is an effect for src/worldstate.lua (WS.apply).
function D.consequences(n)
	local T, out = D.T, {}
	local function add(e) out[#out + 1] = e end
	if n.role == "journalist" then
		add({ kind = "mul", target = "outlet_reach", where = n.outlet, by = T.outletReach })
		if n.rival then add({ kind = "beat", outlet = n.rival, from = n.outlet }) end
	elseif n.role == "leader" then
		add({ kind = "mul", target = "price", where = "faction:" .. n.faction, by = T.leaderPrices })
		for _, item in ipairs(n.goods or {}) do
			add({ kind = "shock", where = "faction:" .. n.faction, item = item, size = T.crisisShock, duration = T.shockLength })
		end
		for _, s in ipairs(n.stances or {}) do add({ kind = "stance", a = n.faction, b = s.with, to = s.to }) end
	end
	if n.role == "leader" or n.role == "ceo" then
		add({ kind = "mul", target = "patrols", where = "faction:" .. n.faction, by = T.patrols })
		add({ kind = "mul", target = "inspections", where = "faction:" .. n.faction, by = T.inspections })
	end
	if n.role == "magnate" or n.role == "ceo" then
		for _, w in ipairs(n.works or {}) do
			add({ kind = "mul", target = "output", where = w.station, sub = w.facility, by = T.worksOutput })
			for _, item in ipairs(n.goods or {}) do
				add({ kind = "shock", where = w.station, item = item, size = T.worksShock, duration = T.shockLength })
			end
		end
	end
	for _, e in ipairs(n.extra or {}) do add(e) end
	return out
end

-- Obituary lines: the victim's own paper, a paper hostile to them, and the rest.
D.headlines = {
	own = { "{name} is dead. {faction} mourns its {office}", "Murder of {name}: {faction} demands justice" },
	hostile = { "{name}, {office}, is dead, and few here will weep", "Good riddance: {name} killed" },
	other = { "{name}, {office}, killed", "Death of {name} shakes {faction}" },
	captured = { "{name} taken: {office} held at {station}" },
	summit = { "Summit at Providence: {names} to attend", "Grand summit: every leader bound for Providence" },
}

return D
