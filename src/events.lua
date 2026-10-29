--[[
	A tiny event bus. Game code emits events; anything (later: mod scripts,
	prototype-module hooks, sound, achievements) can listen without the
	game code knowing about it.

	    events.on("kill", function(victim, killer) ... end)
	    events.emit("kill", victim, killer)

	Events emitted so far: fire, hit, kill, pickup, death.
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
