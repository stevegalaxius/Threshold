--[[
	Regional availability: how much of each good (and each dealer hull)
	every region holds against what its stations want.

	A.region(u, area, item)   -> { count, target, stations = { {id, count, target} } }
	A.status(count, target)   -> 'short' | 'ok' | 'glut'
	A.table(u)                -> rows[item][area] = region record, for every good
	A.hulls(u)                -> hulls[area][hullId] = { new, used }
	A.panel(game, Slab)       -> debug view (A-Life window)
]]
local A={}
local L=require('src.locations')
local Fields=require('src.fields')

A.glut=3   -- stock at this many times target counts as a glut

function A.status(count,target)
 if target<=0 then return count>0 and 'ok' or 'none' end
 if count<target then return 'short' end
 if count>=target*A.glut then return 'glut' end
 return 'ok'
end

function A.items()
 local out,seen={},{}
 local function add(id) if not seen[id] then seen[id]=true;out[#out+1]=id end end
 for _,id in ipairs(require('src.economy').goods()) do add(id) end
 for _,id in ipairs(require('src.ammunition').products or {}) do add(id) end
 return out
end

function A.region(u,area,item)
 local Stock,Econ=require('src.stockpile'),require('src.economy')
 local rec={count=0,target=0,short=0,stations={}}
 for _,id in ipairs(L.stations(area,'trade')) do
  local okC,n=pcall(Stock.count,u,id,item)
  local okT,t=pcall(Econ.target,u,id,item)
  n=okC and n or 0;t=okT and math.floor((t or 0)+0.5) or 0
  rec.count,rec.target=rec.count+n,rec.target+t
  if t>0 and n<t then rec.short=rec.short+1 end
  rec.stations[#rec.stations+1]={id=id,count=n,target=t}
 end
 rec.status=A.status(rec.count,rec.target)
 return rec
end

function A.table(u)
 local rows={}
 for _,item in ipairs(A.items()) do
  rows[item]={}
  for _,area in ipairs(Fields.list) do rows[item][area]=A.region(u,area,item) end
 end
 return rows
end

function A.hulls(u)
 local D=require('src.dealers');local out={}
 for _,area in ipairs(Fields.list) do
  local per={}
  for _,id in ipairs(L.stations(area)) do
   local ok,lots=pcall(D.lots,u,id)
   for _,lot in ipairs(ok and lots or {}) do
    local h=per[lot.hull] or {new=0,used=0};per[lot.hull]=h
    if lot.used then h.used=h.used+1 else h.new=h.new+1 end
   end
  end
  out[area]=per
 end
 return out
end

-- Debug view ---------------------------------------------------------------
local colors={short={1,.45,.4,1},ok={.6,.9,.6,1},glut={.55,.75,1,1},none={.55,.55,.55,1}}
local view={mode='good',item=nil,area=nil}
A.view=view

local function pick(Slab,id,selected,options,onPick)
 if Slab.BeginComboBox(id,{Selected=selected}) then
  for _,o in ipairs(options) do if Slab.TextSelectable(o) then onPick(o) end end
  Slab.EndComboBox()
 end
end

function A.panel(game,Slab)
 local u=game.universe
 local items=A.items()
 view.item=view.item or items[1]
 view.area=view.area or game.fieldId or Fields.list[1]
 pick(Slab,'avail_mode',view.mode,{'good','region','short','hulls'},function(v) view.mode=v end)
 Slab.Text('Colours: red short (< target), green ok, blue glut (>= '..A.glut..'x target).')
 if view.mode=='good' then
  pick(Slab,'avail_item',view.item,items,function(v) view.item=v end)
  for _,area in ipairs(Fields.list) do
   local r=A.region(u,area,view.item)
   if #r.stations>0 then
    Slab.Text(('%-14s %6d / %-6d  %d of %d stations short'):format(area,r.count,r.target,r.short,#r.stations),{Color=colors[r.status]})
   end
  end
 elseif view.mode=='region' then
  pick(Slab,'avail_area',view.area,Fields.list,function(v) view.area=v end)
  for _,item in ipairs(items) do
   local r=A.region(u,view.area,item)
   if r.count>0 or r.target>0 then
    Slab.Text(('%-20s %6d / %-6d'):format(item,r.count,r.target),{Color=colors[r.status]})
   end
  end
 elseif view.mode=='short' then
  -- every good, the regions where it runs short
  for _,item in ipairs(items) do
   local list={}
   for _,area in ipairs(Fields.list) do
    local r=A.region(u,area,item)
    if r.status=='short' then list[#list+1]=('%s %d/%d'):format(area,r.count,r.target) end
   end
   if #list>0 then Slab.Text(item..': '..table.concat(list,', '),{Color=colors.short}) end
  end
 else
  local data=require('src.data')
  for area,per in pairs(A.hulls(u)) do
   local parts={}
   for hull,h in pairs(per) do parts[#parts+1]=('%s %d new/%d used'):format(data.hulls[hull] and data.hulls[hull].name or hull,h.new,h.used) end
   if #parts>0 then table.sort(parts);Slab.Text(area..': '..table.concat(parts,', ')) end
  end
 end
end

return A
