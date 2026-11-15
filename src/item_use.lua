--[[
	Item use: any item in data/items.lua can be made usable with a `use`
	table, in the spirit of an MMO's "Use:" line. The item doesn't hold
	code. It lists building-block effects with their numbers, and those
	blocks are shared by every item:

	    use = {
	      label    = "Field repair",   -- shown on the cast bar and tooltip
	      cast     = 3,                -- seconds to use (0 or nil: instant)
	      cooldown = 10,               -- seconds before this group can be used again
	      group    = "repair",         -- items in one group share a cooldown (default: the item id)
	      consume  = 1,                -- how many items one use spends (0: reusable)
	      interruptible = true,        -- taking a hit cancels the cast (default true)
	      docked   = false,            -- usable while docked? (default false)
	      effects  = {
	        { "restore", "armor", 50, cap = 0.75 },          -- instant
	        { "restore", "armor", 200, over = 20 },          -- spread over 20 s
	        { "buff", "thrust", 1.5, dur = 8 },              -- x1.5 thrust for 8 s
	      },
	    }

	Effects are the building blocks. Each one is registered once and any
	number of items can use it:

	    ItemUse.effect("restore", {
	      check = function(game, e, a) return ok, reason end,  -- optional: can it do anything?
	      apply = function(game, e, a) ... end,                -- runs when the cast completes;
	    })                                                     -- may return an aura (below)

	An aura is a timed thing left on the ship: { dur, tick(dt), expire() }.
	Effects that work over time (heal-over-time, buffs) return one.

	Resources are what restore can fill. ItemUse.resource("armor", {get,
	max, set}) adds one, so new ship systems (shields, coolant) plug in the
	same way.

	The same functions run for the player and for NPC ships. Cast, cooldown
	and auras live on the entity (e.casting, e.cooldowns, e.auras) and are
	not saved: a cast or buff in progress is simply dropped on reload.

	Events: use_begin(e, id), use_finish(e, id), use_cancel(e, id, why).
]]
local data = require("src.data")
local events = require("src.events")
local max, min = math.max, math.min

local U = { effects = {}, resources = {} }

---------------------------------------------------------------------------
-- Registries

function U.effect(name, def)
	assert(type(def) == "table" and type(def.apply) == "function", "effect '" .. tostring(name) .. "' needs an apply function")
	U.effects[name] = def
	return def
end

function U.resource(name, def)
	assert(def.get and def.max and def.set, "resource '" .. tostring(name) .. "' needs get, max and set")
	U.resources[name] = def
	return def
end

-- Turn an effect line into named fields: { "restore", "armor", 50, cap = .75 }
-- reads as { kind = "restore", [1] = "armor", [2] = 50, cap = .75 }.
local function args(line)
	local a = { kind = line[1] }
	for k, v in pairs(line) do
		if type(k) == "number" then
			if k > 1 then a[k - 1] = v end
		else a[k] = v end
	end
	return a
end

---------------------------------------------------------------------------
-- Holds: take from whichever inventory the ship has.

local function count(e, id)
	if e.hold then return require("src.inventory.hold").count(e.hold, id) end
	return e.cargo and e.cargo[id] or 0
end

local function spend(e, id, n)
	if n <= 0 then return true end
	if count(e, id) < n then return false end
	if e.hold then
		local Hold = require("src.inventory.hold")
		Hold.take(e.hold, id, n)
		e.cargo = Hold.totals(e.hold)
	else
		e.cargo[id] = e.cargo[id] - n
		if e.cargo[id] <= 0 then e.cargo[id] = nil end
	end
	e.massDirty = true
	return true
end

---------------------------------------------------------------------------
-- Queries

function U.def(id)
	local item = data.items[id]
	return item and item.use
end

function U.usable(id) return U.def(id) ~= nil end

function U.label(id)
	local cfg, item = U.def(id), data.items[id]
	return cfg and (cfg.label or ("Use " .. item.name)) or nil
end

local function group(id, cfg) return cfg.group or id end

-- Seconds left on this item's cooldown (0 when ready).
function U.cooldown(game, e, id)
	local cfg = U.def(id)
	local ready = cfg and e.cooldowns and e.cooldowns[group(id, cfg)]
	return ready and max(0, ready - game.time) or 0
end

-- Can e start using id right now? Returns true, or false and a reason.
function U.can(game, e, id)
	local cfg = U.def(id)
	if not cfg then return false, "Can't be used" end
	if not e or e.dead then return false, "No ship" end
	if (e.dockState or (e == game.player and game.state == "docked")) and not cfg.docked then
		return false, "Can't use while docked"
	end
	if e.casting then return false, "Already using " .. (data.items[e.casting.id].name) end
	if count(e, id) < (cfg.consume or 1) then return false, "None in the hold" end
	local cd = U.cooldown(game, e, id)
	if cd > 0 then return false, ("Ready in %ds"):format(math.ceil(cd)) end
	-- every effect that can say no gets a say; one that would do something is enough
	local reason, useful = nil, false
	for _, line in ipairs(cfg.effects or {}) do
		local a = args(line)
		local fx = U.effects[a.kind]
		if not fx then return false, "Unknown effect " .. tostring(a.kind) end
		local ok, why = true, nil
		if fx.check then ok, why = fx.check(game, e, a, cfg) end
		if ok then useful = true else reason = reason or why end
	end
	if not useful then return false, reason or "Nothing to do" end
	return true
end

---------------------------------------------------------------------------
-- Using

local function complete(game, e, id, cfg)
	if not spend(e, id, cfg.consume or 1) then return false end
	for _, line in ipairs(cfg.effects or {}) do
		local a = args(line)
		local fx = U.effects[a.kind]
		local ok = not fx.check or fx.check(game, e, a, cfg)
		if ok then
			local aura = fx.apply(game, e, a, cfg)
			if aura then
				aura.t, aura.source = 0, id
				e.auras = e.auras or {}
				-- one aura per key (e.g. one thrust buff): a new one refreshes it
				if aura.key then
					for i = #e.auras, 1, -1 do
						local old = e.auras[i]
						if old.key == aura.key then
							if old.expire then old.expire() end
							table.remove(e.auras, i)
						end
					end
				end
				table.insert(e.auras, aura)
			end
		end
	end
	if (cfg.cooldown or 0) > 0 then
		e.cooldowns = e.cooldowns or {}
		e.cooldowns[group(id, cfg)] = game.time + cfg.cooldown
	end
	events.emit("use_finish", e, id)
	return true
end

-- Start using an item. Returns true, or false and a reason.
function U.begin(game, e, id)
	U.game = game
	local ok, why = U.can(game, e, id)
	if not ok then return false, why end
	local cfg = U.def(id)
	events.emit("use_begin", e, id)
	if (cfg.cast or 0) <= 0 then return complete(game, e, id, cfg) end
	e.casting = { id = id, t = 0, time = cfg.cast, label = U.label(id) }
	return true
end

function U.cancel(game, e, why)
	local c = e and e.casting
	if not c then return end
	e.casting = nil
	events.emit("use_cancel", e, c.id, why)
	if game and e == game.player and game.toast then game:toast(c.label .. " interrupted", 1.5) end
end

-- First usable item in e's hold from a group (e.g. "repair"): the quick-use key.
function U.firstOf(game, e, groupName)
	local reason
	for id, n in pairs(e.cargo or {}) do
		local cfg = U.def(id)
		if n > 0 and cfg and group(id, cfg) == groupName then
			local ok, why = U.can(game, e, id)
			if ok then return id end
			reason = reason or why
		end
	end
	return nil, reason or "Nothing in the hold for that"
end

function U.quick(game, e, groupName)
	local id, why = U.firstOf(game, e, groupName)
	if not id then return false, why end
	return U.begin(game, e, id)
end

-- Every frame, for every live ship.
function U.update(game, e, dt)
	U.game = game
	local c = e.casting
	if c then
		c.t = c.t + dt
		if c.t >= c.time then
			e.casting = nil
			local cfg = U.def(c.id)
			-- the hold may have changed during the cast
			if not complete(game, e, c.id, cfg) then events.emit("use_cancel", e, c.id, "gone") end
		end
	end
	local auras = e.auras
	if auras then
		for i = #auras, 1, -1 do
			local a = auras[i]
			local step = min(dt, a.dur - a.t)
			if a.tick and step > 0 then a.tick(step) end
			a.t = a.t + dt
			if a.t >= a.dur then
				if a.expire then a.expire() end
				table.remove(auras, i)
			end
		end
		if #auras == 0 then e.auras = nil end
	end
end

-- Interruptions: a hit (if the item allows), docking, death.
events.on("hit", function(e)
	local c = e.casting
	if not c then return end
	local cfg = U.def(c.id)
	if cfg.interruptible ~= false then U.cancel(U.game, e, "hit") end
end)
events.on("dock", function(e) U.cancel(U.game, e, "docked") end)

---------------------------------------------------------------------------
-- Resources restore can fill

U.resource("armor", {
	get = function(e) return e.armor or 0 end,
	max = function(e) return e.stats and e.stats.armor or 0 end,
	set = function(e, v)
		e.armor = v
		-- keep an A-Life ship's record in step
		local u = U.game and U.game.universe
		local r = e.alifeId and u and u.npcs and u.npcs[e.alifeId]
		if r and r.ship then r.ship.armor = v end
	end,
})
U.resource("power", {
	get = function(e) return e.power or 0 end,
	max = function(e) return e.stats and e.stats.powerCap or 0 end,
	set = function(e, v) e.power = v end,
})

---------------------------------------------------------------------------
-- Built-in effects

-- { "restore", resource, amount, cap = fraction of max (default 1), over = seconds }
local function ceiling(e, res, a) return res.max(e) * (a.cap or 1) end
U.effect("restore", {
	check = function(game, e, a)
		local res = U.resources[a[1]]
		if not res then return false, "Unknown resource " .. tostring(a[1]) end
		if res.get(e) >= ceiling(e, res, a) - 1e-6 then
			if (a.cap or 1) < 1 then return false, ("Already at %d%% %s (field limit)"):format(math.floor((a.cap) * 100 + .5), a[1]) end
			return false, a[1]:sub(1, 1):upper() .. a[1]:sub(2) .. " already full"
		end
		return true
	end,
	apply = function(game, e, a)
		local res = U.resources[a[1]]
		local function add(n)
			local top = ceiling(e, res, a)
			local v = res.get(e)
			if v < top then res.set(e, min(top, v + n)) end
		end
		if (a.over or 0) <= 0 then add(a[2]); return end
		local rate = a[2] / a.over
		return { dur = a.over, key = a.key, tick = function(dt) if not e.dead then add(rate * dt) end end }
	end,
})

-- { "buff", stat, multiplier, dur = seconds }: scales one of the ship's
-- stats (thrust, sideThrust, turn, ...) for a while. A second buff of the
-- same stat refreshes the first instead of stacking.
U.effect("buff", {
	check = function(game, e, a)
		if not (e.stats and type(e.stats[a[1]]) == "number") then return false, "No " .. tostring(a[1]) .. " to boost" end
		return true
	end,
	apply = function(game, e, a)
		local stats, stat, mult = e.stats, a[1], a[2]
		-- refresh: undo the running buff of this stat before scaling again
		for i = #(e.auras or {}), 1, -1 do
			local old = e.auras[i]
			if old.key == "buff:" .. stat then old.expire(); table.remove(e.auras, i) end
		end
		local base = stats[stat]
		stats[stat] = base * mult
		return { dur = a.dur or 10, key = "buff:" .. stat, expire = function()
			-- only undo it if the ship still has the same stats table (a refit replaces it)
			if e.stats == stats then stats[stat] = base end
		end }
	end,
})

return U
