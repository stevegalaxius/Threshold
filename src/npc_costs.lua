--[[
	Running costs: what keeping a ship flying costs its pilot, besides the
	fuel, ammo and repairs it buys at stations (src/supplies.lua).

	  crew        T.npcCrewWage credits an hour
	  upkeep      T.npcMaintenanceShare of the ship's list price an hour
	  shore leave T.npcShoreLeave of the credits a pilot holds over
	              T.npcSavings, an hour: money spent ashore, so wallets
	              settle instead of growing without end

	All of it is paid to the pilot's home station (else the trade station
	of the area it is in), so it goes back into the economy rather than
	vanishing. A pilot that can't pay just pays what it has.
]]
local T=require('src.tuning')
local L=require('src.locations')
local data=require('src.data')
local C={}
function C.hourly(r)
 local hull=r.ship and data.hulls[r.ship.hull]
 local value=hull and require('src.dealers').price(hull,r.ship.loadout) or 0
 local surplus=math.max(0,(r.credits or 0)-T.npcSavings)
 return T.npcCrewWage+value*T.npcMaintenanceShare+surplus*T.npcShoreLeave
end
local function payee(r)
 if r.homeStation and L.byId[r.homeStation] then return r.homeStation end
 return r.area and L.station(r.area,'trade')
end
function C.update(u,clock)
 if clock<(u.npcCostsNext or 0) then return end
 local hours=(clock-(u.npcCostsAt or clock))/3600
 u.npcCostsNext=clock+T.npcCostTick;u.npcCostsAt=clock
 if hours<=0 then return end
 local Accounts=require('src.accounts')
 local ids={};for id in pairs(u.npcs or {}) do ids[#ids+1]=id end;table.sort(ids)
 for _,id in ipairs(ids) do
  local r=u.npcs[id]
  if r.state~='dead' and r.state~='escaped' and r.ship then
   local cost=math.min(math.max(0,r.credits or 0),C.hourly(r)*hours)
   if cost>0 then
    r.credits=r.credits-cost;r.runningCosts=(r.runningCosts or 0)+cost
    local to=payee(r)
    if to then Accounts.receive(u,to,cost,'sold','running costs') end
   end
  end
 end
end
return C
