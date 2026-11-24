--[[
	Money that stations and factions actually have.

	Every station keeps its own account, opened with T.stationOpeningCredits,
	except the ones its faction runs directly (a military yard, a logistics
	hub, a moon's customs house, or a layout entry with funding = 'faction'), which pay and take in through their
	faction's account (T.factionOpeningCredits). A station also pays its
	faction T.factionTax of what it takes in, and police wages come out of
	the faction's account.

	Nobody goes broke: A.pay always pays in full. A station pays down to
	T.stationFloor, its faction covers the rest down to T.factionFloor, and
	past that the faction's home economy (outside the game) sends the
	money; an independent station's backers do the same. What came from
	outside is tallied in u.accountSubsidy so a soak can see the leak.
	A.receive banks income. Both write the ledger (src/economy.lua).

	Each faction's surplus or deficit is what quests and world state read
	instead of bankruptcy: A.flow(u, faction) is its takings and spending
	per hour, its own stations included, as a rolling average over
	T.factionFlowHours. An independent station is its own party, by id.

	  u.accounts = { [account id] = credits }   ('station:x' or 'faction:y')
	  u.factionFlow = { [party] = { income, spending, at } }
]]
local L=require('src.locations')
local T=require('src.tuning')
local A={}
local function owner(key)
 local place=L.byId[key];local area=place and place.area
 return area and require('src.npc_access').owner(area)
end
-- Is this station run straight off its faction's books?
function A.factionRun(key)
 key=L.canonical(key)
 local place=L.byId[key]
 if not place then return false end
 if place.funding=='faction' then return true end
 -- a logistics hub is its faction's own depot, stocked for the whole system,
 -- and a moon's customs house its depot for the moon: both only pass goods on
 if place.hub or place.customs then return true end
 local def=require('src.dealers').def(key)
 return def~=nil and def.service~=nil
end
-- The account that pays and is paid at this station (or a faction id).
function A.of(key)
 if type(key)=='string' and key:match('^faction:') then return key end
 key=L.canonical(key)
 if A.factionRun(key) then local f=owner(key);if f then return 'faction:'..f end end
 return key
end
local function opening(id)
 if id:match('^faction:') then return T.factionOpeningCredits end
 return T.stationOpeningCredits
end
function A.state(u) u.accounts=u.accounts or {};return u.accounts end
function A.balance(u,key)
 if not key then return 0 end
 local s=A.state(u);local id=A.of(key)
 if s[id]==nil then s[id]=opening(id) end
 return s[id]
end
-- Who a transaction's money belongs to: the station's faction, or the
-- station itself when it has none.
local function party(key,id)
 local f=id:match('^faction:(.+)')
 if f then return f end
 return owner(L.canonical(key)) or id
end
local function decay(rec,clock)
 local k=2^(-math.max(0,clock-rec.at)/(T.factionFlowHours*3600))
 rec.income,rec.spending,rec.at=rec.income*k,rec.spending*k,clock
end
local function track(u,key,id,field,n)
 local p=party(key,id)
 local flows=u.factionFlow or {};u.factionFlow=flows
 local rec=flows[p] or {income=0,spending=0,at=u.clock or 0};flows[p]=rec
 decay(rec,u.clock or 0)
 rec[field]=rec[field]+n
end
-- { income, spending, net } in credits per hour, rolling. net < 0 is a
-- deficit the faction's home economy is covering.
function A.flow(u,p)
 local rec=u.factionFlow and u.factionFlow[p]
 if not rec then return {income=0,spending=0,net=0} end
 decay(rec,u.clock or 0)
 -- an exponential sum holds about halfLife/ln2 hours of flow
 local hours=T.factionFlowHours/math.log(2)
 local i,s=rec.income/hours,rec.spending/hours
 return {income=i,spending=s,net=i-s}
end
function A.parties(u) local out={} for p in pairs(u.factionFlow or {}) do out[#out+1]=p end table.sort(out) return out end
local function floor(id) return id:match('^faction:') and T.factionFloor or T.stationFloor end
-- Take up to n from an account without going below its floor.
local function draw(s,id,n)
 local take=math.max(0,math.min(n,s[id]-floor(id)))
 s[id]=s[id]-take
 return take
end
function A.spendable(u,key)
 return math.max(0,A.balance(u,key)-floor(A.of(key)))
end
function A.refund(u,key,n)
 local balance=A.balance(u,key)
 A.state(u)[A.of(key)]=balance+n
end
-- Pay n in full; returns n.
function A.pay(u,key,n,kind,item)
 if not key or not n or n<=0 then return 0 end
 local s=A.state(u);local id=A.of(key)
 A.balance(u,key)
 local rest=n-draw(s,id,n)
 if rest>0 and not id:match('^faction:') then
  local f=owner(L.canonical(key))
  if f then
   local fid='faction:'..f;if s[fid]==nil then s[fid]=opening(fid) end
   rest=rest-draw(s,fid,rest)
   if rest>0 then id=fid end
  end
 end
 if rest>0 then
  local sub=u.accountSubsidy or {};u.accountSubsidy=sub;sub[id]=(sub[id] or 0)+rest
 end
 track(u,key,A.of(key),'spending',n)
 if kind then require('src.economy').ledger(u,key,kind,n,item) end
 return n
end
-- Every account can pay (A.pay above); kept for callers that ask.
function A.canPay(u,key,n) return true end
-- Bank n; a station that isn't faction-run passes its tax up.
function A.receive(u,key,n,kind,item)
 if not key or not n or n<=0 then return 0 end
 local s=A.state(u);local id=A.of(key)
 A.balance(u,key)
 local tax=0
 if not id:match('^faction:') then
  local f=owner(L.canonical(key))
  if f then
   tax=n*T.factionTax
   local fid='faction:'..f;if s[fid]==nil then s[fid]=opening(fid) end
   s[fid]=s[fid]+tax
  end
 end
 s[id]=s[id]+n-tax
 track(u,key,id,'income',n)
 if kind then require('src.economy').ledger(u,key,kind,n,item) end
 return n
end
-- Pay a faction directly (police wages).
function A.factionPay(u,faction,n)
 if not faction then return 0 end
 return A.pay(u,'faction:'..faction,n)
end
return A
