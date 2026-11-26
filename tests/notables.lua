-- Notables and the world-state ledger (src/notables.lua, src/worldstate.lua).
-- 1. The cast is valid: every station, route, outlet, item, facility and
--    faction it names exists, and every consequence it would fire validates.
-- 2. Each role's death changes the world through the ledger: output,
--    prices, passenger demand, outlet reach and beats, stances.
-- 3. The ledger survives a save.
-- 4. VIP runs: posted on circuits, the player can book one, space them
--    (airlock), hand one over (capture); a carrier lost to someone else
--    lets them get away.
-- 5. Summits: a few leaders, or all of them at a grand one.
return function()
 local Game=require('src.game')
 local D=require('data.notables')
 local NB,WS=require('src.notables'),require('src.worldstate')
 local P,Tasks,L=require('src.passengers'),require('src.tasks'),require('src.locations')
 local Rep,News=require('src.reputation'),require('src.news')
 local Transport=require('src.transport')
 local Outlets=require('data.outlets').outlets
 local data=require('src.data')

 -- 1. validation
 local seen,roles={},{}
 for _,n in ipairs(D.cast) do
  assert(not seen[n.id],'duplicate notable '..n.id);seen[n.id]=true
  assert(D.roles[n.role],n.id..': unknown role '..tostring(n.role))
  assert(Rep.FACTIONS[n.faction],n.id..': unknown faction '..tostring(n.faction))
  roles[n.faction]=roles[n.faction] or {};roles[n.faction][n.role]=true
  assert(L.byId[n.seat],n.id..': unknown seat '..tostring(n.seat))
  for _,stop in ipairs(n.circuit or {}) do
   assert(L.byId[stop],n.id..': unknown circuit stop '..tostring(stop))
   assert(Transport.route(n.seat,stop,0) and Transport.route(stop,n.seat,0),n.id..': no route between '..n.seat..' and '..stop)
  end
  if n.role=='leader' then
   assert(Transport.route(n.seat,D.summit.station,0) and Transport.route(D.summit.station,n.seat,0),n.id..': no route to the summit')
  end
  if n.role=='journalist' then
   assert(Outlets[n.outlet] and Outlets[n.outlet].owner==n.faction,n.id..': outlet must be its faction\'s')
  end
  for _,item in ipairs(n.goods or {}) do assert(data.items[item],n.id..': unknown item '..item) end
  for _,e in ipairs(D.consequences(n)) do
   local ok,why=WS.validate(e)
   assert(ok,('%s: bad consequence %s (%s)'):format(n.id,WS.describe(e),tostring(why)))
  end
 end
 assert(roles.ceres and roles.ceres.ceo and roles.ceres.journalist and roles.bowman and roles.bowman.ceo,'corporations need their CEO and the Beltway its editor')
 for _,f in ipairs({'estates','zhuhai','jove','diwan','milliways'}) do
  for _,role in ipairs({'journalist','leader','magnate'}) do assert(roles[f] and roles[f][role],f..' has no '..role) end
 end

 -- 2. consequences
 local game=Game.new({preview=true});game.autosaveOff=true
 local u=game.universe
 NB.state(u)
 local I=require('src.industry')
 local function recipeAt(key,facility)
  local def=I.definition(facility,I.installations(key)[facility])
  return {id=def.recipes[1]}
 end
 local steel=recipeAt('station:mars_3','roll_steel')
 local before=I.scale(u,'station:mars_3',steel)
 local zstand=Rep.standing(u,'zhuhai')
 assert(NB.kill(u,'zhuhai_magnate',{how='test',by='player',area='mars',witnessed=true}))
 assert(WS.flag(u,'notable.zhuhai_magnate')=='dead','no world-state flag')
 assert(not NB.kill(u,'zhuhai_magnate',{how='again'}),'a notable died twice')
 assert(math.abs(WS.mul(u,'output','station:mars_3','roll_steel')-D.T.worksOutput)<1e-9,'magnate works not cut')
 assert(WS.mul(u,'output','station:mars_3','shipworks')==1,'cut spilled onto other lines')
 if before>0 then assert(I.scale(u,'station:mars_3',steel)<before,'facility scale ignores the ledger') end
 assert(Rep.standing(u,'zhuhai')<=zstand+D.roles.magnate.deed+1,'witnessed killing cost no standing')
 assert(#News.find(u,{kind='notable'})>=#News.order,'no obituaries printed')

 assert(NB.kill(u,'zhuhai_journalist',{how='test'}))
 assert(News.reach(u,'signal')<1,'dead editor\'s paper kept its reach')
 assert(News.covers(u,'gazette','mars'),'rival paper did not take over the beat')

 local price=require('src.markets').price(u,'station:pluto_1','food_crate')
 assert(Rep.stance('zhuhai','milliways',u)=='ambivalent')
 assert(NB.kill(u,'cartel_leader',{how='test'}))
 assert(Rep.stance('zhuhai','milliways',u)=='hostile','leader death did not change the stance')
 assert(require('src.markets').price(u,'station:pluto_1','food_crate')>price,'leaderless markets not dearer')
 -- a leaderless faction fields fewer police, who look for less long
 local S=require('src.security')
 local police=S.policeWanted(u,'earth')
 assert(police>0,'expected Estates police at Earth')
 assert(NB.kill(u,'estates_leader',{how='test'}))
 assert(police==0 or S.policeWanted(u,'earth')<police,('leaderless Estates still want %d police'):format(S.policeWanted(u,'earth')))
 assert(WS.mul(u,'inspections','faction:estates')<1 and WS.mul(u,'patrols','faction:zhuhai')==1)
 -- the corporations' CEOs take their company's security with them
 assert(NB.kill(u,'ceres_ceo',{how='test'}))
 assert(WS.mul(u,'patrols','faction:ceres')<1 and WS.mul(u,'output','station:belt_1','ice_wells')<1)

 -- 3. save round trip
 local state=require('src.persistence').copy(game:saveState())
 local g2=Game.new({preview=true});g2.autosaveOff=true
 g2:loadState(state)
 local u2=g2.universe
 assert(WS.flag(u2,'notable.cartel_leader')=='dead','flags lost in the save')
 assert(math.abs(WS.mul(u2,'output','station:mars_3','roll_steel')-D.T.worksOutput)<1e-9,'effects lost in the save')
 assert(Rep.stance('zhuhai','milliways',u2)=='hostile','stance lost in the save')
 assert(NB.person(u2,'cartel_leader').status=='dead')

 -- 4. VIP runs
 local jn=NB.defs.jove_journalist;local jp=NB.person(u,jn.id)
 jp.next=u.clock
 NB.update(u,u.clock)
 assert(jp.trip,'journalist did not post a VIP run')
 local vip=Tasks.state(u).offers[jp.trip.offer]
 assert(vip and vip.kind=='passenger' and vip.item=='vip' and vip.notable==jn.id and vip.party==1)
 assert(P.maxFare(vip)>P.maxFare({party=1,routeAU=vip.routeAU}),'VIP fare no better than a commuter\'s')
 -- an NPC carrier lost to someone else: they get away, back where they boarded
 NB.carrierDied(u,{id='npc/x'},{notable=jn.id,phase='delivery',source=vip.source},'npc/pirate','callisto')
 assert(NB.alive(u,jn.id) and not jp.trip and jp.at==vip.source,'a pirate kill ended a notable')
 Tasks.state(u).offers[vip.id]=nil

 -- the player books one and spaces them
 local Board=require('src.player_contracts')
 local pg=Game.new({preview=true});pg.autosaveOff=true
 local pu=pg.universe
 NB.state(pu)
 local here=NB.defs.estates_journalist
 if L.byId[here.seat].area~=pg.fieldId then pg:loadField(L.byId[here.seat].area) end
 do
  pg:spawnPlayer('amw_wayfarer')
  local st=assert(pg:locationEntity(here.seat))
  assert(pg:dockInstantly(pg.player,st));pg.state='docked'
  local o=P.postVIP(pu,here,here.seat,here.circuit[1],pu.clock)
  NB.person(pu,here.id).trip={offer=o.id,to=here.circuit[1]}
  local q,why=Board.quote(pg,o)
  assert(q,'player could not book the VIP: '..tostring(why))
  assert(Board.accept(pg,o.id))
  assert((pg.player.cargo.vip or 0)==1,'VIP not aboard')
  local f=here.faction;local s0=Rep.standing(pu,f)
  -- (as the hold screen does: out of the hold, then out of the ship)
  local Hold=require('src.inventory.hold')
  if pg.player.hold then Hold.take(pg.player.hold,'vip',1);pg.player.cargo=Hold.totals(pg.player.hold) else pg.player.cargo.vip=0 end
  pg:eject(pg.player,'vip',1)
  assert(NB.person(pu,here.id).status=='dead','airlock did not kill the VIP')
  assert(not Board.active(pg),'contract survived the airlock')
  assert((pg.player.cargo.vip or 0)==0)
  assert(Rep.standing(pu,f)<s0,'spacing them in their own space cost nothing')
  assert(WS.flag(pu,NB.flag(here.id))=='dead')
 end

 -- capture: a VIP put down at another faction's station
 do
  local en=NB.defs.estates_journalist
  local cg=Game.new({preview=true});cg.autosaveOff=true
  local cu=cg.universe;NB.state(cu)
  cg:spawnPlayer('amw_wayfarer')
  local o=P.postVIP(cu,en,en.seat,en.circuit[1],cu.clock)
  local station=Board.station
  Board.station=function() return en.seat end
  local ok,why=Board.accept(cg,o.id)
  assert(ok,'could not accept: '..tostring(why))
  Board.station=function() return 'station:mars_4' end
  local done,msg=Board.cancel(cg)
  Board.station=station
  assert(done,msg)
  assert(NB.person(cu,en.id).status=='captured','handing over did not capture: '..tostring(msg))
  assert(WS.flag(cu,NB.flag(en.id))=='captured')
 end

 -- 5. summits
 local sm=NB.state(u).summit
 sm.next=u.clock+D.summit.lead
 NB.update(u,u.clock)
 assert(sm.opens and #sm.attendees>=1 and #sm.attendees<=D.summit.small[2],'ordinary summit size')
 local going=0
 for _,id in ipairs(sm.attendees) do
  local p=NB.person(u,id)
  if p.trip and p.trip.to==D.summit.station then going=going+1 end
 end
 assert(going==#sm.attendees,'summit leaders did not post their runs')
 -- run it out: offers expire, they arrive off-board, then go home
 for id,o in pairs(Tasks.state(u).offers) do if o.notable then Tasks.state(u).offers[id]=nil end end
 NB.update(u,u.clock+1)
 for _,id in ipairs(sm.attendees) do assert(NB.person(u,id).at==D.summit.station,'leader never reached the summit') end
 local attendees,closes=sm.attendees,sm.closes
 NB.update(u,closes+1)
 for _,id in ipairs(attendees) do assert(NB.person(u,id).trip,'leader did not head home') end
 -- a grand summit: every living leader
 sm.n=D.summit.grandEvery-1;sm.next=closes+1+D.summit.lead
 for id,o in pairs(Tasks.state(u).offers) do if o.notable then Tasks.state(u).offers[id]=nil end end
 NB.update(u,sm.next-D.summit.lead+1)
 NB.update(u,sm.next-D.summit.lead+2)
 local alive=0
 for _,n in ipairs(D.cast) do if n.role=='leader' and NB.alive(u,n.id) then alive=alive+1 end end
 assert(sm.grand and #sm.attendees==alive,('grand summit should bring all %d living leaders, got %d'):format(alive,#(sm.attendees or {})))

 assert(#WS.report(u)>3)
 print(('ok  notables: %d cast valid, role consequences, save, VIP airlock and capture, summits'):format(#D.cast))
end
