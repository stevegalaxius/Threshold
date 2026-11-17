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
 assert(#decoded.parts==0,'export saved generated faces')
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
 print('ok  icon shapes: depth render and editable export')
end
