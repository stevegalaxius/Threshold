-- Scavenging: one loot loop, role profiles. Pirates stop at a few units,
-- salvagers fill the hold, and anything taken lands in the role's manifest.
return function(game)
 local S=require('src.scavenge')
 local T=require('src.tuning')
 local pirate,salv={role='pirate'},{role='salvager'}
 assert(S.profile(pirate) and S.profile(salv) and not S.profile({role='trader'}),'pirates and salvagers scavenge')
 S.took(pirate,'scrap',T.pirateLootUnits,0)
 assert(pirate.stolenCargo.scrap==T.pirateLootUnits and S.done(pirate,0),'pirates stop at their cut')
 S.took(salv,'scrap',500,0)
 assert(salv.salvageCargo.scrap==500 and not S.done(salv,0),'salvagers keep going until the hold is full')
 assert(S.done(salv,T.salvagerCollectTime+1),'or until they have looked long enough')
 assert(S.profile(salv).clears and not S.profile(pirate).clears,'only salvagers clear wrecks away')
 print('scavenge ok')
end
