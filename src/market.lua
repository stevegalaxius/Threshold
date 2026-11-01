--[[
	Station markets: credits, what each station has on its shelf, and
	settling a trade.

	  credits   game.universe.credits, one balance for the pilot (kept
	            through death, ship swaps and travel). A new game starts
	            with T.startCredits.
	  clock     game.universe.clock, seconds of game time. It runs wherever
	            you are, and a station catches up on whatever came due
	            while you were away when you dock (Game:marketTick).
	  shelf     each station's record (src/world.lua) gets market =
	            { hold, next }: a grid of what's for sale, and when the next
	            stack of each catalogue item comes in. Stock is restocked
	            one stack at a time up to its max (data/markets.lua).
	            Anything you sell sits on the shelf as resale (stack.resale
	            = when it's sold on) and can be bought back until then.
	  prices    buying costs the list price; selling pays T.sellRate of
	            it. A loaded container is priced with everything in it.
	  trading   the market tab (src/ui/cargo.lua) has one shared trade
	            grid. Its stacks carry owner = "player" or "station";
	            Game:completeTrade settles the lot.
	  ships     a station's shipyard (data/markets.lua ships = { hull ids })
	            sells new ships at the hull's list price, parked straight
	            into the hangar (Game:buyShip). Any parked ship can be sold
	            from the hangar for T.sellRate of what it's worth: its hull,
	            its fitted modules over or under the stock fit, and its
	            hold (Game:shipValue, Game:sellShip).

	Added to Game by src/game.lua: require("src.market")(Game).
]]

local data = require("src.data")
local Hold = require("src.inventory.hold")
local Grid = require("src.inventory.grid")
local Shapes = require("src.inventory.shapes")
local Ship = require("src.ship")
local T = require("src.tuning")
local events = require("src.events")

local floor, min = math.floor, math.min

return function(Game)

-- What a stack is worth at list price, with whatever a loaded container
-- carries.
function Game.stackValue(id, n, inner)
	local v = (data.items[id].price or 0) * n
	if inner then
		for _, g in ipairs(inner.grids) do
			for _, s in ipairs(g.stacks) do v = v + Game.stackValue(s.id, s.n, s.inner) end
		end
	end
	return v
end

function Game.buyPrice(s) return Game.stackValue(s.id, s.n, s.inner) end
function Game.sellPrice(s) return floor(Game.stackValue(s.id, s.n, s.inner) * T.sellRate) end

function Game:credits() return self.universe.credits end

-- Seconds for one more stack of a catalogue entry to come in.
local function restockTime(e)
	if e[3] then return e[3] end
	if data.items[e[1]].kind == "ammo" then return T.restockAmmo end
	local m = data.modules[e[1]]
	if m and m.size == "L" then return T.restockL end
	if m and m.size == "M" then return T.restockM end
	return T.restockS
end

-- How many of an item the shelf has as stock (not resale).
local function stockCount(hold, id)
	local n = 0
	for _, g in ipairs(hold.grids) do
		for _, s in ipairs(g.stacks) do
			if s.id == id and not s.resale then n = n + s.n end
		end
	end
	return n
end

function Game.newShelf()
	return Hold.new({ { key = "market", name = "For sale", w = T.marketW, h = T.marketH } })
end

-- A station's market, opened fully stocked the first time.
function Game:stationMarket(st)
	local r = self:stationRecord(st)
	if not r.market then
		r.market = { hold = Game.newShelf(), next = {} }
		local mk = data.markets[st.name]
		for _, e in ipairs(mk and mk.sells or {}) do
			local _, _, cap = Shapes.of(e[1])
			for _ = 1, e[2] do Hold.placeStack(r.market.hold, { id = e[1], n = cap }) end
		end
	end
	return r.market
end

-- Bring a station's shelf up to the clock: resale that's had its time is
-- sold on, and stock comes in a stack at a time. away: { id = n } of its
-- stock that's out on the trade grid, so that doesn't count as missing.
function Game:marketTick(st, away)
	local mk = self:stationMarket(st)
	local now = self.universe.clock
	for _, g in ipairs(mk.hold.grids) do
		for i = #g.stacks, 1, -1 do
			local s = g.stacks[i]
			if s.resale and s.resale <= now then Grid.remove(g, s) end
		end
	end
	local cat = data.markets[st.name]
	for _, e in ipairs(cat and cat.sells or {}) do
		local id = e[1]
		local _, _, cap = Shapes.of(id)
		local want, every = e[2] * cap, restockTime(e)
		local function have() return stockCount(mk.hold, id) + (away and away[id] or 0) end
		while have() < want and mk.next[id] and mk.next[id] <= now do
			if not Hold.placeStack(mk.hold, { id = id, n = min(cap, want - have()) }) then
				mk.next[id] = now + every               -- shelf full: try again later
				break
			end
			mk.next[id] = mk.next[id] + every
		end
		if have() >= want then mk.next[id] = nil
		elseif not mk.next[id] then mk.next[id] = now + every end
	end
end

-- Seconds until the next stack of an item comes in, or nil.
function Game:restockIn(st, id)
	local t = self:stationMarket(st).next[id]
	return t and math.max(0, t - self.universe.clock)
end

-- What the trade grid adds up to: what you get, what you pay.
function Game.tradeTotals(trade)
	local get, pay = 0, 0
	for _, g in ipairs(trade.grids) do
		for _, s in ipairs(g.stacks) do
			if s.owner == "station" then pay = pay + Game.buyPrice(s) else get = get + Game.sellPrice(s) end
		end
	end
	return get, pay
end

-- Put a bought stack in the hold if it fits, else in storage.
local function deliver(s, hold, storage)
	if s.inner then
		return Hold.placeStack(hold, { id = s.id, n = s.n, inner = s.inner })
			or Hold.placeStack(storage, { id = s.id, n = s.n, inner = s.inner })
	end
	local k = Hold.add(hold, s.id, s.n)
	if k < s.n then k = k + Hold.add(storage, s.id, s.n - k) end
	return k == s.n
end

-- The trade grid's goods: what you're buying (biggest first, the way
-- they'll be packed) and what you're selling.
local function split(trade)
	local buying, selling = {}, {}
	for _, g in ipairs(trade.grids) do
		for _, s in ipairs(g.stacks) do table.insert(s.owner == "station" and buying or selling, s) end
	end
	table.sort(buying, function(a, b) return a.w * a.h > b.w * b.h end)
	return buying, selling
end

-- Why the trade can't go through, or nil if it can: you can't cover the
-- difference, or what you're buying won't fit in your hold and storage.
function Game:tradeProblem(st, trade)
	local buying, selling = split(trade)
	if #buying + #selling == 0 then return "NOTHING ON THE TABLE" end
	local get, pay = Game.tradeTotals(trade)
	if self.universe.credits + get < pay then return "NOT ENOUGH CREDITS" end
	local th, ts = Hold.clone(self.player.hold), Hold.clone(self:stationStorage(st))
	for _, s in ipairs(buying) do
		if not deliver(s, th, ts) then return "NO ROOM" end
	end
	return nil
end

-- Settle the trade grid: you're paid for your goods and charged for the
-- station's, as one sum. Bought goods go to your hold, then storage; sold
-- goods go on the shelf as resale. Returns true and the net credits, or
-- false and why not (then nothing changes).
function Game:completeTrade(st, trade)
	local problem = self:tradeProblem(st, trade)
	if problem then return false, problem end
	local p, u = self.player, self.universe
	local get, pay = Game.tradeTotals(trade)
	local buying, selling = split(trade)
	local storage = self:stationStorage(st)
	for _, s in ipairs(buying) do deliver(s, p.hold, storage) end
	local mk = self:stationMarket(st)
	for _, s in ipairs(selling) do
		-- (no room on the shelf: it's sold on straight away)
		Hold.placeStack(mk.hold, { id = s.id, n = s.n, inner = s.inner, wear = s.wear, resale = u.clock + T.resaleTime })
	end
	for _, g in ipairs(trade.grids) do
		for i = #g.stacks, 1, -1 do Grid.remove(g, g.stacks[i]) end
	end
	u.credits = u.credits + get - pay
	p.cargo = Hold.totals(p.hold)
	Ship.updateMass(p)
	return true, get - pay
end

-- Ships ----------------------------------------------------------------------

-- What's in a ship's hold at list price: a Hold, or a plain { id = n }
-- cargo table (ships that never had a grid hold).
local function holdValue(rec)
	local v = 0
	if rec.hold then
		for _, g in ipairs(rec.hold.grids) do
			for _, s in ipairs(g.stacks) do v = v + Game.stackValue(s.id, s.n, s.inner) end
		end
	elseif rec.cargo then
		for id, n in pairs(rec.cargo) do
			if data.items[id] then v = v + (data.items[id].price or 0) * n end
		end
	end
	return v
end

local function fitValue(hull, loadout)
	local v = 0
	for i in ipairs(hull.slots) do
		local id = loadout and loadout[i]
		local m = id and data.modules[id]
		if m then v = v + (m.price or 0) end
	end
	return v
end

-- A ship record at list price: the hull's price (which buys it with its
-- stock fit), plus or minus what its fit is worth over the stock fit,
-- plus its hold.
function Game.shipValue(rec)
	local hull = data.hulls[rec.hull]
	local v = (hull.price or 0) + fitValue(hull, rec.loadout or hull.loadout) - fitValue(hull, hull.loadout)
	return math.max(0, v) + holdValue(rec)
end

function Game.shipSellPrice(rec) return floor(Game.shipValue(rec) * T.sellRate) end

-- The hull ids this station's shipyard sells (may be empty).
function Game.shipyard(st)
	local mk = data.markets[st.name]
	return mk and mk.ships or {}
end

-- Why this ship can't be bought here, or nil if it can.
function Game:shipBuyProblem(st, hullId)
	local hull = data.hulls[hullId]
	if not hull then return "UNKNOWN SHIP" end
	if self.universe.credits < (hull.price or 0) then return "NOT ENOUGH CREDITS" end
	if not self:hangarFit(st, hullId) then return "NO ROOM IN THE HANGAR" end
	return nil
end

-- Buy a new ship of a hull: paid for and parked in this station's hangar.
-- Returns the record, or nil and why not (then nothing changes).
function Game:buyShip(st, hullId)
	local problem = self:shipBuyProblem(st, hullId)
	if problem then return nil, problem end
	local rec = self:addToHangar(st, hullId)
	if not rec then return nil, "NO ROOM IN THE HANGAR" end
	self.universe.credits = self.universe.credits - (data.hulls[hullId].price or 0)
	events.emit("buyship", rec, st)
	return rec
end

-- Sell parked ship i (the one you're flying can't be sold). Its hold goes
-- with it. Returns the credits paid, or nil and why not.
function Game:sellShip(st, i)
	local list = self:hangar(st)
	local rec = list[i]
	if not rec then return nil, "NO SUCH SHIP" end
	local paid = Game.shipSellPrice(rec)
	table.remove(list, i)
	self.universe.credits = self.universe.credits + paid
	events.emit("sellship", rec, st)
	return paid
end

end
