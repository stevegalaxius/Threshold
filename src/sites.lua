--[[
	Sites: instanced places off the map (data/sites.lua).

	A site is spawned from a template into universe.sites under its own
	instance id, near a home planet. Each of its pockets becomes a field
	(Fields["site/<inst>/<n>"], instance = true) built from the template's
	pieces. A mass driver can fire you to pocket 1 (the orrery shows the
	site as a diamond in the site's colour, src/ui/orrery.lua); inside,
	acceleration gates fire you from pocket to pocket, and an exit gate
	sends you back out of the driver you came from.

	Saved per site: which pockets are cleared, where you came in from, and
	when it closes. Containers and wrecks in each pocket persist like any
	other area's (src/persistence.lua).

	Added to Game by src/game.lua: require("src.sites").install(Game).
]]

local data = require("src.data")
local Fields = require("src.fields")
local T = require("src.tuning")

local Sites = {}
local cos, sin, pi, sqrt, random = math.cos, math.sin, math.pi, math.sqrt, love.math.random


function Sites.fieldId(instId, n) return ("site/%s/%d"):format(instId, n) end

-- The site and pocket a field id belongs to.
function Sites.of(fieldId)
	local f = Fields[fieldId]
	return f and f.site, f and f.pocket
end

function Sites.list(u)
	u.sites = u.sites or {}
	return u.sites
end

function Sites.template(inst) return data.sites[inst.template] end

-- Make the fields for one site's pockets.
function Sites.register(inst)
	local def = Sites.template(inst)
	if not def then return false end
	for n, pk in ipairs(def.pockets) do
		local id = Sites.fieldId(inst.id, n)
		local field = {
			instance = true, site = inst.id, pocket = n,
			name = pk.name or def.name, radius = pk.radius or 21000,
			spawn = pk.spawn or { 0, (pk.radius or 21000) * 0.4 },
			stationIds = {}, buoyIds = {}, locations = {},
		}
		field.build = function(game) Sites.build(game, inst, n) end
		Fields[id] = field
	end
	return true
end

function Sites.unregister(inst)
	local def = Sites.template(inst)
	for n = 1, def and #def.pockets or 0 do Fields[Sites.fieldId(inst.id, n)] = nil end
end

-- Put every saved site's fields back (after loading a save). Sites from
-- before wildcat crews (no inst.crew) close: their garrisons are gone.
function Sites.restore(u)
	for _, inst in pairs(Sites.list(u)) do Sites.register(inst) end
	for _, inst in pairs(Sites.list(u)) do
		if not inst.crew and Sites.hasCrew(inst) then Sites.close(u, inst) end
	end
end

-- Does a template put a crew in it (any enemies piece)?
function Sites.hasCrew(inst)
	local def = Sites.template(type(inst) == "table" and inst or { template = inst })
	for _, pk in ipairs(def and def.pockets or {}) do
		for _, pc in ipairs(pk.pieces or {}) do if pc.type == "enemies" then return true end end
	end
	return false
end

-- A new site from template `templateId`. opts: home, lifetime, discovered.
function Sites.spawn(u, templateId, opts)
	opts = opts or {}
	local def = assert(data.sites[templateId], "unknown site " .. tostring(templateId))
	local home = opts.home or def.home
	if type(home) == "table" then home = home[random(1, #home)] end
	home = Fields.orbits[home] and home or "earth"
	u.nextSiteId = (u.nextSiteId or 0) + 1
	local id = ("%s_%d"):format(templateId, u.nextSiteId)
	local life = opts.lifetime or def.lifetime
	local inst = { id = id, template = templateId, home = home, bearing = random() * pi * 2,
		spawned = u.clock or 0, expires = life and (u.clock or 0) + life or nil,
		discovered = opts.discovered or not def.hidden, pockets = {}, hoard = {} }
	Sites.list(u)[id] = inst
	Sites.register(inst)
	-- its wildcat crew, rolled once (src/wildcats.lua)
	require("src.wildcats").roll(u, inst)
	return inst
end

-- Close a site: its fields and saved pockets go.
function Sites.close(u, inst, game)
	require("src.wildcats").disband(u, inst.id, game)
	Sites.unregister(inst)
	for n = 1, #(Sites.template(inst) or { pockets = {} }).pockets do
		if u.areas then u.areas[Sites.fieldId(inst.id, n)] = nil end
	end
	Sites.list(u)[inst.id] = nil
end

-- Close expired and finished sites, except the one you're in (it closes
-- once you leave).
function Sites.prune(u, here, game)
	local inside = Sites.of(here)
	for id, inst in pairs(Sites.list(u)) do
		local gone = not Sites.template(inst) or (inst.expires and (u.clock or 0) >= inst.expires) or inst.done
		if gone and id ~= inside then Sites.close(u, inst, game) end
	end
end

-- Wildcat sites come and go on their own (src/wildcats.lua): every
-- T.siteSpawnEvery one may open near a planet with traffic and a station
-- to pay for it, up to T.sitesPerPlanet each and T.sitesMax in all. They
-- open on the driver from the start.
function Sites.wildTemplates()
	local out = {}
	for _, id in ipairs(data.list.sites) do if data.sites[id].wild then out[#out + 1] = id end end
	return out
end
function Sites.homes()
	local out = {}
	local Dark = require("src.dark")
	for _, area in ipairs(Fields.list) do
		local f = Fields[area]
		if Fields.orbits[area] and not Dark.isDarkArea(area) and f.driverId and f.alifeSecurity
			and require("src.wreck_bounty").payer(area) then out[#out + 1] = area end
	end
	return out
end
-- How many more wildcats the sites need for their share of the population.
function Sites.shortfall(u)
	local living, wild = 0, 0
	for _, r in pairs(u.npcs or {}) do
		if r.state ~= "dead" and r.state ~= "escaped" then
			living = living + 1
			if r.wildcat or r.populationGroup == "hunter" then wild = wild + 1 end
		end
	end
	return math.ceil(T.siteShare * living) - wild
end
function Sites.tick(game, clock)
	local u = game.universe
	if game.preview or game.sideScene then return end
	if clock >= (u.sitePruneNext or 0) then
		u.sitePruneNext = clock + 30
		Sites.prune(u, game.fieldId, game)
	end
	-- (a save from before sites were public: show its hidden ones)
	if not u.sitesPublic then
		u.sitesPublic = true
		for _, inst in pairs(Sites.list(u)) do
			local def = Sites.template(inst)
			if def and def.wild and not inst.done then inst.discovered = true end
		end
	end
	if clock < (u.siteSpawnNext or 0) then return end
	-- the first look (a new world or a save without them) fills the share
	-- at once; after that one site at a time
	local burst = u.siteSpawnNext == nil and T.sitesMax or 1
	u.siteSpawnNext = clock + T.siteSpawnEvery * (0.7 + 0.6 * random())
	local made
	for _ = 1, burst do
		if Sites.shortfall(u) <= 0 then break end
		local open, per = 0, {}
		for _, inst in pairs(Sites.list(u)) do
			local def = Sites.template(inst)
			if def and def.wild and not inst.done then open = open + 1; per[inst.home] = (per[inst.home] or 0) + 1 end
		end
		if open >= T.sitesMax then break end
		local homes = {}
		for _, area in ipairs(Sites.homes()) do if (per[area] or 0) < T.sitesPerPlanet then homes[#homes + 1] = area end end
		local wild = Sites.wildTemplates()
		if #homes == 0 or #wild == 0 then break end
		made = Sites.spawn(u, wild[random(#wild)], { home = homes[random(#homes)] }) or made
	end
	return made
end

function Sites.timeLeft(u, inst)
	if not inst.expires then return nil end
	return math.max(0, inst.expires - (u.clock or 0))
end

-- What the orrery shows: open, discovered sites, sorted by name.
function Sites.visible(u)
	local out = {}
	for _, inst in pairs(Sites.list(u)) do
		local def = Sites.template(inst)
		if def and inst.discovered and not inst.done and (Sites.timeLeft(u, inst) or 1) > 0 then out[#out + 1] = inst end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Mark a hidden site found (a mission, a scan, a tip-off): it joins the
-- driver's Destinations pane and the orrery. Returns true if it was new.
function Sites.discover(u, inst)
	if inst.discovered then return false end
	inst.discovered, inst.discoveredAt = true, u.clock or 0
	return true
end

-- The driver's Destinations pane: open sites split into instances (on
-- the public list) and discoveries (hidden templates the player found).
function Sites.destinations(u)
	local instances, found = {}, {}
	for _, inst in ipairs(Sites.visible(u)) do
		local def = Sites.template(inst)
		table.insert(def.hidden and found or instances, inst)
	end
	return instances, found
end

-- Where a site is, in AU from the Sun: a little way off its home planet,
-- riding round with it.
function Sites.position(inst, clock)
	local x, y = Fields.orbitPos(inst.home, clock)
	return x + cos(inst.bearing) * 0.25, y + sin(inst.bearing) * 0.25
end

-- Where any map is, in AU from the Sun: a planet on its orbit, a moon on
-- its planet, a site's pocket wherever its site is.
function Sites.mapPosition(u, id, clock)
	if Fields.orbits[id] then return Fields.orbitPos(id, clock) end
	local moon = Fields.moons and Fields.moons[id]
	if moon then return Fields.orbitPos(moon.parent, clock) end
	local inst = Sites.of(id) and Sites.list(u)[Sites.of(id)]
	if inst then return Sites.position(inst, clock) end
end

-- How long the lane is between a site and map `from`: the same length a
-- planet-to-planet lane of that distance gets (Fields.laneLength), so a
-- site across the system is a longer trip than one next door. Also the
-- distance, in AU, for the lane's progress bar.
function Sites.laneLength(u, inst, from, clock)
	local ax, ay = Sites.mapPosition(u, from, clock)
	if not ax then return T.siteLaneLength, 0 end
	local bx, by = Sites.position(inst, clock)
	local au = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	return Fields.laneLength(au), au
end

function Sites.fare(inst)
	local def = Sites.template(inst)
	return def and def.fare or T.siteFare or 200
end

function Sites.name(inst)
	local def = Sites.template(inst)
	return def and def.name or inst.id
end

function Sites.color(inst)
	local def = Sites.template(inst)
	return def and def.color or { 0.6, 0.8, 1 }
end

-- Building a pocket ------------------------------------------------------------

local function around(piece, game)
	if piece.x then
		local r = piece.r or 0
		local a, d = random() * pi * 2, random() * r
		return piece.x + cos(a) * d, piece.y + sin(a) * d
	end
	return game:spawnPoint(900, game.arenaRadius - 1500)
end

local builders = {}

function builders.rocks(game, pc) game:spawnAsteroids(pc.count or 40, pc.minD) end

function builders.giant(game, pc) game:spawnGiantAsteroid(pc.x or 0, pc.y or 0, pc.r or 1200) end

function builders.station(game, pc, ctx)
	local st = game:spawnStation(pc.station, pc.x or 0, pc.y or 0, pc.spin or 0.02, false)
	if pc.name then st.name = pc.name end
end

-- Site enemies are the site's wildcat crew (src/wildcats.lua), rolled
-- when it spawned: whoever is at their posts in this pocket comes online
-- through A-Life like any other NPC. Nobody new is placed here.
function builders.enemies(game, pc, ctx)
	if ctx.n and not ctx.settled then
		ctx.settled = true
		require("src.wildcats").settle(game, ctx.inst, ctx.n)
	end
end

function builders.containers(game, pc, ctx)
	-- containers persist with the pocket, so only the first visit places them
	if ctx.restored then return end
	local zone = pc.x and { x = pc.x, y = pc.y, r = pc.r or 400 } or "field"
	require("src.spawn").entry(game, { item = pc.item, container = pc.container, count = pc.count, loot = pc.loot, zone = zone })
end

function builders.spawnSet(game, pc, ctx)
	if ctx.restored then return end
	require("src.spawn").place(game, pc.id, pc.minD)
end

-- A gate's place round its pocket: the template's spot, swung round the
-- centre to a bearing of its own for this site and pocket. Each pocket
-- turns a golden angle (about 137 degrees) on from the last, from the
-- site's own bearing, give or take a little, so a site's gates never all
-- face one way and no two sites lay out alike.
local GOLDEN = pi * (3 - math.sqrt(5))
local function gateBearing(inst, n, k)
	local h = 0
	for i = 1, #inst.id do h = (h * 31 + inst.id:byte(i)) % 2147483647 end
	local rng = love.math.newRandomGenerator(h + n * 7919 + k * 104729)
	return inst.bearing + n * GOLDEN + (rng:random() - 0.5) * 0.6
end
function builders.gate(game, pc, ctx)
	local x, y = pc.x or 0, pc.y or 0
	local d = math.sqrt(x * x + y * y)
	if d > 0 and not pc.angle then
		ctx.gates = (ctx.gates or 0) + 1
		local a = gateBearing(ctx.inst, ctx.n, ctx.gates)
		local q = {}
		for k, v in pairs(pc) do q[k] = v end
		q.x, q.y = cos(a) * d, sin(a) * d
		pc = q
	end
	game:spawnSiteGate(ctx.inst, ctx.n, pc)
end

function Sites.builders() return builders end

function Sites.build(game, inst, n)
	local def = Sites.template(inst)
	local pk = def.pockets[n]
	inst.pockets[n] = inst.pockets[n] or {}
	local ctx = { inst = inst, n = n, state = inst.pockets[n], restored = game.restoringArea ~= nil }
	local exit = false
	for _, pc in ipairs(pk.pieces or {}) do
		local b = builders[pc.type]
		if b then b(game, pc, ctx) end
		if pc.type == "gate" and pc.to == "exit" then exit = true end
	end
	if n == 1 and not exit then
		local sx, sy = game.field.spawn[1], game.field.spawn[2]
		local g = game:spawnSiteGate(inst, n, { to = "exit", x = sx + 900, y = sy + 300 })
		g.autoExit = true
	end
end

-- Debug panel: spawn a site from any template, warp into an open one.
function Sites.panel(game, Slab)
	local u = game.universe
	Slab.Text("Spawn a site (shows on the driver's orrery)")
	for _, id in ipairs(data.list.sites) do
		local def = data.sites[id]
		if Slab.Button(("Spawn %s (%s)"):format(def.name, def.kind or "site"), { W = 290 }) then
			local inst = Sites.spawn(u, id, { discovered = true })
			game:toast(("%s NEAR %s"):format(def.name:upper(), Fields[inst.home].name:upper()), 2)
		end
	end
	Slab.Separator()
	for _, inst in ipairs(Sites.visible(u)) do
		if Slab.Button(("Warp into %s near %s"):format(Sites.name(inst), Fields[inst.home].name), { W = 290 }) then game:enterSite(inst.id) end
	end
	local id, n = Sites.of(game.fieldId)
	if id then
		Slab.Text(("In %s, pocket %d"):format(id, n))
		if Slab.Button("Clear pocket enemies", { W = 290 }) then game:clearEnemies() end
	end
end

-- Gates ------------------------------------------------------------------------

function Sites.install(Game)

-- An acceleration gate: a small mass driver with one target, pre-aimed
-- (the piece's angle, else pointing out from the pocket's middle). Fly
-- up its runway and it tractors you in and fires you down a short lane to
-- the next pocket, or back to the driver you came in by. A locked one
-- won't take you (Game:gateOpen).
function Game:spawnSiteGate(inst, n, pc)
	local x, y = pc.x or 0, pc.y or 0
	local a = pc.angle or ((x ~= 0 or y ~= 0) and math.atan2(y, x) or -pi / 2)
	local barrel = T.gateBarrel
	-- the piece's x, y is the breech; the body sits mid-barrel
	local body = love.physics.newBody(self.world, x + cos(a) * barrel / 2, y + sin(a) * barrel / 2, "kinematic")
	local def = Sites.template(inst)
	local g = { kind = "driver", invulnerable = true, id = self:nextId(), team = 0, body = body, angle = a,
		radius = T.gateRadius, barrel = barrel, hw = T.gateHalfWidth, zone = T.gateZone, zoneWidth = T.gateZoneWidth,
		color = def.color, site = inst.id, pocket = n, unlock = pc.unlock,
		gate = { site = inst.id, pocket = n, to = pc.to },
		name = pc.name or (pc.to == "exit" and "Return gate" or "Acceleration gate") }
	body:setUserData(g)
	table.insert(self.entities, g)
	return g
end

-- Is a gate open? Says why not, if it isn't.
function Game:gateOpen(g)
	local u = g.unlock
	if not u then return true end
	local state = (Sites.list(self.universe)[g.site] or { pockets = {} }).pockets[g.pocket] or {}
	if u == "clear" then
		if state.cleared then return true end
		return false, "CLEAR THE HOSTILES"
	end
	if type(u) == "table" and u.kill then
		for _, e in ipairs(self.entities) do
			if e.kind == "ship" and e.siteTag == u.kill and not e.dead and not e.removed then return false, "DESTROY THE " .. u.kill:upper() end
		end
		return true
	end
	if type(u) == "table" and u.item then
		local p = self.player
		local have = p and p.hold and require("src.inventory.hold").count(p.hold, u.item) or 0
		if have > 0 then return true end
		local item = data.items[u.item]
		return false, "NEEDS " .. (item and item.name or u.item):upper()
	end
	return true
end

-- Fired from a gate (its launch is done): down a short lane to the next
-- pocket, or to the planet you came in from.
function Game:throughGate(gate)
	local u = self.universe
	local inst = Sites.list(u)[gate.site]
	local g = self:findGate(gate)
	local bearing = g and g.angle or 0
	if gate.to == "exit" or not inst then
		local back = inst and inst.from or Fields.start
		-- (a wildcat site closes only once its crew is beaten: W.cleared)
		local def = inst and Sites.template(inst)
		if def and not def.wild and gate.pocket == #def.pockets then inst.done = true end
		local length, au = T.siteLaneLength, 0
		if inst then length, au = Sites.laneLength(u, inst, back, u.clock) end
		self:launchTrip(back, nil, { bearing = bearing, length = length, au = au, gate = true })
		return
	end
	self:launchTrip(Sites.fieldId(inst.id, gate.to), nil, { bearing = bearing, length = T.gateLaneLength, gate = true })
end

function Game:findGate(gate)
	for _, e in ipairs(self.entities) do
		if e.gate == gate then return e end
	end
end

-- The site's hoard, in cargo containers round the middle of this pocket.
function Game:dropHoard(inst)
	local left = {}
	for id, n in pairs(inst.hoard or {}) do if n > 0 then left[id] = n end end
	inst.hoard = {}
	for _ = 1, 12 do
		if not next(left) then break end
		local x, y
		for _ = 1, 20 do
			local a, d = random() * pi * 2, 600 + random() * 1800
			x, y = cos(a) * d, sin(a) * d
			if self:isClear(x, y, 200) then break end
		end
		local e = self:spawnContainer(x, y, "cargo_container", false)
		local before = {}
		for id, n in pairs(left) do before[id] = n end
		left = require("src.inventory.hold").fill(e.hold, before, { random = random })
		e.loot = require("src.inventory.hold").totals(e.hold)
		self:containerMass(e)
	end
end

-- Into a site's first pocket, fired off a mass driver on `bearing` (else
-- straight there: the debug warp).
function Game:enterSite(instId, bearing)
	local inst = Sites.list(self.universe)[instId]
	if not inst then return false end
	if not Sites.of(self.fieldId) then inst.from = self.fieldId end
	local id = Sites.fieldId(inst.id, 1)
	if bearing then
		local length, au = Sites.laneLength(self.universe, inst, self.fieldId, self.universe.clock)
		self:launchTrip(id, nil, { bearing = bearing, length = length, au = au })
		return true
	end
	local rec = require("src.ship").record(self.player)
	local f = Fields[id]
	self.flash = { t = 0, life = 0.6 }
	self:loadField(id, { player = rec, at = { x = f.spawn[1], y = f.spawn[2], angle = -pi / 2, vx = 0, vy = -500 } })
	return true
end

-- Each step in a pocket: mark it cleared, and work the gates.
function Game:updateSites(dt)
	local siteId, n = Sites.of(self.fieldId)
	-- finished and expired sites close once you're out of them (not on the
	-- lane, where turning back would need the pocket you left)
	if not siteId then
		self.siteSettled = nil
		if not self.field.transit and self.sitesPrunedIn ~= self.fieldId then
			self.sitesPrunedIn = self.fieldId
			Sites.prune(self.universe, self.fieldId, self)
		end
		return
	end
	self.sitesPrunedIn = nil
	local inst = Sites.list(self.universe)[siteId]
	if not inst then return end
	local state = inst.pockets[n] or {}
	inst.pockets[n] = state
	if self.siteSettled ~= self.fieldId and self.player and not self.player.dead then
		self.siteSettled = self.fieldId
		-- nobody comes up inside a rock (rocks may be laid after they woke)
		require("src.wildcats").unstick(self)
		-- the way home is where you came in: off the driver you arrive on
		-- the far side from the planet's bearing, not at the map's spawn
		local px, py = self.player.body:getPosition()
		for _, g in ipairs(self.entities) do
			if g.autoExit then
				local gx, gy = g.body:getPosition()
				if (gx - px) ^ 2 + (gy - py) ^ 2 > 3000 ^ 2 then
					local d = math.sqrt(px * px + py * py)
					local ux, uy = d > 0 and px / d or 0, d > 0 and py / d or 1
					-- beside you, a little further in, pointing back out
					local bx, by = px - ux * 700 - uy * 900, py - uy * 700 + ux * 900
					local a = math.atan2(by, bx)
					g.angle = a
					g.body:setPosition(bx + math.cos(a) * g.barrel / 2, by + math.sin(a) * g.barrel / 2)
				end
			end
		end
	end
	if not state.cleared then
		local left = require("src.wildcats").held(self.universe, self.fieldId)
		for _, e in ipairs(self.entities) do
			if left then break end
			if e.kind == "ship" and e.siteEnemy and not e.dead and not e.removed then left = true end
		end
		if not left then
			state.cleared = true
			self:toast("POCKET CLEAR", 1.6)
			-- the last of the crew died here: the hoard is yours
			if inst.crew and not inst.done and require("src.wildcats").posted(self.universe, siteId) == 0 then
				self:dropHoard(inst)
				require("src.wildcats").cleared(self, self.universe, inst, "player")
				self:toast("SITE CLEARED", 2.5)
			end
		end
	end

end

end

return Sites
