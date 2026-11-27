--[[
	Notables: unique named people whose deaths change the world for good
	(cast and role rules in data/notables.lua; the effects go through
	src/worldstate.lua).

	They are not pilots. A notable is a record with a seat and a place
	they are at right now. They move only as VIP passengers: a 'passenger'
	offer on the shared board (src/passengers.lua P.postVIP) with item
	'vip', one seat, a high fare and a comfort and standing floor. NPC
	transports or the player carry them; a contract nobody takes means
	they travelled with their own staff, off the board.

	Journalists and magnates ride their circuit every so often. Leaders
	leave their seat only for summits at Ring Station: a few leaders at
	most summits, every leader at a grand one, announced in the news.

	How one ends (status, flag 'notable.<id>'):
	  dead      their carrier was destroyed by the player, or the player
	            spaced them (ejected the VIP from the hold: an airlock)
	  captured  the player cancelled their contract at another faction's
	            station: handed over
	A carrier lost to anyone else, or the player's own ship wrecked, and
	the notable gets away in a pod and goes home: the world only changes
	when the player chooses it.

	Saved as u.notables = { people = { [id] = { status, at, trip, next } }, summit }.
]]
local D = require("data.notables")
local WS = require("src.worldstate")
local L = require("src.locations")
local Tasks = require("src.tasks")
local N = { defs = {} }
for _, n in ipairs(D.cast) do N.defs[n.id] = n end
N.T = D.T

local function rng(u)
	local s = N.state(u)
	s.seed = (s.seed * 48271) % 2147483647
	return s.seed / 2147483647
end

function N.state(u)
	local s = u.notables
	if not s then
		s = { people = {}, seed = 104729, summit = nil }
		u.notables = s
	end
	local clock = u.clock or 0
	for i, n in ipairs(D.cast) do
		if not s.people[n.id] then
			s.people[n.id] = { status = "alive", at = n.seat,
				-- (staggered, so the cast doesn't all leave at once)
				next = clock + D.T.stay + i * 431 % D.T.tripEvery }
		end
	end
	s.summit = s.summit or { next = clock + D.summit.interval, n = 0 }
	return s
end
function N.person(u, id) return N.state(u).people[id] end
function N.alive(u, id) local p = N.person(u, id); return p and p.status == "alive" end
function N.flag(id) return "notable." .. id end

local function stationName(id) local p = L.byId[id]; return p and p.name or id end
local function factionName(f)
	local d = f and require("src.reputation").FACTIONS[f]
	return d and (d.name:gsub("^The ", "")) or "independent"
end
local function fill(t, v) return (t:gsub("{(%w+)}", function(k) return v[k] and tostring(v[k]) or "" end)) end

---------------------------------------------------------------- travel

-- Their next stop: the circuit, then home again.
local function nextStop(n, p)
	if p.at ~= n.seat then return n.seat end
	if #(n.circuit or {}) == 0 then return nil end
	p.leg = (p.leg or 0) % #n.circuit + 1
	return n.circuit[p.leg]
end
local function depart(u, n, p, target, clock, why)
	if not target or target == p.at then return end
	local o = require("src.passengers").postVIP(u, n, p.at, target, clock)
	if o then
		p.trip = { offer = o.id, to = target, why = why }
		WS.note(u, "travel", ("%s posts a VIP run %s -> %s"):format(n.name, stationName(p.at), stationName(target)), { notable = n.id })
	else
		-- no route there now: go off-board
		p.at = target
	end
end
local function arrive(u, n, p, station, how)
	p.at, p.trip = station, nil
	p.next = (u.clock or 0) + D.T.stay + rng(u) * D.T.tripJitter
	WS.note(u, "travel", ("%s arrived at %s (%s)"):format(n.name, stationName(station), how), { notable = n.id })
end

-- Called by the passenger task when a VIP party gets off at its target.
function N.delivered(u, t, r, station)
	local n, p = N.defs[t.notable], N.person(u, t.notable)
	if not (n and p and p.status == "alive") then return end
	arrive(u, n, p, station, r and r.player and "the player flew them" or "by transport")
	if r and r.player then require("src.reputation").addStanding(u, n.faction, D.T.deliverStanding) end
end

-- The contract ended with them off the ship somewhere other than its
-- target (a cancelled job): they stay there and go on from there.
function N.leftAt(u, id, station)
	local n, p = N.defs[id], N.person(u, id)
	if n and p and p.status == "alive" then arrive(u, n, p, station, "left the ship") end
end

-- A trip that never happened: nobody took the run before it expired,
-- or the carrier gave up before boarding them. They stay where they are
-- and miss it. A missed summit is an event (and a flag on the summit
-- record) quests can hang on.
local function missed(u, n, p, clock)
	local trip = p.trip
	p.trip, p.next = nil, clock + D.T.stay
	WS.note(u, "travel", ("%s missed their %s run to %s"):format(n.name, trip.why or "", stationName(trip.to)), { notable = n.id })
	if trip.why == "summit" then
		local sm = N.state(u).summit
		sm.missed = sm.missed or {}
		sm.missed[#sm.missed + 1] = n.id
		for i, id in ipairs(sm.attendees or {}) do if id == n.id then table.remove(sm.attendees, i); break end end
		WS.note(u, "summit", ("%s will miss the summit"):format(n.name), { notable = n.id })
		require("src.events").emit("notable_missed_summit", n.id, sm.n)
	end
end
-- They're aboard a ship whose contract lapsed (src/player_contracts.lua):
-- whoever has them aboard still has them until the next dock.
function N.held(u, id)
	local p = N.person(u, id)
	if p and p.trip then p.trip.held = true end
end
local function settleTrips(u, clock)
	local offers = Tasks.state(u).offers
	for id, p in pairs(N.state(u).people) do
		local n = N.defs[id]
		if n and p.status == "alive" and p.trip and not p.trip.held and not offers[p.trip.offer] then missed(u, n, p, clock) end
		-- a carrier that took the run and never finished it in time: it
		-- gives them up (aboard, they get off where it is; src/passengers.lua)
		local o = n and p.trip and not p.trip.held and offers[p.trip.offer]
		if o and o.owner and o.owner ~= "player" and clock > (o.deadline or math.huge) then
			local r = u.npcs and u.npcs[o.owner]
			if r and r.task and r.task.id == o.id then Tasks.release(u, r, "VIP run overdue", clock) else offers[o.id] = nil end
		end
	end
end

---------------------------------------------------------------- summits

local function leaders(u)
	local out = {}
	for _, n in ipairs(D.cast) do
		if n.role == "leader" then out[#out + 1] = n end
	end
	return out
end
local function announce(u, sm, clock)
	sm.n = sm.n + 1
	local grand = sm.n % D.summit.grandEvery == 0
	local pool = leaders(u)
	local picked = {}
	if grand then picked = pool
	else
		local want = D.summit.small[1] + math.floor(rng(u) * (D.summit.small[2] - D.summit.small[1] + 1))
		local left = {}
		for _, n in ipairs(pool) do left[#left + 1] = n end
		while #picked < want and #left > 0 do
			picked[#picked + 1] = table.remove(left, 1 + math.floor(rng(u) * #left))
		end
	end
	sm.attendees, sm.grand, sm.opens = {}, grand, clock + D.summit.lead
	sm.missed = {}   -- who was invited and never made it (src/notables.lua missed)
	sm.closes = sm.opens + D.summit.length
	local names, empty = {}, 0
	for _, n in ipairs(picked) do
		local p = N.person(u, n.id)
		if p.status == "alive" then
			sm.attendees[#sm.attendees + 1] = n.id
			names[#names + 1] = n.name
			if not p.trip then depart(u, n, p, D.summit.station, clock, "summit") end
		else empty = empty + 1 end
	end
	local headline = grand and D.headlines.summit[2] or fill(D.headlines.summit[1], { names = table.concat(names, ", ") })
	if grand and empty > 0 then headline = headline .. (" (%d empty chair%s)"):format(empty, empty > 1 and "s" or "") end
	WS.note(u, "summit", headline, { grand = grand })
	local News = require("src.news")
	for _, o in ipairs(News.order) do
		News.publish(u, { outlet = o, kind = "summit", headline = headline, station = D.summit.station, area = L.byId[D.summit.station].area, quest = true })
	end
end
local function updateSummit(u, clock)
	local sm = N.state(u).summit
	if not sm.opens and clock >= sm.next - D.summit.lead then announce(u, sm, clock) end
	if sm.opens and clock >= sm.closes then
		-- the session is over: everyone who made it goes home
		for _, id in ipairs(sm.attendees or {}) do
			local n, p = N.defs[id], N.person(u, id)
			if p.status == "alive" and not p.trip and p.at ~= n.seat then depart(u, n, p, n.seat, clock, "home") end
		end
		WS.note(u, "summit", "The summit closes")
		sm.opens, sm.closes, sm.attendees, sm.grand = nil, nil, nil, nil
		sm.next = clock + D.summit.interval
	end
end

function N.update(u, clock)
	local s = N.state(u)
	settleTrips(u, clock)
	updateSummit(u, clock)
	local sm = s.summit
	for _, n in ipairs(D.cast) do
		local p = s.people[n.id]
		if p.status == "alive" and not p.trip and clock >= (p.next or 0) then
			if n.role == "leader" then
				-- a leader left somewhere (a summit ended while they were busy) goes home
				local attending = false
				for _, id in ipairs(sm.attendees or {}) do if id == n.id then attending = true end end
				if not attending and p.at ~= n.seat then depart(u, n, p, n.seat, clock, "home") end
			else
				depart(u, n, p, nextStop(n, p), clock, "circuit")
				p.next = clock + D.T.tripEvery + rng(u) * D.T.tripJitter
			end
		end
	end
end

---------------------------------------------------------------- endings

local function headlines(u, n, kind, station)
	local News, Rep = require("src.news"), require("src.reputation")
	local Outlets = require("data.outlets").outlets
	local vars = { name = n.name, office = n.office, faction = factionName(n.faction), station = station and stationName(station) }
	local area = L.byId[n.seat] and L.byId[n.seat].area
	for i, o in ipairs(News.order) do
		local owner = Outlets[o].owner
		local set
		if kind == "captured" then set = D.headlines.captured
		elseif owner == n.faction then set = D.headlines.own
		elseif Rep.stance(owner, n.faction, u) == "hostile" or Outlets[o].outlaw then set = D.headlines.hostile
		else set = D.headlines.other end
		News.publish(u, { outlet = o, kind = "notable", headline = fill(set[(i + #n.name) % #set + 1], vars),
			area = area, station = n.seat, faction = n.faction, quest = true, notable = n.id })
	end
end

-- What the player's part costs (or earns) them. witnessed: the victim's
-- faction saw it; otherwise it goes out as a deed the papers may pin on
-- them, and they are the obvious suspect.
local function blame(u, n, area, witnessed)
	local Rep, News = require("src.reputation"), require("src.news")
	local delta = D.roles[n.role].deed
	if witnessed then
		Rep.addStanding(u, n.faction, delta)
		Rep.addHeat(u, n.seat, D.T.heat)
	end
	News.deed(u, { faction = n.faction, delta = delta, area = area, kind = "killed", witnessed = witnessed, suspect = true, notable = n.id })
	-- whoever is at odds with their faction is quietly grateful
	for _, f in ipairs(Rep.ORDER) do
		if f ~= n.faction and Rep.stance(f, n.faction, u) == "hostile" then
			Rep.addReported(u, f, math.min(D.T.reportedCap, -delta * .4))
		end
	end
end

local function finish(u, id, status, ctx)
	local n, p = N.defs[id], N.person(u, id)
	if not (n and p and p.status == "alive") then return false end
	p.status, p.trip, p.endedAt, p.how = status, nil, u.clock or 0, ctx.how
	p.at = ctx.station or p.at
	WS.set(u, N.flag(id), status, ctx.how)
	WS.note(u, "notable", ("%s (%s) %s: %s"):format(n.name, n.role, status, ctx.how), { notable = id, by = ctx.by })
	local source = N.flag(id)
	for _, e in ipairs(D.consequences(n)) do WS.apply(u, e, source) end
	headlines(u, n, status, ctx.station)
	if ctx.by == "player" then blame(u, n, ctx.area, ctx.witnessed) end
	require("src.notify").post(u, { kind = "news", title = status == "dead" and "Death of a notable" or "Notable captured",
		text = ("%s, %s, %s"):format(n.name, n.office, status == "dead" and "is dead" or "has been handed over") })
	require("src.events").emit("notable_" .. status, id, ctx)
	return true
end
function N.kill(u, id, ctx) ctx = ctx or {}; return finish(u, id, "dead", ctx) end

-- Would the faction that owns station take this notable off your hands?
-- The powers aren't at odds enough to hold each other's people. The
-- cartel will hold anyone's for ransom, and a power hostile to the cartel
-- will arrest a cartel notable.
function N.takesCaptive(u, id, station)
	local n = N.defs[id]
	local Rep = require("src.reputation")
	local captor = n and Rep.ofNode(L.canonical(station))
	if not captor or captor == n.faction then return false end
	if captor == Rep.CARTEL then return true end
	return n.faction == Rep.CARTEL and Rep.stance(captor, Rep.CARTEL, u) == "hostile"
end
-- Handed over at station by the player: out of office for good, and the
-- faction holding them is grateful. Their own faction knows who had them.
function N.capture(u, id, station)
	local n = N.defs[id]
	if not n or not N.takesCaptive(u, id, station) then return false end
	local Rep = require("src.reputation")
	local captor = Rep.ofNode(L.canonical(station))
	local area = L.byId[station] and L.byId[station].area
	local ok = finish(u, id, "captured", { how = "handed over at " .. stationName(station), station = station, by = "player",
		area = area, witnessed = true })
	if ok and captor and captor ~= n.faction then Rep.addStanding(u, captor, -D.roles[n.role].deed * .3) end
	return ok
end

-- An NPC carrying a notable died (src/simulation_history.lua H.death).
function N.carrierDied(u, r, work, killer, area)
	local id = work and work.notable
	if not id or not N.alive(u, id) then return end
	if work.phase ~= "delivery" then return end
	if killer == "player" then
		local Rep = require("src.reputation")
		N.kill(u, id, { how = "their transport was destroyed by the player", by = "player", area = area,
			witnessed = Rep.ofArea(area) == N.defs[id].faction })
	else
		local n, p = N.defs[id], N.person(u, id)
		arrive(u, n, p, work.source, "escaped their transport in a pod")
	end
end

-- The player's own ship was wrecked with them aboard: a pod again.
function N.survived(u, id, station)
	local n, p = N.defs[id], N.person(u, id)
	if n and p and p.status == "alive" then arrive(u, n, p, station or n.seat, "escaped the wreck in a pod") end
end

-- The player pushed the VIP out of the hold (src/game.lua Game:eject).
function N.airlock(game)
	local C = require("src.player_contracts")
	local t = C.active(game)
	if not (t and t.notable) then return false end
	local u, n = game.universe, N.defs[t.notable]
	-- their faction booked them onto your ship: it knows who did it, wherever it happened
	C.endVIP(game, "spaced")
	return N.kill(u, n.id, { how = "spaced from the player's airlock", by = "player", area = game.fieldId, witnessed = true })
end

-- Debug lines (F1 debug view, soak dumps).
function N.report(u)
	local s = N.state(u)
	local out = { "Notables" }
	for _, n in ipairs(D.cast) do
		local p = s.people[n.id]
		local where = p.trip and ("-> " .. stationName(p.trip.to)) or ("at " .. stationName(p.at))
		out[#out + 1] = ("  %-22s %-10s %-8s %s"):format(n.name, n.role, p.status, p.status == "alive" and where or "")
	end
	local sm = s.summit
	out[#out + 1] = sm.opens and ("  summit%s opens in %ds"):format(sm.grand and " (grand)" or "", math.floor(sm.opens - (u.clock or 0)))
		or ("  next summit in %ds"):format(math.floor(sm.next - (u.clock or 0)))
	return out
end

return N
