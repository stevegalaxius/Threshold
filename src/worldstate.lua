--[[
	The world-state ledger: the one place permanent story consequences live.

	Rule: nothing changes the world directly. An event (a notable killed,
	later a quest outcome) sets a flag, writes a line in the log, and
	applies effects. A lasting effect is a named, sourced modifier kept
	here; the systems it bends ask for it instead of being edited:

	  WS.mul(u,'output',station,facility)   src/industry.lua   I.scale
	  WS.mul(u,'price',station,item)        src/markets.lua    C.price
	  WS.mul(u,'outlet_reach',outlet)       src/news.lua       runs and nudges
	  WS.beats(u)                           src/news.lua       N.beat, N.covers
	  WS.mul(u,'patrols','faction:<id>')    src/security.lua   police wanted per system
	  WS.mul(u,'inspections','faction:<id>') src/squads.lua    how long a squad holds at each stop

	So every effect in the game can be traced to the event that caused it
	(WS.report, the World State debug view), and two events never fight
	over one variable: multipliers just stack.

	Effects (WS.apply):
	  { kind='mul',    target=, where=, sub=, by= }  lasting multiplier;
	        where is a station, an outlet, or 'faction:<id>' (every station
	        it owns); sub narrows it (a facility, an item), nil means all
	  { kind='beat',   outlet=, from= }              outlet takes over from's beat
	  { kind='stance', a=, b=, to= }                 Rep.setStance, for good
	  { kind='shock',  where=, item=, size=, duration= }   one-off News.shock
	  { kind='flag',   flag=, value= }               set another flag

	Saved as u.worldstate = { flags, log, mods }. The lookup index is
	rebuilt from mods and never saved.
]]
local WS = {}

WS.TARGETS = { output = true, price = true, outlet_reach = true, patrols = true, inspections = true }
WS.STANCES = { neutral = true, ambivalent = true, hostile = true, friendly = true }

function WS.state(u)
	local s = u.worldstate
	if not s then s = { flags = {}, log = {}, mods = {} }; u.worldstate = s end
	s.flags, s.log, s.mods = s.flags or {}, s.log or {}, s.mods or {}
	return s
end

---------------------------------------------------------------- flags and log

function WS.flag(u, name) return u.worldstate and u.worldstate.flags[name] end
function WS.note(u, kind, text, data)
	local s = WS.state(u)
	local e = { clock = u.clock or 0, kind = kind, text = text }
	if data then for k, v in pairs(data) do e[k] = v end end
	s.log[#s.log + 1] = e
	return e
end
function WS.set(u, name, value, cause)
	local s = WS.state(u)
	local old = s.flags[name]
	if old == value then return false end
	s.flags[name] = value
	WS.note(u, "flag", ("%s: %s -> %s"):format(name, tostring(old), tostring(value)), { flag = name, value = value, cause = cause })
	return true
end

---------------------------------------------------------------- the index

local cache = setmetatable({}, { __mode = "k" })
local function index(u)
	local s = u.worldstate
	if not s then return nil end
	local i = cache[u]
	if i and i.n == #s.mods then return i end
	i = { n = #s.mods, mul = {}, beats = {} }
	for _, m in ipairs(s.mods) do
		if m.kind == "mul" then
			local t = i.mul[m.target] or {}; i.mul[m.target] = t
			local key = m.where .. "|" .. (m.sub or "*")
			t[key] = (t[key] or 1) * m.by
		elseif m.kind == "beat" then
			i.beats[m.outlet] = i.beats[m.outlet] or {}
			i.beats[m.outlet][m.from] = true
		end
	end
	cache[u] = i
	return i
end

-- The product of every lasting multiplier on target at where (and sub).
-- A station also takes its owner's faction-wide ones.
function WS.mul(u, target, where, sub)
	local i = index(u)
	local t = i and i.mul[target]
	if not t or not where then return 1 end
	local v = (t[where .. "|*"] or 1)
	if sub then v = v * (t[where .. "|" .. sub] or 1) end
	if where:match("^station:") then
		local f = require("src.reputation").ofNode(require("src.locations").canonical(where))
		if f then
			v = v * (t["faction:" .. f .. "|*"] or 1)
			if sub then v = v * (t["faction:" .. f .. "|" .. sub] or 1) end
		end
	end
	return v
end
-- outlet -> { [outlet whose beat it took over] = true }
function WS.beats(u)
	local i = index(u)
	return i and i.beats or {}
end

---------------------------------------------------------------- effects

local function stationsOf(where)
	local L = require("src.locations")
	local f = where:match("^faction:(.+)$")
	if not f then return L.byId[where] and { where } or {} end
	local Rep, out = require("src.reputation"), {}
	for id, place in pairs(L.byId) do
		if place.kind == "station" and not place.accessOf and Rep.ofNode(id) == f then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end
WS.stationsOf = stationsOf

-- Is effect e well formed and does everything it names exist? Returns
-- true, or false and why. (tests/notables.lua runs it over the whole cast.)
function WS.validate(e)
	local L, Rep = require("src.locations"), require("src.reputation")
	local Outlets, data = require("data.outlets").outlets, require("src.data")
	local function place(w)
		if type(w) ~= "string" then return false end
		local f = w:match("^faction:(.+)$")
		if f then return Rep.FACTIONS[f] ~= nil end
		return L.byId[w] ~= nil
	end
	if e.kind == "mul" then
		if not WS.TARGETS[e.target] then return false, "unknown target " .. tostring(e.target) end
		if type(e.by) ~= "number" or e.by < 0 then return false, "bad multiplier" end
		if e.target == "outlet_reach" then
			if not Outlets[e.where] then return false, "unknown outlet " .. tostring(e.where) end
		elseif not place(e.where) then return false, "unknown place " .. tostring(e.where) end
		if e.target == "output" and e.sub and not e.where:match("^faction:") then
			if not require("src.industry").installations(e.where)[e.sub] then
				return false, ("%s has no facility %s"):format(e.where, e.sub)
			end
		end
		if e.target == "price" and e.sub and not data.items[e.sub] then return false, "unknown item " .. e.sub end
		return true
	elseif e.kind == "beat" then
		if not Outlets[e.outlet] or not Outlets[e.from] then return false, "unknown outlet" end
		return true
	elseif e.kind == "stance" then
		if not (Rep.FACTIONS[e.a] and Rep.FACTIONS[e.b]) or e.a == e.b then return false, "bad faction pair" end
		if not WS.STANCES[e.to] then return false, "unknown stance " .. tostring(e.to) end
		return true
	elseif e.kind == "shock" then
		if not place(e.where) then return false, "unknown place " .. tostring(e.where) end
		if not data.items[e.item] then return false, "unknown item " .. tostring(e.item) end
		return true
	elseif e.kind == "flag" then
		return type(e.flag) == "string", "flag needs a name"
	end
	return false, "unknown effect " .. tostring(e.kind)
end

-- Apply effect e for source (the flag or event that caused it).
function WS.apply(u, e, source)
	local ok, why = WS.validate(e)
	if not ok then
		WS.note(u, "error", ("%s: skipped effect (%s)"):format(source, why))
		return false
	end
	local s = WS.state(u)
	local m = {}
	for k, v in pairs(e) do m[k] = v end
	m.source, m.clock = source, u.clock or 0
	if e.kind == "mul" or e.kind == "beat" then
		s.mods[#s.mods + 1] = m
	elseif e.kind == "stance" then
		require("src.reputation").setStance(u, e.a, e.b, e.to)
		s.mods[#s.mods + 1] = m
	elseif e.kind == "shock" then
		local News = require("src.news")
		for _, key in ipairs(stationsOf(e.where)) do
			News.shock(u, key, e.item, e.size, e.duration)
		end
	elseif e.kind == "flag" then
		WS.set(u, e.flag, e.value == nil and true or e.value, source)
	end
	WS.note(u, "effect", WS.describe(m), { source = source })
	return true
end

function WS.describe(e)
	if e.kind == "mul" then
		return ("%s x%.2f at %s%s"):format(e.target, e.by, e.where, e.sub and (" (" .. e.sub .. ")") or "")
	elseif e.kind == "beat" then return ("%s takes over %s's beat"):format(e.outlet, e.from)
	elseif e.kind == "stance" then return ("%s and %s now %s"):format(e.a, e.b, e.to)
	elseif e.kind == "shock" then return ("%s %+d%% at %s for %dh"):format(e.item, math.floor(e.size * 100 + .5), e.where, math.floor((e.duration or 0) / 3600 + .5))
	elseif e.kind == "flag" then return ("flag %s"):format(e.flag) end
	return tostring(e.kind)
end

-- Lines for the debug view and soak dumps: flags, lasting modifiers by
-- source, and the newest log lines.
function WS.report(u, logLines)
	local s = WS.state(u)
	local out = { "World state" }
	local names = {}
	for k in pairs(s.flags) do names[#names + 1] = k end
	table.sort(names)
	for _, k in ipairs(names) do out[#out + 1] = ("  %s = %s"):format(k, tostring(s.flags[k])) end
	if #s.mods > 0 then out[#out + 1] = "Lasting effects" end
	for _, m in ipairs(s.mods) do out[#out + 1] = ("  [%s] %s"):format(m.source or "?", WS.describe(m)) end
	local n = logLines or 8
	if #s.log > 0 then out[#out + 1] = "Log" end
	for i = math.max(1, #s.log - n + 1), #s.log do
		local e = s.log[i]
		out[#out + 1] = ("  %6.0fs %s"):format(e.clock or 0, e.text or e.kind)
	end
	return out
end

return WS
