return function(game)
 local Engine,Render=require('src.engine_visual'),require('src.render')
 local copy=require('src.persistence').copy
 local e=game.player
 e.hull=copy(e.hull);e.loadout={}
 e.hull.slots={
  {family='engine',size='S',x=-45,y=-25},
  {family='engine',size='S',x=-45,y=25},
  {family='engine',size='S',x=-10,y=0}
 }
 e.loadout={'flit_engine','flit_engine',false}
 e.mainBurn=1;e.sideBurn=0;e.retroBurn=0;e.foreBurn=0;e.turnBurn=0
 e.weapons={};e.dockState=nil;e.flash=0;e.afterburn=false
 e.body:setPosition(0,0);e.body:setAngle(0)
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local emitters=Engine.emitters(e)
 check(#emitters==2,'two engines did not produce two nozzles')
 check(emitters[1].x==-45 and emitters[1].y==-25 and emitters[2].y==25,'nozzles ignored slot coordinates')
 local function draw(player,burn,boost)
  e.isPlayer=player;e.mainBurn=burn;e.afterburn=boost
  local canvas=love.graphics.newCanvas(256,256)
  love.graphics.push('all')
  love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
  love.graphics.origin();love.graphics.translate(128,128)
  love.math.setRandomSeed(123)
  Render.ship(game,e)
  love.graphics.setCanvas();love.graphics.pop()
  return canvas:newImageData()
 end
 local player=draw(true,1,false)
 local npc=draw(false,1,false)
 local function orange(image,x,y)
  local r,g,b,a=image:getPixel(x+128,y+128)
  return a>.1 and r>g and g>b
 end
 check(orange(player,-55,-25) and orange(player,-55,25),'player exhaust missing at one of the engines')
 check(orange(npc,-55,-25) and orange(npc,-55,25),'NPC exhaust missing at one of the engines')
 for _,y in ipairs({-25,25}) do
  local r,g,b,a=player:getPixel(73,128+y)
  local rr,gg,bb,aa=npc:getPixel(73,128+y)
  check(r==rr and g==gg and b==bb and a==aa,'player and NPC exhaust differ')
 end
 e.loadout[2]=false
 local refit=draw(true,1,false)
 check(orange(refit,-55,-25) and not orange(refit,-55,25),'removed engine still emits exhaust')
 e.loadout[1]=false
 check(#Engine.emitters(e)==0,'empty engine slots emit exhaust')
 e.loadout[1]='flit_engine'
 local idle=draw(true,0,false)
 check(not orange(idle,-55,-25),'idle engine emits exhaust')
 local boost=draw(true,1,true)
 check(orange(boost,-85,-25) and not orange(player,-85,-25),'afterburner did not extend exhaust')
 e.hull.slots[1].x=nil;e.hull.slots[1].y=nil
 check(Engine.emitters(e)[1].x==e.tailX,'legacy slot has no tail fallback')
 e.hull.slots[1].x=0;e.hull.slots[1].y=12
 check(Engine.emitters(e)[1].x==0 and Engine.emitters(e)[1].y==12,'zero coordinate treated as missing')
 player:encode('png','twin-engine-player.png')
 npc:encode('png','twin-engine-npc.png')
 print(('ENGINE VISUAL TEST PASSED (%d checks)'):format(checks))
end
