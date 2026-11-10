-- Factions and reputation: standing, heat and goodwill decay on the
-- universe clock, are saved, and drive station and patrol hostility.
return function(game)
 local Rep=require('src.reputation')
 local u=game.universe
 u.clock=u.clock or 0
 assert(Rep.ofNode('station:pluto_1')=='milliways','Milliways owns its freeport')
 assert(Rep.ofNode('station:belt_1')=='ceres','the belt is Ceres Concern')
 assert(Rep.ofNode('station:ceres_quarry_1')=='ceres','area names with underscores')
 assert(Rep.ofNode('station:jupiter_1')=='jove' and Rep.ofNode('station:mars_1')=='zhuhai','majors own their areas')
 assert(Rep.ofNode('station:mars_3')=='zhuhai','Heaven-Ladder is Zhuhai')
 assert(Rep.ofNode('station:uranus_1')=='bowman','Uranus is Bowman Atmospherics')
 assert(Rep.ofNode('station:triton_1')==nil,'Neptune is unowned')
 assert(Rep.ofRecord({role='trader',home='earth'})==nil,'traders are loners')
 assert(Rep.ofRecord({affiliation='estates',home='earth'})=='estates','explicit affiliation determines standing')
 local node='station:earth_1'
 assert(not Rep.hostile(Rep.stationAttitude(u,node)),'neutral to start')
 for _=1,4 do Rep.stationHit(u,node) end
 assert(Rep.hostile(Rep.stationAttitude(u,node)),'a few hits and the station turns hostile')
 assert(not Rep.hostile(Rep.stationAttitude(u,'station:earth_2')),'heat stays local')
 assert(Rep.standing(u,'estates')<0 and Rep.standing(u,'jove')==0,'only the owner minds')
 u.clock=u.clock+600
 assert(not Rep.hostile(Rep.stationAttitude(u,node)),'heat cools on the clock, even offline')
 -- saved
 local state=game:saveState()
 assert(state.reputation and state.reputation.standing.estates,'standing is saved')
 Rep.addStanding(u,'estates',-80)
 assert(Rep.hostile(Rep.stationAttitude(u,node)),'low standing alone is hostile')
 local patrol={affiliation='estates',home='earth'}
 assert(Rep.hostile(Rep.attitude(u,patrol)),'and so are its patrols')
 u.clock=u.clock+3600*100
 assert(Rep.tier(Rep.standing(u,'estates')).id=='neutral','standing forgives with time')
 local trader={role='trader'}
 Rep.shipHit(u,trader);Rep.shipHit(u,trader);Rep.shipHit(u,trader)
 assert(Rep.tier(Rep.attitude(u,trader)).id=='hostile','a ship remembers being shot')
 Rep.shipKilled(u,{task={kind='raid'}},'saturn')
 assert(Rep.standing(u,'diwan')>0,'killing pirates in their space pleases the owner')
 Rep.addStanding(u,'diwan',60)
 assert(Rep.priceFactor(u,'station:saturn_1')<1 and Rep.priceFactor(u,'station:mars_1')==1,'friends get discounts')
 print('reputation ok')
end
