-- Population templates seed identity and equipment preferences, never controllers.
-- $owner and $area are resolved from the spawn location, without faction cases.
--
-- Every NPC has two fixed fields, set once at spawn and kept for life:
--   job      what it does: hauler, miner, raider, guard or hunter
--   network  which economy it lives in: 'white' (the public market) or
--            'dark' (the pirate shadow economy around dark grids)
-- A smuggler is a dark hauler, a pirate a dark raider; no extra roles.
-- Salvage is board work any hauler can take (workProfile 'scavenger' is a
-- hauler's temperament, not a job), so there is no salvager population.
local Templates={
 -- Haulers: the civilian freight fleet. They carry what the board offers
 -- (freight, salvage, satellite runs); one flying a hull with berths
 -- moves new ships to dealer lots too (src/ship_delivery.lua).
 hauler={job='hauler',network='white',purchase={role='hauler',budget=75000,minCargo=4,requires={cargo=true}},label='Hauler',
  -- temperament: most haulers prefer freight, some prefer sweeping wrecks
  profiles={{'freight_regular',4},{'scavenger',1}},homePurpose='trade',mobile=true},
 miner={job='miner',network='white',purchase={role='miner',budget=75000,requires={cargo=true,drill=true}},label='Miner',profile='industrial',homePurpose='mining'},
 patrol={job='guard',network='white',purchase={role='patrol',budget=80000,requires={armed=true},faction='$owner',
  -- Faction police fly their own service hulls, never bought off a lot.
  fleets={estates={'estates_whisper','estates_rapier','estates_bastion'},diwan={'diwan_cherubim','diwan_seraph'}}},label='Faction Police',profile='local_police',homePurpose='trade',affiliation='$owner',
  authorizations={{kind='police',issuer='$owner',jurisdiction='$area'}}},
 pirate={job='raider',network='dark',purchase={role='pirate',budget=75000,requires={armed=true}},label='Raider',profile='raider',homePurpose='pirateBase',roamingHome=true},
 -- Wildcats: the crews of instanced sites (src/wildcats.lua). Raiders on
 -- the dark network, but no population: a site rolls its crew once.
 wildcat={job='raider',network='dark',purchase={role='pirate',budget=60000,requires={armed=true}},label='Wildcat',profile='wildcat',homePurpose='pirateBase',roamingHome=true},
 -- (wildcats start small-time: a proficient one can't reach a 70k hull, a
 -- veteran or elite now and then can; a rich one trades up at the fence)
 -- Bounty hunters: armed freelancers who take site bounties off the
 -- board, and sweep wrecks when there are none (src/wildcats.lua).
 hunter={job='hunter',network='white',purchase={role='patrol',budget=90000,requires={armed=true}},label='Bounty Hunter',profile='bounty_hunter',homePurpose='trade'},
}
-- Faction couriers: the faction's own errand runners. Same service hulls
-- and colours as its police, but ordinary freight work, so police never
-- haul and the faction still moves its own goods.
Templates.courier={job='hauler',network='white',purchase={role='hauler',budget=300000,minCargo=4,requires={cargo=true},faction='$owner',
 fleets=Templates.patrol.purchase.fleets},label='Faction Courier',profile='freight_regular',homePurpose='trade',mobile=true,affiliation='$owner'}
-- A hauler bought for ship delivery: any hull with berths (src/berths.lua),
-- and a temperament for moving ships. Same population, same label.
Templates.berthPurchase={role='hauler',budget=400000,requires={berths=true}}
-- Ship budgets (at proficient; src/npc_rank.lua scales them: rookie .8,
-- elite 1.5, veteran 2) keep the top hulls rare: at 75k a rookie flies
-- something under 60k, a proficient pilot a Bison, Longhorn or Nautilus at
-- most, and only an elite one (112k) can reach an Archangel. Faction
-- fleets (patrol, couriers) fly their own service hulls.
Templates.JOBS={hauler=true,miner=true,raider=true,guard=true,hunter=true}
Templates.NETWORKS={white=true,dark=true}
-- Older saves: the retired salvager group becomes a scavenging hauler.
Templates.RETIRED={salvager={group='hauler',profile='scavenger'},
 trader={group='hauler'},ship_hauler={group='hauler',profile='ship_hauler'}}
function Templates.purchase(name) return assert(Templates[name]).purchase end
-- What a ship has to be able to do for this NPC's work: a ship-delivery
-- hauler needs berths, not a hold.
function Templates.purchaseFor(r)
 if r.workProfile=='ship_hauler' then return Templates.berthPurchase end
 local t=Templates[r.populationGroup]
 return t and t.purchase
end
-- Deterministic temperament pick from a template's weighted profiles.
local function profileFor(t,id)
 if not t.profiles then return t.profile end
 local total,seed=0,7
 for _,p in ipairs(t.profiles) do total=total+p[2] end
 for i=1,#(id or '') do seed=(seed*31+id:byte(i))%2147483647 end
 local roll=seed%total
 for _,p in ipairs(t.profiles) do roll=roll-p[2];if roll<0 then return p[1] end end
 return t.profiles[1][1]
end
function Templates.job(r)
 if r.job then return r.job end
 local t=Templates[r.populationGroup]
 return t and t.job or (r.populationGroup=='salvager' and 'hauler') or nil
end
function Templates.network(r) return r.network or (Templates[r.populationGroup] or {}).network or 'white' end
function Templates.isDark(r) return Templates.network(r)=='dark' end
-- Dark access: who may trade, work and berth on the dark grids. Every dark
-- NPC (raiders) has it, as does anyone born on a dark grid and every hauler
-- who signed on with the Milliways runners (src/dark_runners.lua). Ordinary
-- crews go no further than a fence.
function Templates.darkAccess(r)
 if r.player or Templates.isDark(r) then return true end
 -- born on a dark grid, or signed on with the runners (src/dark_runners.lua)
 return r.darkAccess==true
end
-- Fill job/network on records saved before they existed, and fold retired
-- groups into their replacement. Safe to call every load.
function Templates.migrate(r)
 local old=Templates.RETIRED[r.populationGroup]
 if old then
  local t=Templates[old.group]
  r.populationGroup=old.group;r.label=t.label;r.workProfile=r.workProfile or old.profile
  r.homePurpose=t.homePurpose;r.mobile=t.mobile;r.taskWorker=true
 end
 local t=Templates[r.populationGroup]
 if t then r.job=r.job or t.job;r.network=r.network or t.network end
 if r.darkAccess==nil and r.job then
  -- someone already living on a dark grid keeps living there
  local home=r.homeStation and require('src.locations').byId[r.homeStation]
  r.darkAccess=Templates.darkAccess(r) or (home~=nil and require('src.dark').isDarkArea(home.area))
 end
 -- (a save from when a fixed share of white crews worked the dark grids:
 -- only those who live there or signed on keep it)
 if r.darkAccess and not r.darkRunner and not r.darkAccessV then
  local home=r.homeStation and require('src.locations').byId[r.homeStation]
  r.darkAccess=home~=nil and require('src.dark').isDarkArea(home.area) or false
 end
 r.darkAccessV=2
 return r
end
function Templates.apply(r,name,area)
 local t=assert(Templates[name],'unknown NPC template '..name)
 r.populationGroup=name;r.label=t.label;r.workProfile=profileFor(t,r.id)
 r.job=t.job;r.network=t.network;r.darkAccess=nil
 -- born on a dark grid: whoever it is, it knows the way
 r.darkAccess=Templates.darkAccess(r) or (area~=nil and require('src.dark').isDarkArea(area))
 r.homePurpose=t.homePurpose;r.mobile=t.mobile;r.roamingHome=t.roamingHome
 local owner=require('src.npc_access').owner(area)
 local function resolve(v) if v=='$owner' then return owner elseif v=='$area' then return area else return v end end
 r.affiliation=resolve(t.affiliation);r.authorizations={}
 for _,grant in ipairs(t.authorizations or {}) do
  local g={};for k,v in pairs(grant) do g[k]=resolve(v) end
  if g.issuer then r.authorizations[#r.authorizations+1]=g end
 end
 return r
end
return Templates
