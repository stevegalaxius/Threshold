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

local GATE_RADIUS, GATE_CHARGE = 260, 1.2

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
			name = pk.name or def.name, radius = pk.radius or 7000,
			spawn = pk.spawn or { 0, (pk.radius or 7000) * 0.4 },
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

-- Put every saved site's fields back (after loading a save).
function Sites.restore(u)
	for _, inst in pairs(Sites.list(u)) do Sites.register(inst) end
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
		discovered = opts.discovered or not def.hidden, pockets = {} }
	Sites.list(u)[id] = inst
	Sites.register(inst)
	return inst
end

-- Close a site: its fields and saved pockets go.
function Sites.close(u, inst)
	Sites.unregister(inst)
	for n = 1, #(Sites.template(inst) or { pockets = {} }).pockets do
		if u.areas then u.areas[Sites.fieldId(inst.id, n)] = nil end
	end
	Sites.list(u)[inst.id] = nil
end

-- Close expired sites, except the one you're in (it closes once you leave).
function Sites.prune(u, here)
	local inside = Sites.of(here)
	for id, inst in pairs(Sites.list(u)) do
		local gone = not Sites.template(inst) or (inst.expires and (u.clock or 0) >= inst.expires) or inst.done
		if gone and id ~= inside then Sites.close(u, inst) end
	end
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

-- Where a site is, in AU from the Sun: a little way off its home planet,
-- riding round with it.
function Sites.position(inst, clock)
	local x, y = Fields.orbitPos(inst.home, clock)
	return x + cos(inst.bearing) * 0.25, y + sin(inst.bearing) * 0.25
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

function builders.enemies(game, pc, ctx)
	if ctx.state.cleared then return end
	for _, g in ipairs(pc.groups or {}) do
		for _ = 1, g[2] or 1 do
			local x, y
			for _ = 1, 20 do
				x, y = around(pc, game)
				if game:isClear(x, y, 150) then break end
			end
			local e = game:spawnEnemy(g[1], x, y, { idle = true })
			if e then e.siteEnemy, e.siteTag = true, pc.tag end
		end
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

function builders.gate(game, pc, ctx) game:spawnSiteGate(ctx.inst, ctx.n, pc) end

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
		game:spawnSiteGate(inst, n, { to = "exit", x = sx + 900, y = sy + 300 })
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

function Game:spawnSiteGate(inst, n, pc)
	local body = love.physics.newBody(self.world, pc.x or 0, pc.y or 0, "kinematic")
	local def = Sites.template(inst)
	local g = { kind = "gate", invulnerable = true, id = self:nextId(), team = 0, body = body,
		radius = GATE_RADIUS, site = inst.id, pocket = n, to = pc.to, unlock = pc.unlock,
		color = def.color, charge = 0,
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

-- Fire the player through a gate: to the next pocket, or home.
function Game:throughGate(g)
	local u = self.universe
	local inst = Sites.list(u)[g.site]
	local Ship = require("src.ship")
	local rec = Ship.record(self.player)
	require("src.ui.cargo").close(self)
	self.flash = { t = 0, life = 0.5 }
	if g.to == "exit" or not inst then
		local back = inst and inst.from or Fields.start
		if inst and g.pocket == #Sites.template(inst).pockets then inst.done = true end
		self:loadField(back, { player = rec, at = { driver = back } })
		Sites.prune(u, self.fieldId)
		return
	end
	local id = Sites.fieldId(inst.id, g.to)
	local f = Fields[id]
	self:loadField(id, { player = rec, at = { x = f.spawn[1], y = f.spawn[2], angle = -pi / 2, vx = 0, vy = -300 } })
end

-- Into a site's first pocket, off a mass driver.
function Game:enterSite(instId)
	local inst = Sites.list(self.universe)[instId]
	if not inst then return false end
	if not Sites.of(self.fieldId) then inst.from = self.fieldId end
	local rec = require("src.ship").record(self.player)
	local f = Fields[Sites.fieldId(inst.id, 1)]
	self.flash = { t = 0, life = 0.6 }
	self:loadField(Sites.fieldId(inst.id, 1), { player = rec, at = { x = f.spawn[1], y = f.spawn[2], angle = -pi / 2, vx = 0, vy = -500 } })
	return true
end

-- Each step in a pocket: mark it cleared, and work the gates.
function Game:updateSites(dt)
	local siteId, n = Sites.of(self.fieldId)
	if not siteId then return end
	local inst = Sites.list(self.universe)[siteId]
	if not inst then return end
	local state = inst.pockets[n] or {}
	inst.pockets[n] = state
	if not state.cleared then
		local left = false
		for _, e in ipairs(self.entities) do
			if e.kind == "ship" and e.siteEnemy and not e.dead and not e.removed then left = true break end
		end
		if not left then
			state.cleared = true
			self:toast("POCKET CLEAR", 1.6)
		end
	end
	local p = self.player
	if not p or p.dead or p.dockState then return end
	local px, py = p.body:getPosition()
	for _, g in ipairs(self.entities) do
		if g.kind == "gate" then
			local gx, gy = g.body:getPosition()
			local inside = (px - gx) ^ 2 + (py - gy) ^ 2 < g.radius ^ 2
			if inside then
				local open, why = self:gateOpen(g)
				if open then
					g.charge = g.charge + dt
					self:shake(0.05 * g.charge)
					if g.charge >= GATE_CHARGE then g.charge = 0; self:throughGate(g); return end
				elseif not g.warned then
					g.warned = true
					self:toast("GATE LOCKED: " .. why, 2)
				end
			else
				g.charge, g.warned = 0, nil
			end
		end
	end
end

end

return Sites
