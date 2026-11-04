-- Developer world edits are transactions: change one definition, rebuild the
-- catalogue, reconcile the saved universe, then rebuild the loaded scene.
local W,L,F=require('src.world_layout'),require('src.locations'),require('src.fields')
local Save,copy=require('src.save'),require('src.persistence').copy
local E={}
local function compile()
 for area in pairs(W.stations) do assert(F[area],'unknown station region '..tostring(area)) end
 for area in pairs(W.navigation) do assert(F[area],'unknown navigation region '..tostring(area)) end
 L.rebuildAll()
 for _,place in pairs(L.byId) do
  assert(type(place.id)=='string' and type(place.name)=='string','locations need string identities and names')
  local x,y=L.position(place.id,0)
  assert(type(x)=='number' and type(y)=='number' and x==x and y==y and math.abs(x)<math.huge and math.abs(y)<math.huge,'location position must be finite: '..place.id)
  if place.kind=='buoy' then L.buoyDefinition(place.id) end
  if place.kind=='station' then
   L.stationDefinition(place.id)
   assert(not place.marketId or require('src.data').markets[place.marketId],'unknown station market '..tostring(place.marketId))
   assert(place.adapter~='cloud' or F[place.area].gas,'cloud cities require a gas giant')
  end
 end
end
local function change(edit)
 local before={stations=copy(W.stations),navigation=copy(W.navigation),specials=copy(W.specials),defaults=copy(W.defaults)}
 local ok,result=pcall(function()local value=edit(W);compile();return value end)
 if not ok then
  W.stations,W.navigation,W.specials,W.defaults=before.stations,before.navigation,before.specials,before.defaults
  L.rebuildAll()
  return nil,result
 end
 return true,result
end
function E.apply(game,edit)
 local Cargo=require('src.ui.cargo')
 Cargo.close(game);Cargo.clearTrade(game)
 local snapshot=game:saveState()
 -- Outgoing bodies still refer to the old catalogue. Detach them before IDs
 -- move between regions or disappear, then restore from the immutable snapshot.
 game:captureALife(true)
 require('src.mining').unload(game)
 local ok,result=change(edit)
 if not ok then game:loadState(snapshot);return nil,result end
 game:loadState(snapshot)
 if game.npcTraffic then game.npcTraffic.model=nil end
 if game.localMap then require('src.ui.localmap').fit(game) end
 return true,result
end
function E.import(game,text)
 local definition,err=Save.decode(text)
 if not definition then return nil,err end
 if type(definition.stations)~='table' or type(definition.navigation)~='table' then return nil,'world definition needs stations and navigation tables' end
 return E.apply(game,function()W.stations=definition.stations;W.navigation=definition.navigation;W.specials=definition.specials or W.specials;W.defaults=definition.defaults or W.defaults end)
end
function E.save(path)
 return love.filesystem.write(path or 'world_layout.lua',W.export())
end
function E.loadDefinition(path)
 local text,err=love.filesystem.read(path or 'world_layout.lua')
 if not text then return nil,err end
 local definition;definition,err=Save.decode(text)
 if not definition then return nil,err end
 if type(definition.stations)~='table' or type(definition.navigation)~='table' then return nil,'world definition needs stations and navigation tables' end
 return change(function()W.stations=definition.stations;W.navigation=definition.navigation;W.specials=definition.specials or W.specials;W.defaults=definition.defaults or W.defaults end)
end
return E
