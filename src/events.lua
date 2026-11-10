--[[
	A tiny event bus. Game code emits events; anything (later: mod scripts,
	prototype-module hooks, sound, achievements) can listen without the
	game code knowing about it.

	    events.on("kill", function(victim, killer) ... end)
	    events.emit("kill", victim, killer)

	Events emitted so far: fire, hit, kill, pickup, eject, death, dock,
	undock, travel (from, to), swapship (ship, station), buyship and sellship (record,
	station).
	Simulation history also emits simulation_outcome(entry), a plain-data copy of
	a saved observation shared by online and offline simulation. Its kinds:
	combat_started, combat_ended (aggressor, dead, fled, wrecks), npc_died,
	wreck_created, freight_delivered (task, cargo, route and payment), fuel_condition_changed, rescued (victim saved by killing
	its attacker), docked, undocked, left_area, arrived. Each has a clock,
	area, node (when known) and participant ids ('player' for you).
	Quests and random events read the same log with
	simulation_history.recent(u, { kind, node, area, participant, since }).
	Civilian scavenging emits salvage_sale(npcId, stationId, itemCounts, credits).
	Keep this list small and stable: it's going to be the modding API.
]]

local events = { listeners = {} }

function events.on(name, fn)
	events.listeners[name] = events.listeners[name] or {}
	table.insert(events.listeners[name], fn)
	return fn
end

function events.off(name, fn)
	local list = events.listeners[name]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
end

function events.emit(name, ...)
	local list = events.listeners[name]
	if not list then return end
	for i = 1, #list do list[i](...) end
end

return events
