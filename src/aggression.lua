-- Recent attacks, shared by physical combat, offscreen rounds and dispatch.
-- The save holds a fixed-size ring. Direct lookups use a transient index
-- reconstructed on first use. Hits and target checks never walk the ring.
local T = require("src.tuning")
local A = {capacity = 256}
local indexes = setmetatable({}, {__mode = "k"})

local function indexEntry(index, entry)
	local area = index[entry.area]
	if not area then area = {}; index[entry.area] = area end
	local byVictim = area[entry.attacker]
	if not byVictim then byVictim = {}; area[entry.attacker] = byVictim end
	byVictim[entry.victim] = entry
end

local function indexFor(state)
	local index = indexes[state]
	if not index then
		index = {}
		for _, entry in pairs(state.slots) do indexEntry(index, entry) end
		indexes[state] = index
	end
	return index
end

local function lookup(index, attacker, victim, area)
	local byArea = index[area]
	local byVictim = byArea and byArea[attacker]
	return byVictim and byVictim[victim]
end

local function fresh(entry, clock)
	return entry and clock >= entry.firstAt and clock-entry.lastAt < T.aggressionWindow
end

function A.find(u, attacker, victim, area, clock)
	local state = u.aggression
	if not state or not attacker or not victim or not area then return end
	local entry = lookup(indexFor(state), attacker, victim, area)
	if fresh(entry, clock) then return entry end
end

function A.record(u, attacker, victim, area, clock, cause, node)
	if not attacker or not victim or attacker == victim or not area then return end
	local state = u.aggression
	if not state then state = {slots = {}, nextSlot = 1}; u.aggression = state end
	local index = indexFor(state)
	local entry = lookup(index, attacker, victim, area)
	if entry and clock < entry.lastAt then return end
	if fresh(entry, clock) then
		entry.lastAt = clock
		entry.cause = cause
		entry.node = node or entry.node
		return entry
	end

	local slot = state.nextSlot
	local old = state.slots[slot]
	if old then
		local byArea = index[old.area]
		local byVictim = byArea and byArea[old.attacker]
		if byVictim and byVictim[old.victim] == old then
			byVictim[old.victim] = nil
			if not next(byVictim) then byArea[old.attacker] = nil end
			if not next(byArea) then index[old.area] = nil end
		end
	end
	entry = {attacker=attacker, victim=victim, area=area, firstAt=clock, lastAt=clock, cause=cause, node=node}
	state.slots[slot] = entry
	state.nextSlot = slot % A.capacity + 1
	indexEntry(index, entry)
	return entry
end

-- Export only recent entries, in insertion order. This is the only regular
-- full scan, and runs on save rather than in the simulation update.
function A.snapshot(u)
	local state = u.aggression
	if not state then return end
	local copy = require("src.persistence").copy
	local entries = {}
	for i=0,A.capacity-1 do
		local entry = state.slots[(state.nextSlot+i-1) % A.capacity + 1]
		if fresh(entry, u.clock) then entries[#entries+1] = copy(entry) end
	end
	if #entries > 0 then return {slots=entries, nextSlot=#entries % A.capacity + 1} end
end

function A.migrate(u, attacker)
	local raid = attacker.lastRaid
	if not raid then return end
	attacker.lastRaid = nil
	local victim = raid.victim
	if not victim and attacker.encounter and not attacker.encounter.support then
		local other = u.npcs and u.npcs[attacker.encounter.target]
		if other and other.area == raid.area and other.encounter and other.encounter.target == attacker.id then
			victim = other.id
		end
	end
	if victim and raid.area and raid.clock and u.clock-raid.clock < T.aggressionWindow then
		local entry = A.record(u, attacker.id, victim, raid.area, raid.clock, "raid")
		if entry then entry.reportedAt, entry.dispatched = raid.clock, raid.alerted end
	end
end

return A
