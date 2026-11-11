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
local stats = require("src.stats")
local Hold = require("src.inventory.hold")
local Grid = require("src.inventory.grid")
local Shapes = require("src.inventory.shapes")
local Ship = require("src.ship")
local T = require("src.tuning")
local events = require("src.events")
local Locations = require("src.locations")
local Stock = require("src.stockpile")

local ShipEntry=require("src.inventory.ship_entry")
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

-- Game.priceFactor: the docked station's reputation discount or markup (src/reputation.lua), set by stationMarket.
Game.priceFactor=1
local function tradeValue(s)
 local C=require('src.markets')
 if C.items[s.id] and not s.inner and Game.marketUniverse and Game.marketStation then
  return C.price(Game.marketUniverse,Game.marketStation,s.id)*s.n
 end
 return Game.stackValue(s.id,s.n,s.inner)
end
function Game.buyPrice(s) local item=ShipEntry.item(s.id);return floor((item and item.price or tradeValue(s))*Game.priceFactor) end
function Game.sellPrice(s) if ShipEntry.item(s.id) then return s.shipRecord and Game.shipSellPrice(s.shipRecord) or 0 end;return floor(tradeValue(s)*T.sellRate) end

function Game:credits() return self.universe.credits end
function Game:setMarketPrices(st)
 Game.marketUniverse,Game.marketStation=self.universe,Stock.key(st)
 Game.priceFactor=require('src.reputation').priceFactor(self.universe,st.key or st.locationId)
end

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

-- The services a station offers, from its definition's services list
-- (src/editor: station panel). Stations saved before services existed
-- offer the original three. Storage (your hold, fitting and station
-- storage) is always there. Returns a set: { market = true, ... }.
Game.SERVICES = { "market", "shipyard", "hangar", "repair" }
function Game.stationServices(st)
 local L=require('src.locations');local id=st and (st.locationId or st.key)
 return require('src.station_services').get(st and st.def,id and L.byId[L.canonical(id)])
end

-- Repairs: credits per armor point here, and what fixing a ship costs.
function Game.repairRate(st)
	return st and st.def and st.def.repairRate or T.repairRate
end

-- owner is the player's ship or a stored ship record. Returns missing
-- armor points and the full price.
function Game:repairQuote(st, owner)
	local hull = owner == self.player and owner.hull or data.hulls[owner.hull]
	local max = owner == self.player and owner.stats.armor
		or stats.compute(hull, owner.loadout or hull.loadout).armor
	local missing = math.max(0, math.ceil(max - (owner.armor or max)))
	return missing, missing * Game.repairRate(st), max
end

-- Queue work at the station's rate; payment happens as work completes.
-- Returns requested points and their maximum quote, or nil and why not.
function Game:repairShip(st, owner)
	if not Game.stationServices(st).repair then return nil, "NO REPAIR BAY HERE" end
	local missing = self:repairQuote(st, owner)
	if missing <= 0 then return nil, "NOTHING TO REPAIR" end
	if owner.repairOrder then return nil, "REPAIRS ALREADY IN PROGRESS" end
	local rate = Game.repairRate(st)
	local points = rate > 0 and math.min(missing, floor(self.universe.credits / rate)) or missing
	if points <= 0 then return nil, "NOT ENOUGH CREDITS" end
	owner.repairOrder={key=Stock.key(st),remaining=points,rate=rate,at=self.universe.clock}
	return points, points*rate
end

-- Repair orders are paid as work completes. Stored ships catch up when the
-- station is visited; undocking cancels the flying ship's unpaid remainder.
function Game:updateRepairs(st)
 local key=Stock.key(st)
 local function work(owner)
  local order=owner.repairOrder
  if not order or order.key~=key then return end
  local elapsed=math.max(0,self.universe.clock-order.at);order.at=self.universe.clock
  local missing,_,maximum=self:repairQuote(st,owner)
  local budget=order.rate>0 and self.universe.credits/order.rate or order.remaining
  local points=require('src.repair_materials').restore(self.universe,key,math.min(missing,order.remaining,budget),elapsed,T.npcRepairPerSecond)
  owner.armor=math.min(maximum,(owner.armor or maximum)+points)
  self.universe.credits=math.max(0,self.universe.credits-points*order.rate)
  order.remaining=math.max(0,order.remaining-points)
  if order.remaining<1e-6 or maximum-owner.armor<1e-6 or budget<=points+1e-6 then owner.repairOrder=nil end
 end
 work(self.player)
 for _,owner in ipairs(self:stationRecord(st).hangar) do work(owner) end
end

function Game.marketDefinition(st) return Stock.definition(st) end

function Game.newShelf()
	return Hold.new({ { key = "market", name = "For sale", w = T.marketW, h = T.marketH } })
end

-- A station's market, opened fully stocked the first time.
-- A station's shops: { name, description, sells } each, from the market
-- definition's shops list. A market with a plain sells list is one shop.
function Game.marketShops(st) return Stock.shops(st) end

local function newMarket(sells)
	local m = { hold = Game.newShelf(), next = {} }
	for _, e in ipairs(sells or {}) do
		local _, _, cap = Shapes.of(e[1])
		for _ = 1, e[2] do Hold.placeStack(m.hold, { id = e[1], n = cap }) end
	end
	return m
end

-- Which shop is open (its index), and switching to another.
function Game:currentShop(st)
	local r = self:stationRecord(st)
	local n = #Game.marketShops(st)
	if not r.shop or r.shop > n then r.shop = 1 end
	return r.shop
end
function Game:setShop(st, i)
	if i >= 1 and i <= #Game.marketShops(st) then self:stationRecord(st).shop = i end
end

-- Shop i's shelf (default: the open one). Each shop keeps its own
-- stockpile (src/stockpile.lua) and restock timers; the shelf grid shows
-- that stockpile, and what you sell goes to the shop you sold it to.
function Game:stationMarket(st, i)
	local r = self:stationRecord(st)
	self:setMarketPrices(st)
	i = i or self:currentShop(st)
	r.shops = r.shops or {}
	local m = r.shops[i]
	if not m then
		m = newMarket(Game.marketShops(st)[i].sells)
		r.shops[i] = m
	elseif not m.hold then
		m.hold = Game.newShelf(); m.next = m.next or {}
	end
	local stock = Stock.stock(self.universe, st, i)
	if stock then Stock.syncShelf(m.hold, Stock.shelf(self.universe,st,i)) end
	return m
end

-- Bring a station's shelf up to the clock: resale that's had its time is
-- sold on, and stock comes in a stack at a time. away: { id = n } of its
-- stock that's out on the trade grid, so that doesn't count as missing.
function Game:marketTick(st, away)
	for i, shop in ipairs(Game.marketShops(st)) do self:shopTick(st, i, shop, i == self:currentShop(st) and away or nil) end
end

function Game:shopTick(st, i, shop, away)
	local mk = self:stationMarket(st, i)
	local now = self.universe.clock
	for _, g in ipairs(mk.hold.grids) do
		for i = #g.stacks, 1, -1 do
			local s = g.stacks[i]
			if s.resale and s.resale <= now then Grid.remove(g, s) end
		end
	end
	for _, e in ipairs(shop.sells or {}) do
		local id = e[1]
		local _, _, cap = Shapes.of(id)
		local want, every = e[2] * cap, restockTime(e)
  if shop.unlimited then mk.next[id]=now end
		local stock = not shop.unlimited and Stock.stock(self.universe, st, i)
		local function have() return stock and (stock[id] or 0) or stockCount(mk.hold, id) + (away and away[id] or 0) end
		-- Food, fertilizer and steel come from production or recovery.
		if id=='food_crate' or id=='steel_plate' or require('src.markets').items[id] then mk.next[id]=nil else
		-- the timed restock stands in for production until stations make goods
		while have() < want and mk.next[id] and mk.next[id] <= now do
			if stock then
				stock[id] = (stock[id] or 0) + min(cap, want - have())
			elseif not Hold.placeStack(mk.hold, { id = id, n = min(cap, want - have()) }) then
				mk.next[id] = now + every               -- shelf full: try again later
				break
			end
			mk.next[id] = shop.unlimited and now or mk.next[id] + every
		end
		if have() >= want then mk.next[id] = nil
		elseif not mk.next[id] then mk.next[id] = now + every end
		end
	end
	local stock = not shop.unlimited and Stock.stock(self.universe, st, i)
	if stock then Stock.syncShelf(mk.hold, Stock.shelf(self.universe,st,i), away) end
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

-- Plan parking on an isolated roster so sold ships can free space for purchases.
local function shipPlan(game,st,buying,selling)
 local original=game:stationRecord(st);local roster,sold,planned={},{},{}
 for _,s in ipairs(selling) do if ShipEntry.item(s.id) then
  local found=false
  for _,rec in ipairs(original.hangar) do if rec==s.shipRecord then found=true end end
  if not found or sold[s.shipRecord] then return nil,'SHIP NO LONGER AVAILABLE' end
  sold[s.shipRecord]=true
 end end
 for _,rec in ipairs(original.hangar) do if not sold[rec] then
  local c={};for k,v in pairs(rec) do c[k]=v end;roster[#roster+1]=c
 end end
 local record={hangar=roster,moorings=original.moorings}
 local proxy=setmetatable({stationRecord=function() return record end},{__index=game})
 for _,s in ipairs(buying) do local item=ShipEntry.item(s.id);if item then
  local available=false;for _,lot in ipairs(require('src.dealers').lots(game.universe,st)) do if lot.hull==item.hull then available=true end end
  if not available then return nil,'SHIP NO LONGER FOR SALE' end
  local parking=proxy:shipParkingFit(st,item.hull)
  if not parking then return nil,'NO SUITABLE FREE PARKING' end
  local rec={hull=item.hull};proxy:applyParking(rec,parking);roster[#roster+1]=rec
  planned[#planned+1]={hull=item.hull,parking=parking}
 end end
 return {sold=sold,bought=planned}
end

-- Why the trade can't go through, or nil if it can: you can't cover the
-- difference, or what you're buying won't fit in your hold and storage.
function Game:tradeProblem(st, trade)
	self:setMarketPrices(st)
	local buying, selling = split(trade)
	if #buying + #selling == 0 then return "NOTHING ON THE TABLE" end
	local get, pay = Game.tradeTotals(trade)
	if self.universe.credits + get < pay then return "NOT ENOUGH CREDITS" end
	local th, ts = Hold.clone(self.player.hold), Hold.clone(self:stationStorage(st))
	for _, s in ipairs(buying) do
		if not ShipEntry.item(s.id) and not deliver(s, th, ts) then return "NO ROOM" end
	end
 local wanted={};local shop=Game.marketShops(st)[self:currentShop(st)]
 for _,s in ipairs(buying) do
  if not shop.unlimited and not s.resale and not s.inner and not ShipEntry.item(s.id) then
   wanted[s.id]=(wanted[s.id] or 0)+s.n
   if wanted[s.id]>Stock.available(self.universe,st,s.id,self:currentShop(st)) then return 'STOCK RESERVED OR NO LONGER AVAILABLE' end
  end
 end
 local plan,why=shipPlan(self,st,buying,selling)
 if not plan then return why end
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
	local plan=assert(shipPlan(self,st,buying,selling))
 local records={}
 for _,purchase in ipairs(plan.bought) do
  local e=Ship.new(self,{hull=purchase.hull,team=1,grid=true})
  local rec=Ship.record(e);e.body:destroy();self:applyParking(rec,purchase.parking);records[#records+1]=rec
 end
 local roster=self:stationRecord(st).hangar
 for i=#roster,1,-1 do if plan.sold[roster[i]] then table.remove(roster,i) end end
 for _,rec in ipairs(records) do roster[#roster+1]=rec end
 local shopIndex = self:currentShop(st)
	local shop = Game.marketShops(st)[shopIndex]
	local stock = not shop.unlimited and Stock.stock(u, st, shopIndex)
 for _,s in ipairs(buying) do if not ShipEntry.item(s.id) then
  deliver(s,p.hold,storage)
  if stock and not s.resale and not s.inner then assert(Stock.take(u,st,s.id,s.n,shopIndex)) end
  if stock and not s.resale and require('src.ammunition').byItem[s.id] then require('src.economy').consume(u,st.key,s.id,s.n) end
 end end
	local mk = self:stationMarket(st)
	for _, s in ipairs(selling) do
		-- resale: it can be bought back until it's sold on
		-- (no room on the shelf: it's sold on straight away)
		if (s.id=='steel_plate' or require('src.markets').items[s.id]) and not s.inner then Stock.add(u,st,s.id,s.n)
		elseif not ShipEntry.item(s.id) then Hold.placeStack(mk.hold, { id = s.id, n = s.n, inner = s.inner, wear = s.wear, resale = u.clock + T.resaleTime }) end
	end
	for _, g in ipairs(trade.grids) do
		for i = #g.stacks, 1, -1 do Grid.remove(g, g.stacks[i]) end
	end
	u.credits = u.credits + get - pay
	p.cargo = Hold.totals(p.hold)
	Ship.updateMass(p)
 for rec in pairs(plan.sold) do events.emit("sellship",rec,st) end
 for _,rec in ipairs(records) do events.emit("buyship",rec,st) end
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

-- The ships on this station's dealer lot (src/dealers.lua; may be empty).
function Game:shipyard(st)
	return require("src.dealers").lots(self.universe, st)
end

-- Why this lot ship can't be bought here, or nil if it can. tradeIn (a
-- stored ship record) counts toward the price and frees its parking.
function Game:shipBuyProblem(st, lot, tradeIn)
	if not lot or not require("src.dealers").find(self.universe, st, lot.id) then return "NO LONGER FOR SALE" end
	local credit = tradeIn and Game.shipSellPrice(tradeIn) or 0
	if self.universe.credits + credit < lot.price then return "NOT ENOUGH CREDITS" end
	if not self:shipParkingFit(st, lot.hull, tradeIn) then return "NO SUITABLE FREE PARKING" end
	return nil
end

-- Buy a ship off the dealer lot: paid for and parked at this station, in
-- its own paint and fit. opts.tradeIn is a stored ship here, sold (with
-- its hold) toward the price. Returns the record, or nil and why not.
function Game:buyShip(st, lot, opts)
	opts = opts or {}
	local tradeIn = opts.tradeIn
	local problem = self:shipBuyProblem(st, lot, tradeIn)
	if problem then return nil, problem end
	local list = self:hangar(st)
	local tradeIndex
	if tradeIn then
		for i, rec in ipairs(list) do if rec == tradeIn then tradeIndex = i end end
		if not tradeIndex then return nil, "NO SUCH SHIP" end
		table.remove(list, tradeIndex)
	end
	local rec = self:addToHangar(st, lot.hull, lot.paint, lot.loadout)
	if not rec then
		if tradeIndex then table.insert(list, tradeIndex, tradeIn) end
		return nil, "NO SUITABLE FREE PARKING"
	end
	require("src.dealers").take(self.universe, st, lot.id)
	local credit = tradeIn and Game.shipSellPrice(tradeIn) or 0
	self.universe.credits = self.universe.credits + credit - lot.price
	if tradeIn then events.emit("sellship", tradeIn, st) end
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
