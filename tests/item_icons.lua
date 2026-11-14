-- Item icons: the Shipyard's Icons tab (new icon, open, export source that
-- loads back), and the art drawn in space and in a hold stack.
-- With THRESHOLD_SHOTS set, saves screenshots there.
return function(game)
 local data=require('src.data')
 local Icons=require('src.icons')
 local Editor=require('src.editor')
 local Export=require('src.editor.export')
 local Visual=require('src.weapon_visual')
 local E=Editor.state
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 check(data.icons.missile_m and data.icons.missile_m.id=='icon_missile_m','base icon loaded')
 local w,h=Icons.footprint('missile_m')
 check(w==3 and h==1,'missile footprint')
 local bw,bh=Icons.box('missile_m')
 check(bw==24 and bh==8,'box is cells x CELL')
 check(Icons.worldReach('missile_m')>4 and Icons.worldReach('patch_kit')==nil,'reach')
 -- drones are drawn as their own hull, until someone saves art for them
 local dr=Icons.get('drone_m')
 check(dr and dr.hull==data.items.drone_m.shot.hull and #dr.parts>0,'drone uses its hull')
 local dbw,dbh=Icons.box('drone_m')
 for _,q in ipairs(dr.parts) do for k=1,#q.shape-1,2 do check(math.abs(q.shape[k])<=dbw and math.abs(q.shape[k+1])<=dbh,'drone art fits its footprint') end end
 -- the editor's Icons tab (from a clean start, not the last autosave)
 Editor.open(game)
 E.byCategory={}; E.newDesign('hull')
 E.switchCategory('icon')
 check(E.design.kind=='icon' and E.design.item and not Icons.get(E.design.item),'new icon goes to an item without art (drones have theirs)')
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
 -- the item's grid size, edited with the icon
 E.design.w,E.design.h=2,1
 check(Export.source(E.design):find('w = 2, h = 1',1,true),'size in source')
 check(E.define() and Icons.footprint(item)==2,'saving the icon resizes the item')
 check(Icons.box(item)==16,'art box follows the new size')
 -- reopen through the open-by-id path the file browser uses
 E.openHull('icon_missile_m')
 check(E.design.kind=='icon' and E.design.item=='missile_m' and #E.design.parts>3,'opened a saved icon')
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
 -- every item with art, as hold stacks (34 px cells) and at world size
 local CS=tonumber(os.getenv('THRESHOLD_ICON_CELL') or 34)
 shot('icon-sheet',function()
  local x,y=10,10
  local HUD=require('src.hud')
  for _,id in ipairs(data.list.items) do
   if Icons.get(id) then
    local fw,fh=Icons.footprint(id)
    if x+fw*CS+120>lg.getWidth() then x,y=10,y+CS*1.4+70 end
    local c=HUD.itemColor(data.items[id])
    lg.setColor(c[1],c[2],c[3],0.32); lg.rectangle('fill',x,y+14,fw*CS,fh*CS,3,3)
    Icons.drawInRect(id,x,y+14,fw*CS,fh*CS,false,1)
    Icons.drawWorld(id,x+fw*CS/2,y+14+fh*CS+30,0,1,1)
    lg.setColor(1,1,1,0.7); lg.print(id,x,y)
    x=x+math.max(fw*CS,90)+14
   end
  end
 end)
 -- the hold, with a few drawn items in it
 local Hold=require('src.inventory.hold')
 if p.hold then
  for _,id in ipairs({'missile_m','rounds_s','torp_l','hydrogen_canister','drone_m'}) do Hold.add(p.hold,id,2) end
  local Cargo=require('src.ui.cargo')
  Cargo.toggle(game)
  shot('icons-in-hold',function() require('src.render').world(game); Cargo.draw(game) end)
  Cargo.close(game)
 end
 Editor.open(game)
 E.openHull('icon_missile_m')
 E.boxSel=1
 local Slab=require('lib.Slab')
 for _=1,4 do Slab.Update(1/60); Editor.update(1/60); lg.origin(); lg.clear(0,0,0); Editor.draw(); Slab.Draw(); lg.present() end
 shot('icon-editor',function() Slab.Update(1/60); Editor.update(1/60); Editor.draw(); Slab.Draw() end)
 Editor.close()
 -- boxes: 3/4 view blocks become front/side/top faces that fill the footprint
 local mi=data.icons.missile_m
 check(mi.boxes and #mi.parts==#mi.boxes*3,'each box gives three faces')
 local mbw,mbh=Icons.box('missile_m')
 for _,q in ipairs(mi.parts) do for k=1,#q.shape-1,2 do check(math.abs(q.shape[k])<=mbw+1e-6 and math.abs(q.shape[k+1])<=mbh+1e-6,'box art fits the footprint') end end
 check(#data.icons.rounds_s.parts==#data.icons.rounds_s.boxes*3-1,'open box has no top')
 E.openHull('icon_missile_m')
 local n=#E.design.parts
 local bsrc=Export.source(E.design)
 check(bsrc:find('boxes = {',1,true) and not bsrc:find('crate front',1,true),'source keeps boxes, not their faces')
 local bgot; local bc=assert(loadstring(bsrc)); setfenv(bc,{icon=function(d) bgot=d end}); bc()
 check(#bgot.boxes==#mi.boxes and #bgot.parts==0,'box source round trip')
 E.design.boxes[1].h=2; Icons.syncBoxes(E.design)
 check(#E.design.parts==n,'resync replaces faces, never piles them up')
 -- clicking a face picks its box; Delete hides that face
 local Canvas=require('src.editor.canvas')
 local f1=E.design.parts[1]
 E.boxSel,E.faceSel=f1.box,f1.face
 E.deleteSelected(); Icons.syncBoxes(E.design)
 check(#E.design.parts==n-1 and E.design.boxes[f1.box].hide[f1.face],'deleting a face hides it')
 check(Export.source(E.design):find('hide = {',1,true),'hidden face saved')
 -- deleting a box (Delete with no face picked) removes it and leaves the rest where they were
 local nb=#E.design.boxes
 local last=E.design.parts[#E.design.parts]
 local lx,ly=last.shape[1],last.shape[2]
 E.boxSel,E.faceSel=1,nil
 E.deleteSelected()
 check(#E.design.boxes==nb-1 and E.boxSel==nil,'Delete removes the box from the list')
 local last2=E.design.parts[#E.design.parts]
 check(math.abs(last2.shape[1]-lx)<1e-6 and math.abs(last2.shape[2]-ly)<1e-6,'other boxes keep their place and scale')
 check(Export.source(E.design):find('boxView = {',1,true),'scale saved with the icon')
 -- box colours: dark and light shades differ from the kind colour on the canvas and in game
 local HullShape=require('src.hullshape')
 local kc=E.previewPaint()
 E.design.boxes[1].shade=0.6; Icons.syncBoxes(E.design)
 local dk=HullShape.color(E.design.parts[1],kc)
 local gk=Visual.partColor(E.design.parts[1],kc)
 check(dk[1]<kc[1]-0.05 and math.abs(dk[1]-gk[1])<1e-6,'dark shade shows on canvas and in game')
 E.design.boxes[1].shade=nil; E.design.boxes[1].light=0.45; Icons.syncBoxes(E.design)
 local lt=HullShape.color(E.design.parts[1],kc)
 local function hue(c) local mx,mn=math.max(c[1],c[2],c[3]),math.min(c[1],c[2],c[3]); return {(c[1]-mn)/(mx-mn+1e-9),(c[2]-mn)/(mx-mn+1e-9),(c[3]-mn)/(mx-mn+1e-9)} end
 local h1,h2=hue(kc),hue(lt)
 check(lt[1]+lt[2]+lt[3]>kc[1]+kc[2]+kc[3]+0.1 and math.abs(h1[1]-h2[1])+math.abs(h1[2]-h2[2])+math.abs(h1[3]-h2[3])<0.05,'light keeps the hue')
 Editor.close()
 print(('item icons: %d checks passed'):format(checks))
end
