-- Debug destination view within the player's map; includes moons and real places.
local Travel=require('src.debugtravel')
local Fields=require('src.fields')
local Locations=require('src.locations')
local HUD=require('src.hud')
local W={}
local function layout(game)
 local width,height=love.graphics.getDimensions()
 local out={};local areas=Travel.areas();local rows=math.ceil(#areas/3)
 local col=(width-350)/3;local row=math.min(44,(height-150)/rows)
 for i,id in ipairs(areas) do
  out[#out+1]={x=24+math.floor((i-1)/rows)*col,y=105+(i-1)%rows*row,w=col-8,h=row-5,label=Fields[id].name,selected=(game.localMap.worldArea or game.fieldId)==id,
   action=function() game.localMap.worldArea=id end}
 end
 local area=game.localMap.worldArea or (not Fields[game.fieldId].transit and game.fieldId or 'mars')
 out[#out+1]={x=width-300,y=105,w=276,h=34,label='Teleport: '..Fields[area].name,action=function() Travel.go(game,area) end}
 for i,p in ipairs(Locations.list(area)) do
  out[#out+1]={x=width-300,y=152+(i-1)*38,w=276,h=32,label='Go: '..p.name,action=function() Travel.go(game,area,p.id) end}
 end
 return out
end
function W.click(game,x,y)
 for _,b in ipairs(layout(game)) do
  if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then b.action();break end
 end
end
function W.draw(game)
 local lg=love.graphics;local width,height=lg.getDimensions()
 lg.push('all');lg.origin();lg.clear(.015,.035,.055)
 lg.setFont(HUD.font(20));lg.setColor(HUD.AQUA);lg.print('WORLD DESTINATIONS / DEBUG TRAVEL',24,22)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.print('Select a region, then teleport to its spawn or a named location. Ship and cargo are preserved.',24,82)
 lg.print('M / Esc close',width-110,30)
 for _,b in ipairs(layout(game)) do
  lg.setColor(b.selected and .15 or .09,b.selected and .28 or .16,b.selected and .33 or .20);lg.rectangle('fill',b.x,b.y,b.w,b.h,4)
  lg.setColor(HUD.INK);lg.print(b.label,b.x+8,b.y+7)
 end
 lg.pop()
end
return W
