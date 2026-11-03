-- Hull paint: factory presets, liveries, part paint marks, and repaints
-- surviving a ship record. With THRESHOLD_SHOTS set, saves a screenshot.
return function(game)
 local Paint=require('src.paint')
 local HullShape=require('src.hullshape')
 local Ship=require('src.ship')
 local data=require('src.data')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function same(a,b) return math.abs(a[1]-b[1])+math.abs(a[2]-b[2])+math.abs(a[3]-b[3])<1e-6 end
 check(#Paint.PRESETS>=15,'presets')
 local p=Paint.preset('Signal')
 check(same(p,{1,0.85,0.35}) and p.secondary[1]<p[1],'light preset shades darker')
 local d=Paint.preset('Plum'); check(d.secondary[1]>d[1],'dark preset shades lighter')
 local seen={}
 for _=1,60 do seen[Paint.resolve(nil,nil,{paints={'Signal','Plum'}}).name]=true end
 check(seen.Signal and seen.Plum,'hull pool picks among its paint jobs')
 check(Paint.preset('nope').name==Paint.DEFAULT,'unknown preset falls back')
 -- part marks
 check(same(HullShape.color({},p),Paint.METAL),'unmarked part is metal')
 check(same(HullShape.color({paint='primary'},p),p),'primary part')
 check(same(HullShape.color({paint='secondary'},p),p.secondary),'secondary part')
 check(same(HullShape.color({color={0,1,0},paint='primary'},p),{0,1,0}),'fixed colour wins')
 check(same(HullShape.color({},{0.2,0.3,0.4}),{0.2,0.3,0.4}),'plain colour (stations) paints every part')
 -- spawning
 local hullId=data.list.hulls[1]
 local s=Ship.new(game,{hull=hullId,team=1})
 check(Paint.isPaint(s.color) and s.color.name~=nil,'factory preset on spawn')
 local raider=data.enemies.brawler
 local r=Ship.new(game,{hull=raider.hull,enemy=raider})
 check(same(r.color,raider.livery.primary),'livery on spawn')
 local t=Ship.new(game,{hull=data.enemies.freighter.hull,enemy=data.enemies.freighter})
 check(t.color.name~=nil,'traders fly stock')
 local legacy=Ship.new(game,{hull=hullId,color={0.1,0.2,0.3}})
 check(Paint.isPaint(legacy.color),'old plain colours are dropped')
 local rp=Paint.make({0,0,1},{1,1,0})
 s.color=rp
 local rec=Ship.record(s)
 local back=Ship.new(game,{hull=hullId,color=rec.color})
 check(same(back.color,{0,0,1}) and same(back.color.secondary,{1,1,0}),'repaint survives a record')
 for _,e in ipairs({s,r,t,legacy,back}) do if e.body then e.body:destroy() end end
 local shots=os.getenv('THRESHOLD_SHOTS')
 if shots then
  local Editor=require('src.editor'); local E=Editor.state
  Editor.open(game); E.switchCategory('hull'); E.openHull('brute_anvil')
  E.design.stats.paints={'Hazard','Cobalt'}; E.showPaints=true
  for i,q in ipairs(E.design.parts) do q.paint=(i%3==0) and 'secondary' or (i%3==1) and 'primary' or nil end
  E.view.zoom=4; E.view.x,E.view.y=0,0
  local Slab=require('lib.Slab')
  for _=1,4 do Slab.Update(1/60); Editor.update(1/60); love.graphics.origin(); love.graphics.clear(0,0,0); Editor.draw(); Slab.Draw(); love.graphics.present() end
  Slab.Update(1/60); Editor.update(1/60)
  love.graphics.origin(); love.graphics.clear(0,0,0); Editor.draw(); Slab.Draw()
  love.graphics.captureScreenshot(function(img) local f=io.open(shots..'/paint.png','wb'); f:write(img:encode('png'):getString()); f:close() end)
  love.graphics.present()
 end
 print(('paint: %d checks passed'):format(checks))
end
