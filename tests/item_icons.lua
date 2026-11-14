-- Item icons: the Shipyard's Icons tab (new icon, open, export source that
-- loads back), and the art drawn in space and in a hold stack.
-- With THRESHOLD_SHOTS set, saves screenshots there.
return function(game)
 local data=require('src.data')
 local Icons=require('src.icons')
 local Editor=require('src.editor')
 local Export=require('src.editor.export')
 local E=Editor.state
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 check(data.icons.missile_m and data.icons.missile_m.id=='icon_missile_m','base icon loaded')
 local w,h=Icons.footprint('missile_m')
 check(w==3 and h==1,'missile footprint')
 local bw,bh=Icons.box('missile_m')
 check(bw==24 and bh==8,'box is cells x CELL')
 check(Icons.worldReach('missile_m')>20 and Icons.worldReach('rounds_s')==nil,'reach')
 -- drones are drawn as their own hull, until someone saves art for them
 local dr=Icons.get('drone_m')
 check(dr and dr.hull==data.items.drone_m.shot.hull and #dr.parts>0,'drone uses its hull')
 local dbw,dbh=Icons.box('drone_m')
 for _,q in ipairs(dr.parts) do for k=1,#q.shape-1,2 do check(math.abs(q.shape[k])<=dbw and math.abs(q.shape[k+1])<=dbh,'drone art fits its footprint') end end
 -- the editor's Icons tab (from a clean start, not the last autosave)
 Editor.open(game)
 E.byCategory={}; E.newDesign('hull')
 E.switchCategory('icon')
 check(E.design.kind=='icon' and E.design.item and not data.icons[E.design.item],'new icon goes to an item without one')
 local item=E.design.item
 check(item~='silicon' and item~='patch_kit','test items stay free')
 E.design.parts[1].paint='primary'
 table.insert(E.design.parts,{name='fin',shape={-4,-4,0,-4,-2,-7},mirror=true})
 local src=Export.source(E.design)
 check(src:match('^%-%- Made in the Shipyard') and src:find('icon {',1,true),'icon source')
 local chunk=assert(loadstring(src))
 local got
 setfenv(chunk,{icon=function(d) got=d end}); chunk()
 check(got and got.item==item and #got.parts==2 and got.parts[2].mirror==true,'source round trip')
 check(E.define(),'define registers it')
 check(data.icons[item] and #data.icons[item].parts==2,'registered')
 -- reopen through the open-by-id path the file browser uses
 E.openHull('icon_missile_m')
 check(E.design.kind=='icon' and E.design.item=='missile_m' and #E.design.parts==5,'opened a saved icon')
 E.openIcon('silicon')
 check(E.design.item=='silicon' and #E.design.parts==1,'item without an icon starts a new one: '..tostring(item)..' '..#E.design.parts)
 -- drawing, for real
 local lg=love.graphics
 local cv=lg.newCanvas(400,200)
 lg.setCanvas(cv)
 check(Icons.drawWorld('missile_m',100,100,0.3),'world draw')
 check(Icons.drawInRect('missile_m',200,20,66,22,false,1),'hold draw')
 check(Icons.drawInRect('missile_m',300,20,22,66,true,0.5),'rotated hold draw')
 check(Icons.drawInRect('patch_kit',0,0,22,22)==false,'no icon: falls back')
 lg.setCanvas()
 -- a frame of the game with pickups out, and of the editor
 game.pickups={}
 local p=game.player
 local x,y=p.body:getPosition()
 for i,id in ipairs({'missile_m','shell_s','hydrogen_canister','drone_s','patch_kit',item}) do
  local k=game:pickupView(x+60+i*40,y,id,1); k.spin=i
 end
 local shots=os.getenv('THRESHOLD_SHOTS')
 local function shot(name,draw)
  lg.origin(); lg.clear(0,0,0); draw(); lg.present()
  if not shots then return end
  lg.captureScreenshot(function(img) local f=io.open(shots..'/'..name..'.png','wb'); f:write(img:encode('png'):getString()); f:close() end)
  lg.present()
 end
 Editor.close()
 game.camera.zoom=4; game.camera.x,game.camera.y=x+140,y
 shot('icons-in-space',function() require('src.render').world(game) end)
 -- the hold, with a few drawn items in it
 local Hold=require('src.inventory.hold')
 if p.hold then
  for _,id in ipairs({'missile_m','shell_s','hydrogen_canister','drone_m'}) do Hold.add(p.hold,id,2) end
  local Cargo=require('src.ui.cargo')
  Cargo.toggle(game)
  shot('icons-in-hold',function() require('src.render').world(game); Cargo.draw(game) end)
  Cargo.close(game)
 end
 Editor.open(game)
 E.openHull('icon_missile_m')
 local Slab=require('lib.Slab')
 for _=1,4 do Slab.Update(1/60); Editor.update(1/60); lg.origin(); lg.clear(0,0,0); Editor.draw(); Slab.Draw(); lg.present() end
 shot('icon-editor',function() Slab.Update(1/60); Editor.update(1/60); Editor.draw(); Slab.Draw() end)
 Editor.close()
 print(('item icons: %d checks passed'):format(checks))
end
