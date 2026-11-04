-- Controlled outcomes only: no long-running emergent scenarios.
return function(game)
 local H,E,A=require('src.simulation_history'),require('src.encounters'),require('src.alife')
 local copy,Save,T=require('src.persistence').copy,require('src.save'),require('src.tuning')
 local Events=require('src.events')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function count(u,kind)
  local n=0;for _,e in ipairs(H.state(u).entries) do if e.kind==kind then n=n+1 end end;return n
 end
 local pirate,trader
 for _,r in pairs(game.universe.npcs) do
  if r.area=='earth' and r.role=='pirate' then pirate=copy(r)
  elseif r.area=='earth' and r.role=='trader' then trader=copy(r) end
 end
 assert(pirate and trader,'missing combat fixture archetypes')
 pirate.id,trader.id='npc/90001','npc/90002'
 for _,r in ipairs({pirate,trader}) do
  r.state='travel';r.encounter=nil;r.retreatUntil=nil;r.pose=nil
  r.depart,r.arrive=0,1000;r.deathOutcomeId=nil;r.historyWreckId=nil
  local F=require('src.fields')
  r.route={F.earth.buoyIds[1],F.earth.stationIds[1]};r.index=2;r.driverState=nil;r.offset=nil
 end
 local u={npcs={[pirate.id]=pirate,[trader.id]=trader},clock=10}
 -- Begin is idempotent across both orderings; notifications cannot mutate history.
 local notified=0
 local listener=Events.on('simulation_outcome',function(e) notified=notified+1;e.kind='changed' end)
 local fight=H.begin(u,pirate.id,trader.id,10,'earth')
 check(H.begin(u,trader.id,pirate.id,11,'earth').id==fight.id,'pair ordering duplicated fight')
 check(count(u,'combat_started')==1 and notified==1,'start notification or history duplicated')
 Events.off('simulation_outcome',listener)
 -- Save/load active fights; mixed bodies never receive offline damage.
 E.begin(pirate,trader,10)
 local restored=assert(Save.decode(Save.encode(u)))
 local rp,rt=restored.npcs[pirate.id],restored.npcs[trader.id]
 check(H.begin(restored,rp.id,rt.id,12,'earth').id==fight.id,'save lost encounter identity')
 local armor=rt.ship.armor
 E.update({universe=restored,alifeOnline={[rp.id]={}}},14)
 check(rt.ship.armor==armor,'history integration allowed mixed abstract damage')
 -- A lethal abstract round records death + salvage before a single final summary.
 rp.ship.armor=10000;rp.ship.cargo.rounds_s=1000
 rt.ship.armor=.001;rt.ship.cargo={};rt.ship.hold=nil
 restored.encounterNext=14
 E.update({universe=restored,alifeOnline={}},14)
 check(rt.state=='dead','fixture did not die')
 check(count(restored,'npc_died')==1 and count(restored,'wreck_created')==1,'offline death or salvage not recorded')
 check(count(restored,'combat_ended')==1,'offline fight did not close once')
 local summary=rt.fight_log
 check(summary.fightId==fight.id and summary.result.dead[1]==rt.id,'offline summary lost participant or fight')
 check(summary.result.wrecks[1]==restored.alifeWrecks[rt.id].historyWreckId,'salvage reference disagrees')
 local n=#H.state(restored).entries
 E.update({universe=restored,alifeOnline={}},18)
 H.death(restored,rt,18,'earth');H.wreck(restored,rt,18,'earth')
 check(#H.state(restored).entries==n,'dead record generated duplicate outcomes')
 -- Actual online takeover retains the same history fight while releasing graph AI.
 game:captureALife(true)
 game.universe.npcs=u.npcs;game.universe.simulationHistory=u.simulationHistory
 game.universe.clock=12
 local x,y=A.point(pirate,12);game.player.body:setPosition(x+1000,y)
 local pe=A.wake(game,pirate)
 E.syncOnline(game)
 local te=game.alifeOnline[trader.id]
 check(te and te.aggressor==pe and not pirate.encounter,'online takeover fixture failed')
 check(count(game.universe,'combat_ended')==0,'handoff was reported as fight ending')
 check(H.begin(game.universe,pe.alifeId,te.alifeId,12,'earth').id==fight.id,'handoff assigned a new fight')
 -- Saving and unloading bodies is observational, not combat completion.
 local state=game:saveState()
 check(state.simulationHistory.fights[pirate.id..'|'..trader.id].id==fight.id,'game save omitted active history')
 game:captureALife(true)
 check(count(game.universe,'combat_ended')==0,'body unload ended fight')
 game:loadState(assert(Save.decode(Save.encode(state))))
 check(H.begin(game.universe,pirate.id,trader.id,12,'earth').id==fight.id,'game load lost history')
 -- Real damage/reaping supplies the same death and wreck facts as abstract combat.
 local r=game.universe.npcs[trader.id]
 te=game.alifeOnline[trader.id] or A.wake(game,r)
 pe=game.alifeOnline[pirate.id] or A.wake(game,game.universe.npcs[pirate.id])
 assert(te and pe,'could not wake physical fixture')
 te.dockState=nil;te.invulnerable=nil;te.driverProtected=nil
 game:damage(te,1e9,pe,'gun');game:reap()
 H.update(game)
 check(count(game.universe,'npc_died')==1 and count(game.universe,'wreck_created')==1,'physical death facts missing')
 check(count(game.universe,'combat_ended')==1,'physical fight did not finish once')
 check(r.fight_log.fightId==fight.id and r.fight_log.result.dead[1]==r.id,'physical summary differs')
 local wreck
 for _,e in ipairs(game.entities) do if e.historyWreckId==r.historyWreckId then wreck=e end end
 check(wreck and r.fight_log.result.wrecks[1]==wreck.historyWreckId,'physical wreck lacks stable reference')
 local saved=game:saveState();local ref=r.historyWreckId
 game:loadState(assert(Save.decode(Save.encode(saved))))
 local found=false
 for _,e in ipairs(game.entities) do if e.historyWreckId==ref then found=true end end
 check(found,'wreck identity did not survive area persistence')
 check(count(game.universe,'npc_died')==1 and count(game.universe,'combat_ended')==1,'reload duplicated outcomes')
 -- Retreat, quiet disengagement and bounded retention do not require a world run.
 local v={clock=1,npcs={a={id='a',state='travel'},b={id='b',state='travel'}}}
 local ea,eb={alifeId='a',fleeing=true},{alifeId='b'}
 H.begin(v,'a','b',1,'earth')
 H.update({universe=v,alifeOnline={a=ea,b=eb}})
 check(count(v,'combat_ended')==0,'fleeing ended a fight while shots could still land')
 H.hit({universe=v,fieldId='earth'},ea,eb)
 check(count(v,'combat_started')==1,'continued fire split a fleeing engagement')
 v.clock=1+T.historyQuietTime
 H.update({universe=v,alifeOnline={a=ea,b=eb}})
 check(v.npcs.a.fight_log.result.fled[1]=='a','physical retreat missing')
 H.begin(v,'a','b',2,'earth');v.clock=2+T.historyQuietTime
 H.update({universe=v,alifeOnline={}})
 check(v.npcs.a.fight_log.result.reason=='disengaged','quiet fight did not close')
 for i=1,T.historyLimit do H.begin(v,'a','b',i,'earth');H.finish(v,'a','b',i,'disengaged') end
 check(#H.state(v).entries==T.historyLimit and next(H.state(v).fights)==nil,'history retention is unbounded')
 check(v.npcs.a.fight_log.id==H.state(v).entries[#H.state(v).entries].id,'latest summary lost after eviction')
 H.begin(v,'a','player',v.clock,'earth')
 H.update({universe=v,alifeOnline={},player={isPlayer=true,dead=true}})
 check(v.npcs.a.fight_log.result.dead[1]=='player','player death did not close NPC engagement')
 local old={npcs={}};check(#H.state(old).entries==0,'legacy save did not initialize empty history')
 print(('simulation history: %d checks passed'):format(checks))
end
