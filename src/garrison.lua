--[[
	Garrisons: site enemies are real A-Life NPCs.

	A site's enemy groups no longer spawn throwaway ships. Each enemy is an
	ordinary NPC record in universe.npcs (a pirate by template, with a rank,
	a personality and a home), carrying a garrison duty:

	  r.garrison = { site, pocket, field, x, y, tag }

	While it has the duty it lives in the pocket: it holds its post offline,
	wakes there when you come near, and fights with its enemy archetype's
	combat AI. Damage, ammo and cargo stay on the record between visits.

	The duty ends (G.release) when the ship runs from the fight, when it's
	badly hurt and you've left, or when its site closes. Then it's moved out
	to the site's home planet and runs the pirate brain like any other: it
	heads home to repair, raids, fences loot. So the ones you let go are the
	ones you meet again later.

	A revisited pocket keeps whoever is still guarding it and tops each group
	back up to the template's count with new recruits.
]]

local data = require("src.data")
local T = require("src.tuning")
local L = require("src.locations")
local Fields = require("src.fields")

local G = {}

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

local function alive(r) return r and r.state ~= "dead" and r.state ~= "escaped" end

-- Living garrison records of one pocket (optionally one enemy group / tag).
function G.members(u, field, enemy, tag)
	local out = {}
	for _, r in pairs(u.npcs or {}) do
		local g = r.garrison
		if g and g.field == field and alive(r) and (not enemy or r.archetype == enemy) and (tag == nil or g.tag == tag) then
			out[#out + 1] = r
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Is anyone still holding this pocket?
function G.held(u, field) return #G.members(u, field) > 0 end

-- A new garrison NPC for a site pocket at (x, y), flying enemy `enemy`.
function G.recruit(game, inst, pocket, enemy, x, y, tag)
	local u = game.universe
	local def = assert(data.enemies[enemy], "unknown enemy " .. tostring(enemy))
	local hull = data.hulls[def.hull]
	local Stats = require("src.stats")
	local loadout = copy(def.loadout or hull.loadout)
	local field = require("src.sites").fieldId(inst.id, pocket)
	u.nextNpcId = (u.nextNpcId or 0) + 1
	local clock = u.clock or 0
	local r = {
		id = "npc/" .. u.nextNpcId, area = field, home = inst.home, archetype = enemy,
		speed = require("src.npc").cruise(enemy), spread = 0,
		route = {}, index = 1, state = "garrison", untilTime = clock,
		ship = { hull = def.hull, loadout = loadout, cargo = copy(def.cargo or {}), armor = Stats.compute(hull, loadout).armor },
		garrison = { site = inst.id, pocket = pocket, field = field, x = x, y = y, tag = tag },
		rank = require("src.npc_rank").roll(),
		spawnedAt = clock, spawnOrigin = "garrison",
	}
	require("src.npc_templates").apply(r, "pirate", inst.home)
	require("src.personality").ensure(r)
	require("src.npc_home").choose(u, r)
	require("src.supplies").provision(r)
	u.npcs[r.id] = r
	require("src.alife_trace").note(r, clock, "garrison", "recruited for " .. inst.id .. " pocket " .. pocket)
	return r
end

-- Fill a pocket's groups up to the template's counts. Survivors stay; new
-- recruits make up the difference. Returns the records now guarding it.
function G.muster(game, inst, pocket, pc, place)
	local u = game.universe
	local field = require("src.sites").fieldId(inst.id, pocket)
	for _, grp in ipairs(pc.groups or {}) do
		local have = #G.members(u, field, grp[1], pc.tag or false)
		for _ = have + 1, grp[2] or 1 do
			local x, y = place()
			G.recruit(game, inst, pocket, grp[1], x, y, pc.tag or false)
		end
	end
end

-- Where a released NPC rejoins the world: a station or buoy of the site's
-- home planet.
local function rejoinNode(r)
	local home = r.home
	local node = L.station(home, "pirateBase") or L.station(home, "trade")
	if node then return node.id or node end
	local f = Fields[home]
	return f and (f.buoyIds and f.buoyIds[1] or f.stationIds and f.stationIds[1])
end

-- End the duty: the NPC leaves the pocket for its home planet and goes on
-- living as an ordinary pirate.
function G.release(game, r, reason)
	if not r or not r.garrison then return false end
	local u = game.universe
	local clock = u.clock or 0
	local node = rejoinNode(r)
	if not node then r.state = "escaped"; r.garrison = nil; return false end
	local from = r.garrison
	r.garrison = nil
	r.area = r.home
	r.route, r.index, r.node, r.state, r.untilTime = { node, node }, 1, node, "idle", clock
	r.pose, r.offset, r.savedOnline = nil, nil, nil
	r.taskWorker = true
	r.veteranOf = { site = from.site, reason = reason, clock = clock }
	require("src.alife_trace").note(r, clock, "garrison", ("left %s (%s)"):format(from.site, reason or "released"))
	local hurt = r.ship and r.ship.armor and data.hulls[r.ship.hull] and
		r.ship.armor < require("src.stats").compute(data.hulls[r.ship.hull], r.ship.loadout).armor * T.pirateRetreatHealth
	if hurt or reason == "fled" then
		local ok = pcall(require("src.piracy").returnRecord, game, r)
		if ok then return true end
	end
	require("src.npc").advance(r, clock, u, game)
	return true
end

-- Release every garrison of a site (it closed).
function G.disband(game, siteId, reason)
	for _, r in pairs(game.universe.npcs or {}) do
		if r.garrison and r.garrison.site == siteId and alive(r) then G.release(game, r, reason) end
	end
end

-- Offline tick for a garrisoned record. Returns true when it handled it.
function G.advance(r, clock, u, game)
	local g = r.garrison
	if not g then return false end
	local inst = require("src.sites").list(u)[g.site]
	if not inst then
		if game then G.release(game, r, "site closed") else r.garrison = nil end
		return true
	end
	-- badly hurt and nobody's in the pocket to stop it: it goes for repairs
	if game and game.fieldId ~= g.field and r.ship and r.ship.armor then
		local hull = data.hulls[r.ship.hull]
		local full = hull and require("src.stats").compute(hull, r.ship.loadout).armor
		if full and r.ship.armor < full * T.pirateRetreatHealth then G.release(game, r, "retreat") end
	end
	return true
end

function G.point(r)
	local g = r.garrison
	if g then return g.x, g.y end
end

-- Set up a woken garrison ship: it waits at its post and fights like its
-- enemy archetype.
function G.woke(game, e, r)
	local g = r.garrison
	if not g then return false end
	local def = data.enemies[r.archetype]
	e.team = def.team or 2
	e.aggro = false
	e.siteEnemy, e.siteTag = true, g.tag or nil
	e.route = nil
	return true
end

return G
