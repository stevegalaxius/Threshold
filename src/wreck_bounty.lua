--[[
	Wreck-clearing bounties. Each system's trade station (the one that posts
	its satellite work: src/sat_jobs.lua J.places) pays a standing bounty for
	every ship wreck cleared out of that system. Whoever clears it is paid:
	an NPC clean-up crew straight into its own credits (on top of whatever it
	sells the loot for: src/salvager.lua), the player into a tab with that
	station, collected from the Jobs screen at any station in its system.

	"Cleared" means the wreck is gone: drilled apart or shot apart, online
	(Game reap) or offline (src/offline_loot.lua strips it). Only wrecks of
	ships that died count (a husk with an origin, or a saved combat wreck),
	not authored derelicts or satellites. A wreck that broke into pieces is
	paid once, when its last piece goes.

	Saved state: u.wreckBounty = { owed = {[station]=credits}, cleared = {[station]=n},
	  heads = {[station]=n} }   (heads: wildcat bounties, src/wildcats.lua, paid into the same tab)
]]
local T=require('src.tuning')
local L=require('src.locations')
local B={}

function B.state(u)
 u.wreckBounty=u.wreckBounty or {owed={},cleared={}}
 return u.wreckBounty
end
-- The station paying for wrecks cleared in this area (nil: nobody does).
function B.payer(area)
 if not area then return end
 return (require('src.sat_jobs').places(area))
end
-- Credits per cleared wreck: a flat fee plus a share for the hull's size.
function B.rate(steel) return math.floor(T.wreckBountyBase+(steel or 0)*T.wreckBountyPerSteel+.5) end
-- The areas a station pays for (its system, and any quiet region it covers).
function B.areas(station)
 local out={}
 for _,area in ipairs(require('src.fields').list) do
  if B.payer(area)==station then out[#out+1]=area end
 end
 return out
end

local function steelOf(record)
 if record.steel then return record.steel end
 local hull=record.ship and record.ship.hull or type(record.hull)=='table' and record.hull.id or record.hull
 local data=require('src.data')
 return require('src.game').wreckSteel(data.hulls[hull])
end
-- A wreck that broke apart is cleared with its last piece.
local function lastPiece(game,record,list)
 local o=record.origin;if not o then return true end
 for _,e in ipairs(game and game.entities or {}) do
  if e~=record and e.kind=='husk' and e.origin==o and not e.dead and not e.removed then return false end
 end
 for _,s in ipairs(list or {}) do
  if s~=record and s.kind=='husk' and s.origin and o.npc and s.origin.npc==o.npc then return false end
 end
 return true
end

-- A wreck is gone. who: the A-Life record or live entity that cleared it
-- (nil when nobody in particular did); record: the husk or saved wreck.
function B.cleared(game,who,record,area,list)
 local u=game and game.universe
 if not u or not record or record.sat then return end
 if not (record.origin or record.ship) then return end -- an authored derelict
 if not lastPiece(game,record,list) then return end
 local station=B.payer(area);if not station then return end
 local pay=B.rate(steelOf(record))
 if who and who.isPlayer then
  local s=B.state(u)
  s.owed[station]=(s.owed[station] or 0)+pay
  s.cleared[station]=(s.cleared[station] or 0)+1
  if game.toast then game:toast(('Wreck cleared: %d CR bounty at %s'):format(pay,(L.byId[station] or {}).name or station),2.5) end
  return pay
 end
 local r=who and (who.alifeId and (u.npcs or {})[who.alifeId] or who.ship and who.id and who)
 if r then
  pay=require('src.accounts').pay(u,station,pay,'bounty')
  r.credits=(r.credits or 0)+pay;r.bountyEarnings=(r.bountyEarnings or 0)+pay
  return pay
 end
end

-- Wrecks still out there for a station's bounty: saved combat wrecks, saved
-- wreck objects and live husks in the loaded area. Pieces count once.
function B.count(game,station)
 local u=game.universe;local n=0;local seen={}
 local function add(key) if key and seen[key] then return end;if key then seen[key]=true end;n=n+1 end
 for _,area in ipairs(B.areas(station)) do
  for id,w in pairs(u.alifeWrecks or {}) do
   if w.area==area and u.clock<(w.expires or math.huge) then add('w/'..id) end
  end
  if game.fieldId==area then
   for _,e in ipairs(game.entities or {}) do
    if e.kind=='husk' and e.origin and not e.sat and not e.dead and not e.removed then add(e.origin.npc and 'n/'..e.origin.npc or e.origin) end
   end
  else
   local saved=u.areas and u.areas[area]
   for _,s in ipairs(saved and saved.objects or {}) do
    if s.kind=='husk' and s.origin and not s.sat then add(s.origin.npc and 'n/'..s.origin.npc or s) end
   end
  end
 end
 return n
end

function B.owed(u,station) return B.state(u).owed[station] or 0 end
function B.collect(game,station)
 local u=game.universe;local s=B.state(u);local pay=s.owed[station] or 0
 if pay<=0 then return nil,'No bounty owed here' end
 if not require('src.quests').willOffer(u,station) then return nil,'This station will not pay you' end
 local n=s.cleared[station] or 0
 local heads=s.heads and s.heads[station] or 0
 if not require('src.accounts').canPay(u,station,pay) then return nil,'The station can\'t pay its bounties right now' end
 require('src.accounts').pay(u,station,pay,'bounty')
 u.credits=u.credits+pay;s.owed[station]=nil;s.cleared[station]=nil
 if s.heads then s.heads[station]=nil end
 local parts={}
 if n>0 then parts[#parts+1]=('%d wreck%s'):format(n,n==1 and '' or 's') end
 if heads>0 then parts[#parts+1]=('%d wildcat%s'):format(heads,heads==1 and '' or 's') end
 return true,('Bounty collected: %d CR for %s'):format(pay,table.concat(parts,' and '))
end
return B
