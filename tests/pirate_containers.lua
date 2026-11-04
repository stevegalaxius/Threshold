return function(game)
 local Ship,Hold,Grid=require('src.ship'),require('src.inventory.hold'),require('src.inventory.grid')
 local Loot,P,T=require('src.loot'),require('src.piracy'),require('src.tuning')
 local Save,data=require('src.save'),require('src.data')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function inner(w,h) return Hold.new({{key='main',name='Contents',w=w or 8,h=h or 4}}) end
 local function pirate(hull)
  local e=Ship.new(game,{hull=hull,grid=true,cargo={},enemy=data.enemies.pirate_wisp,x=10000,y=10000})
  local r={role='pirate',stolenCargo={}}
  e.alifeRole='pirate';e.alifeRecord=r;e.alifeGame=game
  return e,r
 end
 -- A large hull takes a loaded container intact, including a nested container.
 local big,r=pirate('ferrous_freighter')
 local contents=inner(16,8);local nested=inner();Hold.add(nested,'scrap',4)
 check(Hold.placeStack(contents,{id='cargo_container',n=1,inner=nested}),'nested test crate did not fit')
 Hold.add(contents,'rounds_s',12)
 local box=game:spawnContainer(10000,10000,'cargo_container',false,contents)
 check(Loot.canTake(big,box),'large pirate refused loaded crate')
 local beforeMass=big.body:getMass()
 check(Loot.transfer(game,big,box)==1 and box.removed,'intact crate did not leave the world')
 local stack=big.hold.grids[1].stacks[1]
 check(stack and stack.inner==contents and stack.stolen,'crate contents or provenance lost at pickup')
 check(Hold.count(stack.inner,'cargo_container')==1 and Hold.count(nested,'scrap')==4,'nested contents flattened at pickup')
 check(big.body:getMass()>beforeMass+4,'nested cargo mass was not included')
 check(Loot.transfer(game,big,box)==0,'removed crate could be looted twice')
 -- Serialization restores the complete stack and its stolen marker.
 local encoded=assert(Save.decode(Save.encode(Hold.serialize(big.hold))))
 local restored=Hold.deserialize(encoded)
 check(restored.grids[1].stacks[1].stolen,'save lost stolen container marker')
 r.ship={cargo=Hold.totals(restored),hold=Hold.serialize(restored)}
 local u={};P.unload(u,r)
 local savedBox=u.piracy.containers[T.pirateBase][1]
 local stored=Hold.deserialize(savedBox.inner)
 check(Hold.count(stored,'rounds_s')==12 and Hold.count(stored,'cargo_container')==1,'stash lost intact crate contents')
 local sub
 for _,g in ipairs(stored.grids) do for _,s in ipairs(g.stacks) do if s.inner then sub=s.inner end end end
 check(sub and Hold.count(sub,'scrap')==4,'stash lost nested crate cargo')
 local persisted=assert(Save.decode(Save.encode(u)))
 local restoredStash=Hold.deserialize(persisted.piracy.containers[T.pirateBase][1].inner)
 check(Hold.count(restoredStash,'rounds_s')==12,'save lost stashed container contents')

 check(Hold.count(Hold.deserialize(r.ship.hold),'cargo_container')==0,'unloaded crate still aboard pirate')
 P.unload(u,r)
 check(#u.piracy.containers[T.pirateBase]==1 and u.piracy.stashes[T.pirateBase].cargo_container==1,'repeated unload duplicated crate')
 -- A Wisp cannot carry the shell; it takes only contents that fit.
 local small,sr=pirate('halcyon_wisp')
 local hold=inner(16,16);Hold.add(hold,'scrap',200)
 local smallBox=game:spawnContainer(10100,10000,'cargo_container',false,hold)
 local count=Hold.count(hold,'scrap')
 check(Loot.canTake(small,smallBox),'small pirate refused accessible crate contents')
 local moved=0
 for _=1,200 do local n=Loot.transfer(game,small,smallBox);moved=moved+n;if n==0 then break end end
 check(moved>0 and moved<count and not smallBox.removed,'small hull did not perform partial transfer')
 check(Hold.count(hold,'scrap')+(small.cargo.scrap or 0)==count,'partial transfer lost or duplicated contents')
 local remaining=Hold.count(hold,'scrap')
 check(Loot.transfer(game,small,smallBox)==0 and Hold.count(hold,'scrap')==remaining,'full pirate consumed more cargo')
 check(sr.stolenCargo.scrap==moved and not sr.stolenCargo.cargo_container,'partial loot counted the container shell')
 -- A nested crate too big to stow is unpacked without deleting either shell.
 local other,orole=pirate('halcyon_wisp')
 local outer=inner(16,8);local child=inner();Hold.add(child,'scrap',3)
 Hold.placeStack(outer,{id='cargo_container',n=1,inner=child})
 local outerBox=game:spawnContainer(10200,10000,'cargo_container',false,outer)
 check(Loot.transfer(game,other,outerBox)+Loot.transfer(game,other,outerBox)==3,'small pirate failed to unpack nested contents')
 check(not outerBox.removed and Hold.count(outer,'cargo_container')==1 and Hold.count(child,'scrap')==0,'nested partial loot removed a shell')
 -- Unique worn items retain their exact state through extraction/unload.
 local damaged=inner();Hold.placeStack(damaged,{id='salvage_kit',n=1,wear=.37})
 local damagedBox=game:spawnContainer(10300,10000,'cargo_container',false,damaged)
 check(Loot.transfer(game,other,damagedBox)==1,'worn item extraction failed')
 local worn
 for _,g in ipairs(other.hold.grids) do for _,s in ipairs(g.stacks) do if s.id=='salvage_kit' then worn=s end end end
 check(worn and worn.wear==.37 and worn.stolen,'extraction lost item wear or provenance')
 local wornRecord={ship={hold=Hold.serialize(other.hold)},stolenCargo={salvage_kit=1}}
 local wornStash={};P.unload(wornStash,wornRecord)
 check(wornStash.piracy.stacks[T.pirateBase][1].wear==.37,'stash lost unique item state')
 game:remove(damagedBox)
 -- The actual pirate controller selects a physical loaded container and
 -- extracts its contents through the same transfer path.
 local live=orole;live.id='container-ai-test';live.role='pirate'
 other.alifeId=live.id;game.universe.npcs[live.id]=live
 local liveContents=inner();Hold.add(liveContents,'scrap',6)
 local liveBox=game:spawnContainer(10000,10000,'cargo_container',false,liveContents)
 local prior=other.cargo.scrap or 0
 check(P.think(game,other,1/60,require('src.ai')) and other.pirateContainer==liveBox,'pirate AI did not select a loaded physical container')
 check((other.cargo.scrap or 0)>prior and Hold.count(liveContents,'scrap')+(other.cargo.scrap or 0)-prior==6,'pirate AI container transfer did not conserve cargo')
 game.universe.npcs[live.id]=nil;game:remove(liveBox)
 for _,e in ipairs({big,small,other}) do e.body:destroy() end
 for _,b in ipairs({smallBox,outerBox}) do game:remove(b) end
 print(('PIRATE CONTAINER TEST PASSED (%d checks)'):format(checks))
end
