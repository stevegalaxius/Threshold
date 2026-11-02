-- Sleeping rocks keep a fixed orbital radius. Cull whole radial bands before
-- evaluating their rotating positions; the exact distance/view checks follow.
local Index={}
local WIDTH=1024
function Index.range(game,x,y,reach)
 local list=game.sleepers
 local index=game.sleeperIndex
 if not index or index.source~=list then
  index={source=list,bands={},queries={}}
  for i,e in ipairs(list) do
   e.sleepSlot=i
   if e.sleep and not e.removed then
    local band=math.floor(e.sleep.r/WIDTH)
    local bucket=index.bands[band]
    if not bucket then bucket={};index.bands[band]=bucket end
    bucket[#bucket+1]=e
    e.sleepBandSlot=#bucket
   end
  end
  game.sleeperIndex=index
 end
 local w=game.well
 local dx,dy=x-w.x,y-w.y
 local r=math.sqrt(dx*dx+dy*dy)
 local first=math.max(0,math.floor((r-reach)/WIDTH))
 local last=math.floor((r+reach)/WIDTH)
 return index,first,last
end
function Index.candidates(game,x,y,reach,kind)
 local index,first,last=Index.range(game,x,y,reach)
 kind=kind or 'draw'
 index.queries=index.queries or {}
 local query=index.queries[kind]
 if not query or query.first~=first or query.last~=last then
  query={first=first,last=last}
  for band=first,last do
   local bucket=index.bands[band]
   if bucket then
    for _,e in ipairs(bucket) do query[#query+1]=e end
   end
  end
  index.queries[kind]=query
 end
 return query
end
function Index.add(game,e)
 local index=game.sleeperIndex
 if not index or index.source~=game.sleepers then return end
 local band=math.floor(e.sleep.r/WIDTH)
 local bucket=index.bands[band]
 if not bucket then bucket={};index.bands[band]=bucket end
 bucket[#bucket+1]=e;e.sleepBandSlot=#bucket
 index.queries=nil
end
function Index.remove(game,e)
 local index=game.sleeperIndex
 if not index or index.source~=game.sleepers then return end
 local bucket=index.bands[math.floor(e.sleep.r/WIDTH)]
 local slot=e.sleepBandSlot
 local last=bucket[#bucket]
 bucket[slot]=last;bucket[#bucket]=nil
 if last~=e then last.sleepBandSlot=slot end
 e.sleepBandSlot=nil
 index.queries=nil
end

return Index
