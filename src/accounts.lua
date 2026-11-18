--[[
	Money that stations and factions actually have.

	Every station keeps its own account, opened with T.stationOpeningCredits,
	except the ones its faction runs directly (a military yard, or a layout
	entry with funding = 'faction'), which pay and take in through their
	faction's account (T.factionOpeningCredits). A station also pays its
	faction T.factionTax of what it takes in, and police wages come out of
	the faction's account.

	A.pay never goes below zero: it pays what the account holds and returns
	that, so an empty station pays haulers, miners and sellers less (or
	nothing) until it sells something. A.receive banks income. Both write
	the ledger (src/economy.lua) as before.

	  u.accounts = { [account id] = credits }   ('station:x' or 'faction:y')
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
-- Pay out up to n; returns what was paid.
function A.pay(u,key,n,kind,item)
 if not key or not n or n<=0 then return 0 end
 local s=A.state(u);local id=A.of(key)
 local paid=math.min(n,A.balance(u,key))
 s[id]=s[id]-paid
 if paid<n then
  local short=u.accountShort or {};u.accountShort=short;short[id]=(short[id] or 0)+(n-paid)
 end
 if kind then require('src.economy').ledger(u,key,kind,paid,item) end
 return paid
end
function A.canPay(u,key,n) return A.balance(u,key)>=(n or 0) end
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
 if kind then require('src.economy').ledger(u,key,kind,n,item) end
 return n
end
-- Pay a faction directly (police wages).
function A.factionPay(u,faction,n)
 if not faction then return 0 end
 return A.pay(u,'faction:'..faction,n)
end
return A
