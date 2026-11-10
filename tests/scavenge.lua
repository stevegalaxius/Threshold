-- Scavenging: one loot loop, role profiles. Pirates stop at a few units,
-- salvagers fill the hold, and anything taken lands in the role's manifest.
return function(game)
 local S=require('src.scavenge')
 local T=require('src.tuning')
 local pirate,salv={role='pirate'},{role='salvager',task={kind='salvage'}}
 assert(S.profile(pirate) and S.profile(salv) and not S.profile({role='trader'}),'pirates and active salvage workers scavenge')
 S.took(pirate,'scrap',T.pirateLootUnits,0)
 assert(pirate.stolenCargo.scrap==T.pirateLootUnits and S.done(pirate,0),'pirates stop at their cut')
 S.took(salv,'scrap',500,0)
 assert(salv.salvageCargo.scrap==500 and not S.done(salv,0),'salvagers keep going until the hold is full')
 assert(S.done(salv,T.salvagerCollectTime+1),'or until they have looked long enough')
 assert(S.profile(salv).clears and not S.profile(pirate).clears,'only salvagers clear wrecks away')
 salv.role='trader'
 assert(S.profile(salv).clears,'traders use the salvage handler while working salvage')
 salv.task={kind='transport'}
 assert(not S.profile(salv),'freight cargo is never treated as salvage')
 print('scavenge ok')
end
