return function(game)
 local pirateBase=require('src.locations').station(nil,'pirateBase')
 local O,A,P=require('src.offline_loot'),require('src.alife'),require('src.piracy')
 local Hold,Fields,L=require('src.inventory.hold'),require('src.fields'),require('src.locations')
 local data,T,Save=require('src.data'),require('src.tuning'),require('src.save')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game:loadField('pluto');game:captureALife(true)
 local u=game.universe;local clock=u.clock
 u.alifeWrecks={};u.areas.earth={capturedAt=clock,objects={},pickups={}}
 local nextId=0
 local function pirate(area,hull)
  nextId=nextId+1
  local node=Fields[area].buoyIds[1] or Fields[area].stationIds[1]
  local h=hull or 'halcyon_wisp'
  local r={id='offline-loot/'..nextId,home=area,area=area,role='pirate',archetype='pirate_wisp',speed=600,
   route={node,node},node=node,index=1,state='idle',untilTime=clock+100,
   ship={hull=h,loadout=data.hulls[h].loadout,cargo={},armor=data.hulls[h].armor}}
  u.npcs[r.id]=r
  local x,y=L.position(node,clock)
  return r,x,y
 end
 local r,x,y=pirate('earth');local other=pirate('earth')
 local item={id=1001,item='scrap',count=8,x=x,y=y,vx=0,vy=0,spin=0}
 local area=u.areas.earth;area.pickups={item}
 check(O.update(game,r,clock) and r.offlineLoot,'pirate did not approach saved loose loot')
 check(item.count==8 and not r.ship.cargo.scrap,'approach transferred cargo instantly')
 check(not O.update(game,other,clock) and not other.offlineLoot,'two pirates claimed the same resource')
 clock=clock+2;u.clock=clock;O.update(game,r,clock)
 check(#area.pickups==0 and r.ship.cargo.scrap==8,'offline pickup transfer lost or duplicated cargo')
 check(r.piracy and r.route[#r.route]==pirateBase,'offline looter did not return to Milliways')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(#saved.areas.earth.pickups==0 and saved.npcs[r.id].ship.cargo.scrap==8,'save lost offline resource depletion')
 -- Intact saved containers preserve nested inventory and disappear only once.
 local big,bx,by=pirate('earth','ferrous_freighter')
 local inner=Hold.new({{key='box',w=8,h=4}});Hold.add(inner,'rounds_s',25)
 local box={id=1002,kind='container',item='cargo_container',x=bx,y=by,vx=0,vy=0,
  hold=Hold.serialize(inner),mass={0,0,20,200},hp=90,radius=30}
 area.objects={box}
 O.update(game,big,clock);clock=clock+2;u.clock=clock;O.update(game,big,clock)
 check(#area.objects==0,'looted saved container remained in the world snapshot')
 local h=Hold.deserialize(big.ship.hold);local stack=h.grids[1].stacks[1]
 check(stack.inner and stack.stolen and Hold.count(stack.inner,'rounds_s')==25,'offline container lost nested cargo or provenance')
 P.unload(u,big)
 local stored=u.piracy.containers[pirateBase]
 check(Hold.count(Hold.deserialize(stored[#stored].inner),'rounds_s')==25,'offline crate lost contents at stash')
 -- Prepared combat wreck inventories are authoritative when materialized later.
 area.objects={};area.pickups={}
 local looter,wx,wy=pirate('earth')
 local cargo=Hold.new({{key='wreck',w=12,h=10}});Hold.add(cargo,'scrap',6)
 local node=looter.node
 local w={id='offline-victim',area='earth',from=node,to=node,progress=0,clock=clock,expires=clock+1800,
  ship={hull='halcyon_wisp',loadout=data.hulls.halcyon_wisp.loadout,cargo={scrap=99},armor=0},
  archetype='gunner',lootHold=Hold.serialize(cargo),salvagedSlots={}}
 u.alifeWrecks[w.id]=w
 O.update(game,looter,clock)
 for _=1,6 do clock=clock+2;u.clock=clock;O.update(game,looter,clock);if looter.piracy then break end end
 check(looter.ship.cargo.scrap==6 and Hold.count(Hold.deserialize(w.lootHold),'scrap')==0,'combat wreck loot was not depleted exactly once')
 -- Simulate visiting that area: materialization must not roll fresh loot.
 local field=game.fieldId;game.fieldId='earth'
 require('src.encounters').materialize(game,wx,wy,clock)
 game.fieldId=field
 local wreck
 for _,e in ipairs(game.entities) do if e.alifeWreckId==w.id then wreck=e end end
 check(wreck and Hold.count(wreck.hold,'scrap')==0 and not u.alifeWrecks[w.id],'materializing a looted wreck regenerated cargo')
 -- Current and retained scenes own their physical resources; stale snapshots
 -- are never another source of loot for remote NPCs.
 local localPirate,lx,ly=pirate('pluto')
 u.areas.pluto={capturedAt=clock,objects={},pickups={{id=1003,item='scrap',count=7,x=lx,y=ly,vx=0,vy=0,spin=0}}}
 check(not O.update(game,localPirate,clock) and u.areas.pluto.pickups[1].count==7,'offline looting modified a loaded area snapshot')
 local retained,rx,ry=pirate('earth')
 area.pickups={{id=1004,item='scrap',count=7,x=rx,y=ry,vx=0,vy=0,spin=0}}
 game.arrivalPreview={game={fieldId='earth'}}
 check(not O.update(game,retained,clock) and area.pickups[1].count==7,'offline looting modified a retained preview scene')
 game.arrivalPreview=nil
 -- Full holds cannot consume a saved source; expired wrecks are not looted.
 local full,fx,fy=pirate('earth')
 local slots=Hold.new(require('src.ship').holdLayout({hull=data.hulls.halcyon_wisp,loadout=data.hulls.halcyon_wisp.loadout,stats=require('src.stats').compute(data.hulls.halcyon_wisp,data.hulls.halcyon_wisp.loadout)}))
 Hold.add(slots,'scrap',10000);full.ship.hold=Hold.serialize(slots);full.ship.cargo=Hold.totals(slots)
 area.pickups={{id=1005,item='scrap',count=7,x=fx,y=fy,vx=0,vy=0,spin=0}}
 check(not O.update(game,full,clock) and area.pickups[1].count==7,'full offline pirate consumed loot')
 area.pickups={};u.alifeWrecks.expired={id='expired',area='earth',from=node,to=node,progress=0,expires=clock-1,ship=w.ship,archetype='gunner'}
 local fresh=pirate('earth')
 check(not O.update(game,fresh,clock),'pirate looted an expired wreck')
 -- An offline approach has a position; waking cancels its exclusive claim
 -- while preserving that position rather than jumping back to the graph.
 u.alifeWrecks={}
 local approaching,ax,ay=pirate('earth')
 area.pickups={{id=1006,item='scrap',count=4,x=ax+1200,y=ay,vx=0,vy=0,spin=0}}
 O.update(game,approaching,clock)
 local pending=assert(Save.decode(Save.encode(game:saveState())))
 check(pending.npcs[approaching.id].offlineLoot.id==1006 and pending.areas.earth.pickups[1].lootOwner==approaching.id,'save lost pending loot reservation')
 local resumed={universe=pending,fieldId='pluto',alifeOnline={}}
 pending.clock=clock+3
 O.update(resumed,pending.npcs[approaching.id],pending.clock)
 check(#pending.areas.earth.pickups==0 and pending.npcs[approaching.id].ship.cargo.scrap==4,'restored reservation failed to transfer exactly once')
 local px,py=A.point(approaching,clock+1)
 check(px>ax and px<ax+1200,'offline loot approach had no intermediate position')
 O.release(game,approaching,clock+1)
 local hx,hy=A.point(approaching,clock+1)
 check(math.abs(hx-px)<.01 and math.abs(hy-py)<.01 and not approaching.offlineLoot,'live handoff moved pirate or retained its loot claim')
 check(not area.pickups[1].lootOwner,'live handoff did not release saved resource')
 -- Reload the saved depleted world to verify revisit/save restoration.
 game:loadState(saved)
 check(#game.universe.areas.earth.pickups==0,'load regenerated consumed loose items')
 print(('OFFLINE LOOT TEST PASSED (%d checks)'):format(checks))
end
