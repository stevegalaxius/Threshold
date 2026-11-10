-- Equipment selection and recovery yield shared by physical and remote wrecks.
local data=require('src.data')
local T=require('src.tuning')
local W={}
function W.weapon(ship)
 local cargo=ship.cargo or {}
 local slots=ship.weapons
 if not slots then
  slots={}
  for _,id in pairs(ship.loadout or {}) do
   local m=id and data.modules[id]
   if m and m.weapon then slots[#slots+1]={w=m.weapon,ammoOptions=data.ammoOptions(m)} end
  end
 end
 local gun
 for _,slot in ipairs(slots) do
  local w=slot.w
  if (w.damage or 0)>0 and w.kind=='drill' then return slot end
  if w.kind=='laser' and (w.damage or 0)>0 then gun=gun or slot
  elseif w.kind=='cannon' then
   for _,id in ipairs(slot.ammoOptions or {slot.ammo}) do
    local item=id and data.items[id]
    if item and item.shot and (item.shot.damage or 0)>0 and (cargo[id] or 0)>0 then gun=gun or slot;break end
   end
  end
 end
 return gun
end
function W.survivors(n,drilled,roll)
 if drilled then return n end
 roll=roll or love.math.random
 local survived=0
 for _=1,n do if roll()<T.wreckShotRecovery then survived=survived+1 end end
 return survived
end
function W.scatter(game,x,y,stack,safe)
 local n=W.survivors(stack.n,safe)
 if n>0 then game:spawnPickup(x,y,stack.id,n,stack.inner) end
end
return W
