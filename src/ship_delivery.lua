--[[
	Ship deliveries: new ships moving from a shipyard's lot to a dealer
	that sells them but doesn't build them, carried on a ship hauler's
	berths (src/berths.lua).

	Everything here reads the data, so new hull designs need no edits:
	  * a hauler is any NPC whose hull has berths (capability "berths");
	    a hauler bought for delivery (workProfile ship_hauler) buys whichever
	    such hull it can afford
	  * a delivery fits a hauler when some free berth of its hull takes the
	    ship's hull (Berths.fits: length and width)
	  * a dealer wants a delivery for each hull on its list it has no lot
	    of, sourced from any shipyard with that hull on its lot

	Deliveries are the only way a dealer that doesn't build ships restocks
	(past its opening stock): nothing is conjured if no hauler comes.
]]
local Tasks = require("src.tasks")
local L = require("src.locations")
local G = require("src.travelgraph")
local T = require("src.tuning")
local data = require("src.data")
local Berths = require("src.berths")
local copy = require("src.persistence").copy

local SD = {}
local HOUR = 3600
local PICKUP_WINDOW=2*HOUR
T.shipDeliveryPatience = T.shipDeliveryPatience or 6     -- game hours before a dealer restocks anyway
T.shipDeliveryRate = T.shipDeliveryRate or 0.03          -- share of the ship's price paid per delivery
T.shipDeliveryPerAU = T.shipDeliveryPerAU or 1500        -- plus credits per AU of route

local function Transport() return require("src.transport") end
local function Dealers() return require("src.dealers") end

-- A stand-in carrier for berth checks on an NPC record.
local function carrierOf(r)
	return { hull = data.hulls[r.ship.hull], carried = r.ship.carried or {} }
end

local function offers(u, fn)
	local deliveries,board=Tasks.offersOfKind(u,"ship_delivery")
 for id,o in pairs(deliveries) do if board[id]==o then fn(o) end end
end

-- The dealer stations that build ships, and the ones that only sell.
local function stations()
	local D, factories, shops = Dealers(), {}, {}
	for key, place in pairs(L.byId) do
		if place.kind == "station" and not place.accessOf then
			local def = D.def(key)
			if def and not def.usedOnly then
				if D.buildsShips(key) then factories[#factories + 1] = key else shops[#shops + 1] = key end
			end
		end
	end
	table.sort(factories); table.sort(shops)
	return factories, shops
end
SD.stations = stations

-- Is a delivery for this target and hull already on the board?
function SD.pending(u, target, hull)
	local found
	offers(u, function(o) if not o.playerDelivery and o.target == target and (not hull or o.hull == hull) then found = o end end)
	return found
end

-- Should dealer `key` still wait for a hauler rather than restock hull?
function SD.waiting(u, key, hull, clock)
	local o = SD.pending(u, key, hull)
	return o and (o.state == "reserved" or clock < (o.placed or clock) + T.shipDeliveryPatience * HOUR) or false
end

-- Post a delivery for every hull a shop lacks that a shipyard has on its lot.
function SD.refresh(u, clock)
	local D = Dealers()
	local factories, shops = stations()
	-- lots already promised to a delivery
	local promised = {}
	offers(u, function(o) promised[o.source .. "/" .. tostring(o.lot)] = true end)
	for _, target in ipairs(shops) do
		local s, def = D.state(u, target)
		if s and #s.lots < (def.lots or 6) then
			local have = {}
			for _, lot in ipairs(s.lots) do have[lot.hull] = true end
			for _, hull in ipairs(def.hulls or {}) do
				if not have[hull] and not SD.pending(u, target, hull) and data.hulls[hull] then
					for _, source in ipairs(factories) do
						local lot
						for _, l in ipairs(D.lots(u, source)) do
							if l.hull == hull and not l.playerOrder and not l.playerDelivery and not l.used and not promised[source .. "/" .. tostring(l.id)] then lot = l break end
						end
						if lot and G.itinerary(source,target,clock,true) then
							promised[source .. "/" .. tostring(lot.id)] = true
							Tasks.post(u, { kind = "ship_delivery", source = source, target = target, hull = hull, lot = lot.id,
								price = lot.price, placed = clock, cooldown = 120, requires = { capabilities = { "berths" } } })
							break
						end
					end
				end
			end
		end
	end
	-- drop offers whose ship has gone (sold off the lot) before pickup
	local state = Tasks.state(u)
	for id, o in pairs(state.offers) do
		if o.kind == "ship_delivery" and o.state == "available" and not D.find(u, o.source, o.lot) then state.offers[id] = nil end
	end
 SD.updatePlayerOrders(u,clock)
end

local function payment(o, clock)
	Transport().quote(o, clock)
	return math.floor((o.price or 50000) * T.shipDeliveryRate + (o.routeAU or 0) * T.shipDeliveryPerAU)
end

local function playerOrders(u)
 local board=Tasks.state(u)
 board.shipPurchases=board.shipPurchases or {}
 local orders=board.shipPurchases
 local legacy={}
 for key,order in pairs(orders) do
  if key~=order.id then legacy[#legacy+1]={key=key,order=order} end
 end
 for _,entry in ipairs(legacy) do
  local order=entry.order
  local offer=board.offers[order.id]
  order.target=entry.key
  order.pickupBy=(offer and offer.placed or u.clock)+PICKUP_WINDOW
  orders[entry.key],orders[order.id]=nil,order
 end
 return orders
end

function SD.playerOrders(u,target)
 local list={}
 for _,order in pairs(playerOrders(u)) do
  if order.target==target then list[#list+1]=order end
 end
 table.sort(list,function(a,b)
  return tonumber(a.id:match('%d+$'))>tonumber(b.id:match('%d+$'))
 end)
 return list
end

local function active(order)
 return order.status=='listed' or order.status=='in transit'
end

-- The board holds the parking claim, so cancellation and settlement cannot
-- leave a second saved reservation behind.
local function destinationParking(u,offer)
 local Parking=require('src.dealer_parking')
 if not offer.playerDelivery and not offer.parking then
  local stock,def=Dealers().state(u,offer.target)
  if not stock then return end
  local used=#stock.lots
  for _,claim in ipairs(Parking.claims(u,offer.target)) do
   if claim.dealerStock then used=used+1 end
  end
  if used>=(def.lots or 6) then return end
 end
 local prefer=not offer.playerDelivery and 'outside' or nil
 local spot=Parking.plan(u,offer.target,offer.hull,1,prefer,offer.playerDelivery,offer.parking)[1]
 if spot then
  spot.hull=offer.hull
  spot.dealerStock=not offer.playerDelivery
 end
 return spot
end

local function reserveParking(u,task)
 local offer=Tasks.state(u).offers[task.id]
 if not offer then return end
 local spot=destinationParking(u,offer)
 if spot then offer.parking=spot end
 return spot
end

local function deliveryCarrier(u,offer)
 local busy={}
 local board=Tasks.state(u)
 for _,order in pairs(playerOrders(u)) do
  local task=board.offers[order.id]
  if active(order) and task then
   local id=task.owner or order.carrier
   if id then busy[id]=true end
  end
 end
 local W=require('src.work_preferences')
 local Access=require('src.npc_access')
 local best
 for id,r in pairs(u.npcs or {}) do
  local node=r.node or r.route and r.route[r.index]
  if not busy[id] and r.ship and r.state~='dead' and r.state~='escaped'
   and not r.service and not r.suspendedTask and not r.worldRecovery
   and r.fuelStatus~='stranded' and r.fuelStatus~='empty'
   and L.byId[node] and W.weight(r,'ship_delivery')>0
   and Berths.free(carrierOf(r),offer.hull) and Access.eligible(r,offer,Access.capabilities(r),u)
   and (node==offer.source or G.itinerary(node,offer.source,u.clock)) then
   if not best or id<best then best=id end
  end
 end
 return best
end

function SD.hasCarrier(u,quote)
 local offer=copy(quote)
 offer.requires={capabilities={'berths'}}
 return deliveryCarrier(u,offer)~=nil
end

local function carrierExists(hullId)
 for _,hull in pairs(data.hulls) do
  for _,berth in ipairs(hull.berths or {}) do
   if Berths.fitsSize(berth,hullId) then return true end
  end
 end
 return false
end
function SD.catalogue(u,target,clock)
 local D=Dealers()
 local sources={}
 for key,place in pairs(L.byId) do
  if key~=target and place.kind=='station' and not place.accessOf and D.def(key) then sources[#sources+1]=key end
 end
 table.sort(sources)
 local cheapest,compatible,promised={},{},{}
 offers(u,function(o) promised[o.source.."/"..o.lot]=true end)
 for _,source in ipairs(sources) do
  local lots=D.lots(u,source)
  local route
  for _,lot in ipairs(lots) do
   if compatible[lot.hull]==nil then compatible[lot.hull]=carrierExists(lot.hull) end
   if compatible[lot.hull] and not lot.playerOrder and not lot.playerDelivery and not promised[source..'/'..lot.id] then
    if route==nil then route=G.itinerary(source,target,clock,true) or false end
    if route then
     local offer={kind='ship_delivery',source=source,target=target,hull=lot.hull,lot=lot.id,price=lot.price,placed=clock}
     offer.fee=payment(offer,clock)
     local old=cheapest[lot.hull]
     if not old or offer.price+offer.fee<old.price+old.fee then cheapest[lot.hull]=offer end
    end
   end
  end
 end
 local choices={}
 for _,o in pairs(cheapest) do choices[#choices+1]=o end
 table.sort(choices,function(a,b) return data.hulls[a.hull].name<data.hulls[b.hull].name end)
 return choices
end

function SD.orderPlayer(u,quote)
 local target=quote.target
 if not L.byId[target] or L.byId[target].kind~='station' then return nil,'No delivery station' end
 local orders=playerOrders(u)
 local D=Dealers()
 local def=D.def(quote.source)
 local lot=def and not def.service and D.find(u,quote.source,quote.lot)
 if not lot or lot.hull~=quote.hull or lot.playerOrder or lot.playerDelivery or lot.price~=quote.price then return nil,'That ship is no longer for sale' end
 local promised=false
 offers(u,function(o) if o.source==quote.source and o.lot==quote.lot then promised=true end end)
 if promised then return nil,'That ship is already promised to a delivery' end
 if not carrierExists(lot.hull) then return nil,'No carrier design can transport this hull' end
 if not G.itinerary(quote.source,target,u.clock,true) then return nil,'No delivery route' end
 local offer={kind='ship_delivery',source=quote.source,target=target,hull=lot.hull,lot=lot.id,price=lot.price,placed=u.clock}
 local price,fee=lot.price,payment(offer,u.clock)
 if u.credits<price+fee then return nil,'Not enough credits' end
 offer.requires={capabilities={'berths'}}
 offer.playerDelivery=true
 offer.parking=destinationParking(u,offer)
 if not offer.parking then return nil,'No suitable parking at this station' end
 offer.order=true
 local carrier=deliveryCarrier(u,offer)
 if not carrier then return nil,'No compatible NPC carrier is currently available for this pickup' end
 local posted=Tasks.post(u,offer)
 u.credits=u.credits-price-fee
 lot.playerDelivery=posted.id
 orders[posted.id]={id=posted.id,hull=lot.hull,source=offer.source,target=target,lot=lot.id,price=price,fee=fee,
  status='listed',pickupBy=u.clock+PICKUP_WINDOW,carrier=carrier}
 return orders[posted.id]
end

local function refundOrder(u,order,status)
 local lot=Dealers().find(u,order.source,order.lot)
 if lot and lot.playerDelivery==order.id then lot.playerDelivery=nil end
 Tasks.state(u).offers[order.id]=nil
 u.credits=u.credits+order.price+order.fee
 order.status=status
end

function SD.cancelPlayer(u,id)
 local order=playerOrders(u)[id]
 if not order or order.status~='listed' then return nil,'The ship has already been picked up' end
 refundOrder(u,order,'cancelled')
 return true
end

function SD.updatePlayerOrders(u,clock)
 local offers=Tasks.state(u).offers
 for _,order in pairs(playerOrders(u)) do
  if active(order) and not offers[order.id] then
   refundOrder(u,order,'lost')
  elseif order.status=='listed' and order.pickupBy and clock>=order.pickupBy then
   refundOrder(u,order,'expired')
  elseif active(order) and not offers[order.id].parking then
   reserveParking(u,order)
  end
 end
end

-- Keep a hauler that's flying in the scene in step with its record: its
-- entity draws and collides with what's on its berths.
local function mirror(game, r)
	if not (game and game.entities) then return end
	for _, e in ipairs(game.entities) do
		if e.alifeId == r.id and not e.removed then
			e.carried = r.ship.carried and copy(r.ship.carried) or nil
			require("src.ship").updateMass(e)
		end
	end
end

-- Load the promised ship onto a free berth. False if it's gone or won't fit.
local function load(u, r, t)
	local D = Dealers()
	local lot = D.find(u, t.source, t.lot)
	if not lot or lot.playerDelivery and lot.playerDelivery~=t.id then return false end
 if t.playerDelivery and lot.playerDelivery~=t.id then return false end
 if t.playerDelivery then
  local order=playerOrders(u)[t.id]
  if not order or order.status~='listed' or u.clock>=order.pickupBy then return false end
 end
	local slot = Berths.free(carrierOf(r), lot.hull)
	if not slot then return false end
	if not reserveParking(u,t) then return false,"destination parking unavailable" end
	D.take(u, t.source, t.lot)
	local rec = D.ship(lot)
	rec.delivery, rec.lot = t.id, copy(lot)
	r.ship.carried = r.ship.carried or {}
	r.ship.carried[slot] = rec
 if t.playerDelivery then
  local order=playerOrders(u)[t.id]
  order.status='in transit'
 end
 Tasks.state(u).offers[t.id].loaded=true
	t.berth, t.phase = slot, "delivery"
	return true
end

Tasks.register("ship_delivery", {
	requires = { capabilities = { "berths" } },
	plan = function(t, station, clock)
		if t.phase == "pickup" then return G.itinerary(station,t.source,clock,true) end
		return G.itinerary(station,t.target,clock,true)
	end,
	eligible = function(u, r, o, station, clock)
  if o.playerDelivery then
   local order=playerOrders(u)[o.id]
   if not order or order.status~='listed' or clock>=order.pickupBy then return false end
  end
		if station ~= o.source and (r.task or not L.byId[station]) then return false end
		if not (L.byId[o.source] and L.byId[o.target]) then return false end
		local lot=Dealers().find(u,o.source,o.lot)
        if not lot or lot.playerDelivery and lot.playerDelivery~=o.id then return false end
		return Berths.free(carrierOf(r), o.hull) ~= nil
	end,
	feasible = function(u, r, o, station, clock)
		return (station == o.source or G.itinerary(station,o.source,clock,true) ~= nil)
   and G.itinerary(o.source,o.target,clock,true) ~= nil and destinationParking(u,o)~=nil
	end,
	score = function(u, r, o, station, clock)
		local pay = payment(o, clock)
		return pay / math.max(60, Transport().duration(o, station, clock)) * 100 - (station ~= o.source and 50 or 0)
	end,
	prepare = function(u, r, t, station, clock)
		t.route = G.itinerary(t.source,t.target,clock,true)
		if not t.route then return false end
		t.phase = "pickup"
		t.parking=nil
		if station ~= t.source then return reserveParking(u,t)~=nil end
		return load(u, r, t)
	end,
 release = function(u,r,t)
  local board=Tasks.state(u).offers
  if not t.playerDelivery then
   if t.phase=='delivery' then board[t.id]=nil
   elseif board[t.id] then board[t.id].parking=nil end
   return
  end
  if t.settled or t.phase~='delivery' then return end
  local order=playerOrders(u)[t.id]
  if order and order.id==t.id and order.status=='in transit' then
   order.status='lost'
   u.credits=u.credits+order.price+order.fee
   Tasks.state(u).offers[t.id]=nil
  end
 end,
	complete = function(u, r, t, station, clock, game)
		if t.settled then return true end
		if t.phase == "pickup" then
			if station ~= t.source then return false end
			local loaded,reason=load(u,r,t)
   if not loaded then Tasks.release(u,r,reason or "ship gone",clock) else mirror(game,r) end
			return false
		end
		if station ~= t.target then return false end
		local carried = r.ship.carried or {}
		local rec = t.berth and carried[t.berth]
		if not (rec and rec.delivery == t.id) then Tasks.release(u, r, "ship lost", clock) return false end
  if t.playerDelivery then
   local order=playerOrders(u)[t.id]
   if not order or order.status~='in transit' then return false end
   local parking=reserveParking(u,t)
   if not parking then order.waitingParking=true;return false end
   order.waitingParking=nil
   rec.delivery,rec.lot=nil,nil
   rec.bay,rec.mooring=parking.bay,parking.mooring
   local record=require('src.stockpile').record(u,station)
   record.hangar=record.hangar or {}
   record.hangar[#record.hangar+1]=rec
   carried[t.berth]=nil
   if not next(carried) then r.ship.carried=nil end
   mirror(game,r)
   require('src.accounts').receive(u,t.source,order.price,'sold','ship:'..rec.hull)
   r.credits=(r.credits or 0)+order.fee
   r.freightEarnings=(r.freightEarnings or 0)+order.fee
   order.status='delivered'
   t.settled=true
   return true
  end
		-- onto the dealer's lot, parked outside while there's room
		local D = Dealers()
		local s = D.state(u, station)
		local lot = rec.lot or { hull = rec.hull, loadout = rec.loadout, price = t.price }
		lot.armor = rec.armor or lot.armor
		local parking = reserveParking(u,t)
		if not parking then return false end   -- no room yet: wait docked
		s.serial=(s.serial or 0)+1
		lot.id=s.serial
		lot.bay, lot.mooring, lot.dealerStock, lot.deliveredAt = parking.bay, parking.mooring, true, clock
		s.lots[#s.lots + 1] = lot
		carried[t.berth] = nil
		if not next(carried) then r.ship.carried = nil end
		mirror(game, r)
		local pay = require("src.accounts").pay(u, station, payment(t, clock), "freight")
		r.credits = (r.credits or 0) + pay
		r.freightEarnings = (r.freightEarnings or 0) + pay
		t.settled = true
		return true
	end,
})

-- Ship-delivery berths an area wants among its haulers: one where a
-- shipyard builds ships for sale, while any shop sells what they build.
-- (The hauler population in src/alife.lua adds these to its target and
-- buys a berth hull for the next arrival while they're missing.)
function SD.berthsWanted(area)
	if not L.station(area, "trade") then return 0 end
	local factories, shops = stations()
	if #shops == 0 then return 0 end
	for _, key in ipairs(factories) do
		if L.byId[key] and L.byId[key].area == area then return 1 end
	end
	return 0
end
-- Haulers homed here working ship delivery.
function SD.berthHaulers(u, area)
	local n = 0
	for _, r in pairs(u.npcs or {}) do
		if r.populationGroup == "hauler" and r.workProfile == "ship_hauler" and r.home == area
			and r.state ~= "dead" and r.state ~= "escaped" then n = n + 1 end
	end
	return n
end

return SD
