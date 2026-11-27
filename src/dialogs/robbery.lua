-- A pirate's demand (src/robbery.lua owns the outcome: it watches the
-- jettison count and decides when the target is spared or fired on).
-- ch.v.request is the Handover request; ch.v.amount what it asks for.
local function robbery() return require('src.robbery') end
local function left(ch) local d=ch.v.request;return math.max(0,d.amount-d.paid) end
local function refuse(ch)
 ch.v.request.refused=true
 if not ch.listener.isPlayer then ch.listener.aggressor=ch.speaker end
 return 'refused'
end
local options={
 { "Jettison {owed} cargo", pick=function(ch)
   robbery().pay(ch.game,ch.listener,ch.v.request)
   return 'waiting'
  end },
 { "Haggle", show=function(ch) return not ch.v.haggled end, pick=function(ch)
   ch.v.haggled=true
   return robbery().haggle(ch.game,ch.v.request) and 'haggled' or 'firm'
  end },
 { "Refuse", pick=refuse },
}
local function demand(text)
 return { text=text,
  enter=function(ch) ch.v.owed=left(ch) end,
  timeout=function(ch) return math.max(0,ch.v.request.deadline-ch.game.time) end,
  onTimeout='refused',
  npc=function(ch) return robbery().npcAnswer(ch.game,ch.listener,ch.v.request) end,
  options=options }
end
return {
 start='demand',
 -- the Handover request holds live ships: save its numbers, reopen it on load
 save=function(ch)
  local d=ch.v.request
  return {amount=d.amount,paid=d.paid,owed=ch.v.owed,haggled=ch.v.haggled,refused=d.refused}
 end,
 restore=function(game,ch,saved) return robbery().restore(game,ch,saved) end,
 nodes={
  demand=demand('"{listener.name}, jettison {owed} cargo or be fired upon."'),
  haggled=demand('"Fine. {owed}, and be quick about it."'),
  firm=demand('"Don\'t push your luck. {owed}. Now."'),
  waiting={ text='"Keep it coming."', hold=true,
   enter=function(ch) ch.v.owed=left(ch) end,
   timeout=function(ch) return math.max(0,ch.v.request.deadline-ch.game.time) end,
   onTimeout='refused',
   options={ { "Jettison {owed} more", show=function(ch) return left(ch)>0 end, pick=function(ch)
     robbery().pay(ch.game,ch.listener,ch.v.request);ch.v.owed=left(ch);return false end },
    { "Refuse", pick=refuse } } },
  paid={ text='"Wise choice. Move along."' },
  refused={ text='"You were warned." They\'re opening fire.',
   enter=function(ch) ch.v.request.refused=true end },
 },
}
