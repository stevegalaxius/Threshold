-- Job + network: every NPC has a fixed job and economy network, and the
-- retired salvager group folds into a scavenging hauler on load.
return function(game)
 local Templates=require('src.npc_templates')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local want={trader={'hauler','white'},miner={'miner','white'},patrol={'guard','white'},pirate={'raider','dark'}}
 for _,r in pairs(game.universe.npcs) do
  local w=want[r.populationGroup]
  if w then check(r.job==w[1] and r.network==w[2],('%s %s has job %s on %s'):format(r.populationGroup,r.id,tostring(r.job),tostring(r.network))) end
  check(Templates.JOBS[Templates.job(r) or 'hauler'] and Templates.NETWORKS[Templates.network(r)],'unknown job or network on '..r.id)
 end
 local old=Templates.migrate({id='npc/old',populationGroup='salvager',workProfile='scavenger'})
 check(old.populationGroup=='trader' and old.job=='hauler' and old.network=='white' and old.workProfile=='scavenger','old salvager did not become a scavenging hauler')
 local legacy=Templates.migrate({id='npc/legacy',populationGroup='pirate'})
 check(legacy.job=='raider' and Templates.isDark(legacy),'old pirate record did not land on the dark network')
 -- haulers split by temperament, deterministically by id
 local seen={}
 for i=1,40 do local r=Templates.apply({id='npc/t'..i},'trader','earth');seen[r.workProfile]=true
  check(Templates.apply({id='npc/t'..i},'trader','earth').workProfile==r.workProfile,'temperament pick is not stable') end
 check(seen.freight_regular and seen.scavenger,'haulers never pick up the scavenger temperament')
 print(('NPC ROLES TEST PASSED (%d checks)'):format(checks))
end
