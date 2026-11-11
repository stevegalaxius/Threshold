-- Scavenging: one loot loop, role profiles. Pirates stop at a few units,
-- salvagers fill the hold, and anything taken lands in the role's manifest.
return function(game)
 local S=require('src.scavenge')
 local T=require('src.tuning')
 local pirate,salv={task={kind='raid'}},{role='salvager',task={kind='salvage'}}
 assert(S.profile(pirate) and S.profile(salv) and not S.profile({role='trader'}),'pirates and active salvage workers scavenge')
 S.took(pirate,'water_ice',T.pirateLootUnits,0)
 assert(pirate.stolenCargo.water_ice==T.pirateLootUnits and S.done(pirate,0),'pirates stop at their cut')
 S.took(salv,'water_ice',500,0)
 assert(salv.salvageCargo.water_ice==500 and not S.done(salv,0),'salvagers keep going until the hold is full')
 assert(S.done(salv,T.salvagerCollectTime+1),'or until they have looked long enough')
 assert(S.profile(salv).clears and not S.profile(pirate).clears,'only salvagers clear wrecks away')
 salv.label='Trader'
 assert(S.profile(salv).clears,'traders use the salvage handler while working salvage')
 salv.task={kind='transport'}
 assert(not S.profile(salv),'freight cargo is never treated as salvage')
 print('scavenge ok')
end
