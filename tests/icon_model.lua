-- Part of the fast content check: geometry, export and actual GPU depth.
return function(game)
 local M,Icons=require('src.icon_model'),require('src.icons')
 local Export=require('src.editor.export')
 local listed={};for _,id in ipairs(require('src.editor.panels').iconItems()) do listed[id]=true end
 assert(listed.ember_reactor and listed.flit_engine and listed.steel_plate,'icon picker omits generated module items')
 for _,shape in ipairs(M.shapes) do
  local parts=M.parts({{primitive=shape,material='metal',w=1,d=1,h=1}},16,16)
  assert(#parts>0,'empty primitive '..shape)
 end
 local boxes={{name='rear',primitive='box',material='painted',color={.8,.2,.1},w=1,d=1,h=1},
  {name='front',primitive='cylinder',material='metal',x=.3,y=-.2,z=.1,w=.7,d=.7,h=.7}}
 if game then
  local Cargo,Hold=require('src.ui.cargo'),require('src.inventory.hold')
  local oldHold,oldState,oldOpen,oldTab=game.player.hold,game.state,Cargo.open,Cargo.tab
  game.player.hold=Hold.new({{key='wide-test',w=30,h=20}});game.state='playing';Cargo.open=true;Cargo.tab='cargo';Cargo.panX=0
  local first=Cargo.layout(game);assert(first.cs==64 and first.overflowX>0,'wide inventory shrinks instead of panning')
  Cargo.wheelmoved(game,0,-3);local second=Cargo.layout(game)
  assert(second.cs==64 and second.grids[1].x<first.grids[1].x,'horizontal inventory pan does not move hit targets')
  game.player.hold=oldHold;game.state=oldState;Cargo.open=oldOpen;Cargo.tab=oldTab;Cargo.panX=0;Cargo.panY=0
 end
 local lg=love.graphics
 local function render(list)
  local parts=M.parts(list,16,16);local c=lg.newCanvas(128,128)
  local old=lg.getCanvas();lg.push('all');lg.setCanvas(c);lg.clear();lg.origin();lg.translate(64,64);lg.scale(3)
  M.draw(parts,1);lg.setCanvas(old);lg.pop()
  local pixels=c:newImageData();c:release();return pixels
 end
 local a=render(boxes);local b=render({boxes[2],boxes[1]})
 assert(a:getString()==b:getString(),'solid overlap depends on list order')
 local visible=false;for y=0,127 do for x=0,127 do local _,_,_,alpha=a:getPixel(x,y);if alpha>0 then visible=true;break end end end
 assert(visible,'model renderer produced no pixels')
 local design={id='icon_test',item='steel_plate',kind='icon',w=1,h=1,boxes=boxes,parts={}}
 Icons.syncBoxes(design)
 local source=Export.source(design);local decoded
 local chunk=assert(loadstring(source));setfenv(chunk,{icon=function(d) decoded=d end});chunk()
 assert(decoded.boxes[2].primitive=='cylinder' and decoded.boxes[2].material=='metal','export flattened shape parameters')
 assert(not decoded.parts or #decoded.parts==0,'export saved generated faces')
 Icons.syncBoxes(decoded);assert(#decoded.parts==#design.parts,'reopen changed geometry')
 if os.getenv('ICON_MODEL_PREVIEW') then
  local canvas=lg.newCanvas(1320,1050);local old=lg.getCanvas();lg.push('all');lg.setCanvas(canvas);lg.origin();lg.clear(.025,.035,.045)
  lg.setColor(.85,.94,1);lg.setFont(lg.newFont(24));lg.print('PARAMETRIC ICONS / ACTUAL GAME RENDERER',24,22)
  for i,id in ipairs({'steel_plate','iron_ore','deuterium_canister','gun_s_base','flit_engine','ember_reactor'}) do
   local x=24+(i-1)%3*432;local y=82+math.floor((i-1)/3)*450
   lg.setColor(.055,.075,.09);lg.rectangle('fill',x,y,412,430,6)
   lg.setColor(.85,.94,1);lg.setFont(lg.newFont(16));lg.print(id,x+14,y+14)
   Icons.drawInRect(id,x+76,y+55,250,160)
   local fw,fh=Icons.footprint(id);local cell=64
   for row=0,fh-1 do for col=0,fw-1 do lg.setColor(.15,.23,.28);lg.rectangle('line',x+14+col*cell,y+230+row*cell,cell,cell) end end
   Icons.drawInRect(id,x+14,y+230,fw*cell,fh*cell)
  end
  lg.setCanvas(old);lg.pop();local f=assert(io.open(os.getenv('ICON_MODEL_PREVIEW'),'wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
 end
 local Editor=require('src.editor');local E=Editor.state;local Canvas=require('src.editor.canvas')
 Editor.open(game);E.newIcon('steel_plate');E.newSolid='cylinder'
 Editor.keypressed('n');assert(#E.design.boxes==1 and E.design.boxes[1].primitive=='cylinder','N did not create an editable solid')
 local px,py
 for _,f in ipairs(E.design.parts) do
  local x,y=0,0;for k=1,#f.shape,2 do x=x+f.shape[k];y=y+f.shape[k+1] end
  x,y=x/(#f.shape/2),y/(#f.shape/2)
  if M.pick(E.design.parts,x,y) then px,py=Canvas.toScreen(E,x,y);break end
 end
 assert(px,'no visible solid to select')
 Canvas.mousepressed(E,px,py,1);assert(E.drag and E.drag.kind=='solid','click entered a polygon tool')
 local before=E.design.boxes[1].x or 0
 Canvas.mousemoved(E,px+32,py-16);Canvas.mousereleased(E,px+32,py-16,1)
 assert((E.design.boxes[1].x or 0)>before,'drag did not move solid parameters')
 local moved=E.design.boxes[1].x
 E.undoStep();assert((E.design.boxes[1].x or 0)==before,'solid drag undo failed')
 E.redoStep();assert(E.design.boxes[1].x==moved,'solid drag redo failed')
 local src=Export.source(E.design);local saved;local fn=assert(loadstring(src));setfenv(fn,{icon=function(v)saved=v end});fn()
 assert(saved.boxes[1].x==tonumber(('%.3f'):format(moved)),'save lost the moved solid')
 Export.autosave(E.design);local autosaved=assert(Export.loadAutosave())
 assert(math.abs(autosaved.boxes[1].x-moved)<.00051 and #autosaved.parts>0,'autosave lost editable solids')
 E.duplicateSelected();assert(#E.design.boxes==2,'solid duplicate failed')
 Editor.keypressed('delete');assert(#E.design.boxes==1,'delete did not remove the whole solid')
 local data=require('src.data');local previousIcon=data.icons.steel_plate
 local savePath=Export.FOLDER..'/icons/icon_steel_plate.lua';local previousFile=love.filesystem.read(savePath)
 E.design.folder='icons';E.export()
 assert(love.filesystem.getInfo(savePath),'Save did not write an icon file')
 E.openIcon('steel_plate');assert(E.design.boxes[1].x==moved,'reopening the saved icon lost editable parameters')
 data.icons.steel_plate=previousIcon
 if previousFile then love.filesystem.write(savePath,previousFile) else love.filesystem.remove(savePath) end
 Editor.keypressed('p');assert(E.tool=='solid' and not E.drawing,'polygon shortcut interferes with solid editing')
 E.isOpenFlag=false
 print('ok  icon authoring: create, select, drag, undo, duplicate, delete and export')
 print('ok  icon shapes: depth render and editable export')
end
