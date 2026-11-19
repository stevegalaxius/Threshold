--[[
	Docking fee: every ship that docks at a station pays it once per visit,
	the player and NPC pilots alike, priced by the hangar cells the hull
	takes (src/berth_rent.lua's footprint): T.dockFeePerCell a cell, at
	least T.dockFeeMin. It goes into the station's own account (or its
	faction's, for a faction-run yard or hub: src/accounts.lua).

	A pilot that can't pay the whole fee pays what it has: nobody is turned
	away at the door.
]]
local T=require('src.tuning')
local F={}
function F.amount(hullId)
 if not hullId then return 0 end
 local cells=require('src.berth_rent').footprint(hullId)
 return math.max(T.dockFeeMin,math.floor(cells*T.dockFeePerCell+.5))
end
local function station(node)
 local p=node and require('src.locations').byId[require('src.locations').canonical(node)]
 return p and p.kind=='station'
end
-- An NPC record docking at node. Returns what it paid.
function F.npc(u,r,node)
 if not (u and r and r.ship and station(node)) then return 0 end
 local paid=math.min(math.max(0,r.credits or 0),F.amount(r.ship.hull))
 if paid<=0 then return 0 end
 r.credits=r.credits-paid;r.dockFees=(r.dockFees or 0)+paid
 require('src.accounts').receive(u,node,paid,'sold','docking')
 return paid
end
-- The player docking at station key with hull. Returns what it paid.
function F.player(u,key,hullId)
 if not (u and station(key)) then return 0 end
 local paid=math.min(math.max(0,u.credits or 0),F.amount(hullId))
 if paid<=0 then return 0 end
 u.credits=u.credits-paid
 require('src.accounts').receive(u,key,paid,'sold','docking')
 return paid
end
return F
