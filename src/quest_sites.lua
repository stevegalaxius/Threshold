--[[
	Site jobs: "go to a place and use an item there". A blueprint for station
	quests that send the player somewhere in space (src/quests.lua posts and
	settles them; the contracts screen lists them like any other quest).

	Q.site(kind, def) registers one. def:
	  label           board label
	  item            the item you use at the site (its `use` has a
	                  { "quest", item = <id> } effect: src/item_use.lua)
	  give            true: one item is put in your hold when you accept
	                  (a stand-in for gear the job provides); false: bring
	                  your own
	  candidates(u, clock) -> list of { giver, area, subject, reward, title, detail }
	                  called once per quest tick; each candidate is one job
	  open(u, q)      does the job still need doing? (else the offer is
	                  withdrawn, or an accepted one fails: someone else did it)
	  where(game, q)  -> x, y, range, label while you're on q.area's map
	  apply(game, q)  the item was used at the site: do the work

	Quests made here carry: kind, giver, area, subject, key, item, give,
	amount = 1, unit = reward, title, detail. The HUD compass shows the site
	of every active one on the current map (Q.markers).
]]
local T=require('src.tuning')
return function(Q)
 Q.sites={}
 function Q.site(kind,def)
  Q.sites[kind]=def
  Q.order[#Q.order+1]=kind
  local list={}
  Q.generators[kind]={
   label=def.label,
   prepare=function(u,clock)
    list={}
    for _,c in ipairs(def.candidates(u,clock)) do
     list[c.giver]=list[c.giver] or {};table.insert(list[c.giver],c)
    end
   end,
   keep=function(u,q) return def.open(u,q) end,
   propose=function(u,st,clock,ctx)
    local out={}
    for _,c in ipairs(list[st] or {}) do
     local key=kind..'|'..c.subject
     if not ctx.taken[key] then
      out[#out+1]={kind=kind,giver=st,area=c.area,subject=c.subject,key=key,item=def.item,give=def.give or nil,
       amount=1,unit=c.reward,title=c.title,detail=c.detail}
     end
    end
    table.sort(out,function(a,b) return a.subject<b.subject end)
    return out
   end,
   resolve=function(game,q)
    if q.used then return 'done',q.title..': done' end
    if not def.open(game.universe,q) then return 'failed','Someone else got there first' end
   end,
  }
 end

 -- Where the player's active site jobs are on this map, for the HUD.
 function Q.markers(game)
  local out={}
  for _,q in pairs(Q.state(game.universe).active) do
   local def=Q.sites[q.kind]
   if def and q.area==game.fieldId and not q.used then
    local x,y,range,label=def.where(game,q)
    if x then out[#out+1]={x=x,y=y,range=range,label=label or q.title,quest=q} end
   end
  end
  return out
 end

 -- The quest an item use at e's position would count for, if any.
 function Q.siteFor(game,e,item)
  if not e or e~=game.player or not e.body then return nil end
  local px,py=e.body:getPosition()
  for _,m in ipairs(Q.markers(game)) do
   if m.quest.item==item and (m.x-px)^2+(m.y-py)^2<=m.range^2 then return m.quest end
  end
 end
 function Q.useAt(game,e,item)
  local q=Q.siteFor(game,e,item)
  if not q then return false end
  Q.sites[q.kind].apply(game,q)
  q.used=game.universe.clock
  -- settle now rather than at the next quest tick
  local status,text=Q.generators[q.kind].resolve(game,q)
  if status then Q.settle(game.universe,q,status,game.universe.clock,game,text) end
  return true
 end
 T.siteRange=T.siteRange or 2500
end
