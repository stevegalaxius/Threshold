-- Isolated preview bodies share Ship.performance with the F1 handling readout.
local Slab=require('lib.Slab')
local data=require('src.data')
local Ship=require('src.ship')
local T=require('src.tuning')
local Export=require('src.editor.export')
local C={open=false,emptyHolds=false,previews={}}
local function world()
 if not C.world or C.world:isDestroyed() then
  C.world=love.physics.newWorld(0,0,true)
  C.context={world=C.world,field={rockDrag=0},nextId=function()return 0 end}
 end
 return C.context
end
function C.clear()
 if C.world and not C.world:isDestroyed() then C.world:destroy() end
 C.world=nil;C.context=nil;C.previews={}
end
local function preview(side,definition,empty)
 local signature=Export.serialize(definition)..tostring(empty)
 local cached=C.previews[side]
 if not cached or cached.signature~=signature then
  if cached and cached.ship and not cached.ship.body:isDestroyed() then cached.ship.body:destroy() end
  cached={signature=signature};C.previews[side]=cached
  local def,err
  if definition.parts and #definition.parts==0 then err='Add a hull part to compare handling.'
  elseif side=='reference' then def=Export.copy(definition)
  else def,err=data.prepareHull(Export.copy(definition)) end
  if not def then cached.error=err
  else
   local context=world();local existing={}
   for _,body in ipairs(context.world:getBodies()) do existing[body]=true end
   local ok,ship=pcall(Ship.new,context,{hull=def,cargo=empty and {} or def.cargo,grid=true})
   if ok then cached.ship=ship
   else
    cached.error=ship
    for _,body in ipairs(context.world:getBodies()) do if not existing[body] then body:destroy() end end
   end
  end
 end
 if cached.ship then Ship.updateMass(cached.ship) end
 return cached.ship,cached.error
end
function C.compare(design,id,empty)
 if design.kind and design.kind~='hull' then return nil,'Select a ship hull to compare.' end
 local reference=data.hulls[id]
 if not reference then return nil,'Select a comparison ship.' end
 local current,currentError=preview('design',Export.hullDef(design),empty)
 local other,otherError=preview('reference',reference,empty)
 return {current=current,reference=other,currentError=currentError,referenceError=otherError}
end
function C.rows(ship)
 local p=Ship.performance(ship);local s=ship.stats
 return {
  {'Mass',p.mass,'%.0f t'},
  {'Dry mass',s.mass*T.massScale,'%.0f t'},
  {'Cargo mass',ship.cargoMass*T.massScale,'%.0f t'},
  {'Acceleration',p.accel,'%.0f px/s2'},
  {'Top speed',p.topSpeed,'%.0f px/s'},
  {'Max afterburner speed',p.afterburnTopSpeed,'%.0f px/s'},
  {'Turn acceleration',p.turnAccel,'%.1f rad/s2'},
  {'Max turn speed',p.turnSpeed,'%.0f deg/s'},
  {'Side acceleration',p.sideAccel,'%.0f px/s2'},
  {'Main thrust',s.thrust,'%.0f kN'},
  {'Maneuvering thrust',s.sideThrust,'%.0f kN'},
  {'Reverse thrust',s.retroThrust,'%.0f kN'},
  {'Armor',s.armor,'%.0f'},
  {'Power output',s.powerOut,'%.0f/s'},
  {'Power draw',s.powerDraw,'%.0f/s'},
  {'Power storage',s.powerCap,'%.0f'},
  {'Hold used',ship.holdUsed,'%.1f m3'},
  {'Hold capacity',Ship.holdCapacity(ship),'%.0f m3'},
  {'Engine spool time',ship.hull.spoolTime or 0,'%.2f s'},
  {'Crash toughness',ship.hull.toughness or 1,'x%.2f'},
 }
end
function C.update(E)
 if not C.open or E.isPlaced() then return end
 local width,height=love.graphics.getDimensions()
 C.open=Slab.BeginWindow('yard_comparison',{Title='Ship comparison',X=math.max(20,(width-780)/2),Y=60,
  W=math.min(780,width-40),H=math.min(610,height-80),AutoSizeWindow=false,AllowResize=true,IsOpen=C.open})
 if C.open then
  if not data.hulls[C.selected] then C.selected=E.design.base or data.list.hulls[1] end
  Slab.Text('Compare current design with:')
  if Slab.BeginComboBox('yard_compare_hull',{Selected=data.hulls[C.selected].name,W=320}) then
   for _,id in ipairs(data.list.hulls) do
    if Slab.TextSelectable(data.hulls[id].name..' ('..id..')') then C.selected=id end
   end
   Slab.EndComboBox()
  end
  if Slab.CheckBox(C.emptyHolds,'Empty holds on both ships') then C.emptyHolds=not C.emptyHolds end
  Slab.Text('Uses fitted default modules. Handling matches F1; speeds are relative to the local current.')
  Slab.Text('Afterburner speed is the full-power maximum before capacitor reserve mode.')
  Slab.Separator()
  local result,err=C.compare(E.design,C.selected,C.emptyHolds)
  if not result then Slab.Text(err)
  else
   local a=result.current and C.rows(result.current)
   local b=result.reference and C.rows(result.reference)
   if result.currentError then Slab.Text('Design: '..tostring(result.currentError)) end
   if result.referenceError then Slab.Text('Comparison: '..tostring(result.referenceError)) end
   Slab.BeginLayout('yard_compare_stats',{Columns=3,ExpandW=true})
   local count=a and #a or b and #b or 0
   for col=1,3 do
    Slab.SetLayoutColumn(col)
    Slab.Text(col==1 and 'Stat' or col==2 and E.design.name..' (design)' or data.hulls[C.selected].name)
    for i=1,count do
     local row=(a or b)[i]
     if col==1 then Slab.Text(row[1])
     else
      local values
      if col==2 then values=a else values=b end
      Slab.Text(values and string.format(values[i][3],values[i][2]) or '--')
     end
    end
   end
   Slab.EndLayout()
  end
 end
 Slab.EndWindow()
 if not C.open then C.clear() end
end
return C
