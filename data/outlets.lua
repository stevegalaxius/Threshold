--[[
	News outlets (src/news.lua). Each is owned by a faction from
	src/reputation.lua, reports its beat first-hand, and leans its numbers
	toward what its owner sells.

	  owner     the faction that owns it (stations of that faction carry it)
	  hidden    the real owner, if it isn't public (shown nowhere yet)
	  beat      areas it has reporters in: first-hand, accurate details
	  everywhere  carried at every station, not just its owner's
	  agenda    good -> lean: +1 talks the price up, -1 talks it down
	  lean      how hard it leans (0 = honest, 1 = doubles every move)
	  rumour    chance per news tick of printing a story with nothing behind it
	  hush      own-faction shortages: 'suppress' never prints them,
	            'soften' prints them at half size
	  smear     how readily it names people (0..1); tabloids name everyone
	  outlaw    a pirate sheet: attacks on the factions are heroics, and
	            it warms to whoever does them
	  templates headline sets by story kind; {good} {station} {area}
	            {pct} {who} {faction} are filled in. Missing kinds fall back
	            to data.default.
]]
local D = {}

D.order = { "gazette", "signal", "ledger", "courier", "beltway", "blacksheet" }

D.outlets = {
	gazette = {
		name = "Inner Worlds Gazette", short = "Gazette", owner = "estates",
		beat = { "mercury", "venus", "earth", "luna", "station" },
		agenda = { food_crate = 1, medical_supplies = 1, electronics = -1 },
		lean = .5, rumour = .03, hush = "soften", smear = .3,
		templates = {
			shortage = { "{station} society frets over scarce {good}", "{good} prices climb at {station}: {pct}" },
			glut = { "A surfeit of {good} at {station}, {pct}" },
			killed = { "{faction} vessel lost near {area}; {who} sought", "Tragedy off {area}: {who} blamed", "Grief and fury near {area}: {faction} crew slain, {who} at large" },
			lost = { "Independent {victim} lost near {area}", "Lawlessness near {area}: {victim} destroyed by {who}" },
			praise = { "A credit to the Inner Worlds: {who} at {area}" },
			smear = { "Questions raised over the conduct of {who}" },
		},
	},
	signal = {
		name = "Red Signal", short = "Signal", owner = "zhuhai",
		beat = { "mars", "phobos", "deimos" },
		agenda = { electronics = 1, steel_plate = 1, food_crate = -1 },
		lean = .6, rumour = .04, hush = "suppress", smear = .5,
		templates = {
			shortage = { "{faction} mismanagement empties {station} of {good}", "{good} {pct} at {station}: who profits?" },
			glut = { "Mars industry floods {station} with {good}, {pct}" },
			killed = { "Foreign provocation near {area}: {who} strikes {faction} ship", "{who} attacks {faction} shipping off {area}", "{faction} crew butchered near {area}: is {who} working for someone?" },
			lost = { "Unprotected {victim} destroyed near {area}: who will guard the people?", "{who} preys on {victim} off {area}" },
			praise = { "Independent captain {who} defies blockade at {area}" },
			smear = { "{who}: agent of foreign interests?" },
		},
	},
	ledger = {
		name = "Jovian Ledger", short = "Ledger", owner = "jove",
		beat = { "jupiter", "io", "europa", "ganymede", "callisto" },
		agenda = { deuterium_canister = 1, hydrogen_canister = 1, steel_plate = -1 },
		lean = .3, rumour = .02, hush = "soften", smear = .2,
		templates = {
			shortage = { "{good} at {station} {pct} on list", "Supply note: {station} short of {good} ({pct})" },
			glut = { "{good} at {station} {pct} on list; carriers advised" },
			killed = { "Freight loss off {area}: one {faction} hull, {who} reported", "{faction} hull and crew written off near {area}; {who} named in the claim" },
			lost = { "Hull loss near {area}: independent {victim}, {who} reported", "Premiums up near {area} after {victim} goes down" },
			praise = { "Carrier {who} credited with clean run at {area}" },
			smear = { "Underwriters wary of {who}" },
		},
	},
	courier = {
		name = "Diwan Courier", short = "Courier", owner = "diwan",
		beat = { "saturn", "enceladus", "titan" },
		agenda = { water_ice = 1, water = 1, silicon = -1 },
		lean = .5, rumour = .03, hush = "soften", smear = .4,
		templates = {
			shortage = { "Thirst at {station}: {good} {pct}", "The faithless go without: {good} {pct} at {station}" },
			glut = { "Waste at {station}: {good} {pct}" },
			killed = { "An outrage near {area}: {who} sheds {faction} blood", "{who} will answer for {area}", "Mourning for the {faction} dead off {area}; {who} cursed in every chapel" },
			lost = { "A {victim} lost near {area}; the Courier prays for its crew", "{who} strikes again near {area}: a {victim} burns" },
			praise = { "The Courier honours {who} for conduct at {area}" },
			smear = { "The Courier has not forgotten {who}" },
		},
	},
	beltway = {
		name = "Beltway", short = "Beltway", owner = "ceres", hidden = "ceres", everywhere = true,
		beat = { "belt", "ceres_quarry", "quarry" },
		agenda = { iron_ore = 1, heavy_metals = 1, silicon = 1 },
		lean = 1, rumour = .08, hush = "suppress", smear = .8,
		templates = {
			shortage = { "{good} CRISIS: {station} shelves bare!", "PANIC at {station} as {good} soars {pct}!" },
			glut = { "{good} CRASH at {station}: {pct}!" },
			killed = { "BLOODBATH off {area}! {who} guns down {faction} crew", "MASSACRE near {area}: {who} on the loose", "{faction} CREW BLOWN TO PIECES off {area}! Is {who} next door?" },
			lost = { "FIREBALL near {area}! {victim} vaporised by {who}", "DEATH LANE: another {victim} gone near {area}" },
			praise = { "HERO {who} saves the day at {area}!" },
			smear = { "WHO IS {who}? The captain everyone's talking about" },
		},
	},
	blacksheet = {
		name = "The Black Sheet", short = "Black Sheet", owner = "milliways", outlaw = true,
		beat = { "milliways", "shoals", "cordelia", "antichthon" },
		agenda = { explosives = 1, electronics = 1, medical_supplies = 1, food_crate = -1 },
		lean = .8, rumour = .06, hush = "suppress", smear = .6,
		templates = {
			shortage = { "{faction} can't feed {station}: {good} {pct}", "Easy money: {good} {pct} at {station}" },
			glut = { "{good} going cheap at {station} ({pct}), help yourself" },
			killed = { "Another {faction} tub sent down off {area}. Drinks on {who}", "{who} takes a bite out of {faction} near {area}", "{faction} bleeds near {area} and {who} sends its regards" },
			lost = { "Tough luck for a {victim} near {area}", "{who} picks off a {victim} near {area}: salvage, anyone?" },
			praise = { "Raise a glass to {who}", "{who}: one of ours" },
			smear = { "{who} is a company snitch", "Don't dock next to {who}" },
		},
	},
}

D.default = {
	shortage = { "{good} short at {station} ({pct})" },
	glut = { "{good} cheap at {station} ({pct})" },
	killed = { "{faction} ship lost near {area}; {who} blamed" },
	lost = { "{victim} lost near {area}; {who} blamed" },
	praise = { "{who} praised for conduct at {area}" },
	smear = { "Concern over {who}" },
}

return D
