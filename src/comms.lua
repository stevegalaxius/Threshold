--[[
	Comms: ship-to-ship conversations in space.

	One mechanism for every exchange between two ships: a pirate's demand
	(src/dialogs/robbery.lua), a police cargo inspection
	(src/dialogs/inspection.lua), and later quest givers and NPC dialog.
	The systems that own the outcome (src/robbery.lua, src/contraband.lua,
	src/quests.lua) open a channel with a script and react to what happens;
	comms only carries the conversation.

	A channel joins two ships:
	  speaker    the ship that opened it (the patrol, the pirate, the giver)
	  listener   the ship it's addressed to (often the player)
	Either side can be the player or an NPC. NPC sides answer through the
	same script (a node's `npc` picks for them), so an NPC trader stopped by
	police meets the same outcomes the player would.

	A script is a table of nodes:

	  return {
	    start = 'hail',
	    nodes = {
	      hail = {
	        text = "{speaker.faction} patrol {speaker.name}. Hold for a scan.",
	        timeout = 20, onTimeout = 'ran',      -- seconds, or function(ch)
	        enter = function(ch) ... end,         -- runs on arrival; may return
	                                              -- a node id to move on to
	        npc = function(ch) return 1 end,      -- option an NPC side picks
	        options = {
	          { "Comply", go = 'scan' },
	          { "Bribe ({bribe} cr)", show = function(ch) ... end,
	            pick = function(ch) return 'waved' end },
	        },
	      },
	    },
	  }

	Text takes tokens: {speaker.name}, {speaker.faction}, {listener.name},
	{listener.faction}, and {key} for any value in ch.v (the variables the
	opening system put there). text may also be a function(ch).

	An option is { label, go = node } or { label, pick = function(ch) ->
	node id }, with optional show(ch) (hidden when false) and enabled(ch)
	(greyed out when false). A node with no options is an ending: it stays
	on screen for a moment, then the channel closes.

	Quests and other systems add to a conversation without touching the
	script: Comms.extend(scriptId, nodeId, fn) registers fn(ch, options)
	to append options when that node is shown.

	Channels hold live entities, so they aren't saved: a reload drops any
	conversation in progress, and whoever opened it (the pirate, the patrol)
	starts over if it still wants to.
]]
local Comms={channels={},extensions={},scripts={},nextId=0}

Comms.T={endingLinger=5,maxLog=8}

local function gone(e) return not e or e.dead or e.removed end

function Comms.script(id)
 local s=Comms.scripts[id]
 if not s then s=require('src.dialogs.'..id);Comms.scripts[id]=s end
 return s
end
function Comms.register(id,script) Comms.scripts[id]=script end
function Comms.extend(scriptId,nodeId,fn)
 local key=scriptId..'/'..nodeId
 Comms.extensions[key]=Comms.extensions[key] or {}
 table.insert(Comms.extensions[key],fn)
end

-- Who a ship is, for tokens and the window header.
function Comms.nameOf(e)
 if not e then return '?' end
 if e.isPlayer then return e.hull and e.hull.name or 'your ship' end
 return e.def and e.def.name or (e.hull and e.hull.name) or 'unknown ship'
end
function Comms.factionOf(game,e)
 local Rep=require('src.reputation')
 if not e or e.isPlayer then return nil end
 local r=e.alifeRecord or (e.alifeId and game.universe.npcs[e.alifeId])
 local grant=r and require('src.npc_access').policeGrant(r,game.fieldId)
 local f=grant and grant.issuer or Rep.crewFaction(r)
 return f
end
function Comms.factionName(game,e)
 local f=Comms.factionOf(game,e)
 local def=f and require('src.reputation').FACTIONS[f]
 return def and def.name or (e and e.isPlayer and 'Independent' or 'Unaffiliated')
end

local function side(ch,which)
 local e=ch[which]
 return {name=Comms.nameOf(e),faction=Comms.factionName(ch.game,e)}
end
function Comms.format(ch,s)
 if type(s)=='function' then s=s(ch) end
 if not s then return '' end
 return (s:gsub('{([%w_%.]+)}',function(key)
  local who,field=key:match('^(%a+)%.(%w+)$')
  if who=='speaker' or who=='listener' then
   local v=side(ch,who)[field];if v~=nil then return tostring(v) end
  end
  local v=ch.v[key]
  if v~=nil then return tostring(v) end
  return '{'..key..'}'
 end))
end

function Comms.node(ch) return ch.script.nodes[ch.node] end

-- The options shown for the current node: { label, enabled, option }.
function Comms.options(ch)
 local node=Comms.node(ch)
 local out={}
 local list={}
 for _,o in ipairs(node and node.options or {}) do list[#list+1]=o end
 for _,fn in ipairs(Comms.extensions[ch.scriptId..'/'..tostring(ch.node)] or {}) do fn(ch,list) end
 for _,o in ipairs(list) do
  if not o.show or o.show(ch) then
   out[#out+1]={label=Comms.format(ch,o[1] or o.label),enabled=not o.enabled or o.enabled(ch)~=false,option=o}
  end
 end
 return out
end

local function log(ch,who,text)
 if text=='' then return end
 ch.log[#ch.log+1]={who=who,text=text}
 while #ch.log>Comms.T.maxLog do table.remove(ch.log,1) end
end

-- Move a channel to a node (nil closes it).
function Comms.go(ch,nodeId)
 if not ch or ch.closed then return end
 for _=1,16 do                       -- enter() may hop on; guard against loops
  if not nodeId then return Comms.close(ch,'ended') end
  local node=ch.script.nodes[nodeId]
  assert(node,('dialog %s has no node %s'):format(ch.scriptId,tostring(nodeId)))
  ch.node=nodeId;ch.enteredAt=ch.game.time
  local nextId=node.enter and node.enter(ch)
  if ch.closed then return end
  if nextId and nextId~=nodeId then
   nodeId=nextId
  else
   log(ch,'speaker',Comms.format(ch,node.text))
   local t=node.timeout;if type(t)=='function' then t=t(ch) end
   ch.deadline=t and ch.game.time+t or nil
   ch.endAt=(not node.options or #node.options==0) and not node.hold and ch.game.time+Comms.T.endingLinger or nil
   ch.npcPicked=nil
   return
  end
 end
 error('dialog '..ch.scriptId..' loops at '..tostring(nodeId))
end

-- The player (or an NPC) picks option i of what Comms.options shows.
function Comms.choose(ch,i)
 if not ch or ch.closed then return end
 local shown=Comms.options(ch)[i]
 if not shown or not shown.enabled then return end
 local o=shown.option
 log(ch,'listener',shown.label)
 local nextId
 if o.pick then nextId=o.pick(ch) else nextId=o.go end
 if ch.closed then return end
 if nextId==false then return end            -- stay on this node
 Comms.go(ch,nextId)
end

function Comms.close(ch,why)
 if not ch or ch.closed then return end
 ch.closed=true;ch.why=why
 for i,c in ipairs(Comms.channels) do if c==ch then table.remove(Comms.channels,i);break end end
 if ch.speaker and ch.speaker.comms==ch then ch.speaker.comms=nil end
 if ch.listener and ch.listener.comms==ch then ch.listener.comms=nil end
 if ch.script.onClose then ch.script.onClose(ch,why) end
end

-- Open a conversation. vars: the script's variables (ch.v). Replaces any
-- channel either ship already has open.
function Comms.open(game,scriptId,speaker,listener,vars)
 Comms.close(speaker.comms,'replaced');Comms.close(listener.comms,'replaced')
 Comms.nextId=Comms.nextId+1
 local ch={id=Comms.nextId,scriptId=scriptId,script=Comms.script(scriptId),game=game,
  speaker=speaker,listener=listener,v=vars or {},log={},opened=game.time}
 speaker.comms,listener.comms=ch,ch
 Comms.channels[#Comms.channels+1]=ch
 Comms.go(ch,ch.script.start)
 if not ch.closed and listener.isPlayer then
  require('src.notify').post(game.universe,{kind='comms',title='Incoming hail: '..Comms.factionName(game,speaker)..' '..Comms.nameOf(speaker),
   text='Press C to answer',key='comms:'..ch.id})
  if Comms.onHail then Comms.onHail(game,ch) end
 end
 return ch
end

function Comms.involvesPlayer(ch) return ch.speaker.isPlayer or ch.listener.isPlayer end
-- The player's open conversation, newest first.
function Comms.playerChannel()
 for i=#Comms.channels,1,-1 do
  local ch=Comms.channels[i]
  if Comms.involvesPlayer(ch) then return ch end
 end
end
function Comms.remaining(ch)
 return ch.deadline and math.max(0,ch.deadline-ch.game.time) or nil
end

function Comms.update(game)
 for i=#Comms.channels,1,-1 do
  local ch=Comms.channels[i]
  if ch and not ch.closed then
   ch.game=game
   if gone(ch.speaker) or gone(ch.listener) then Comms.close(ch,'lost contact')
   elseif ch.endAt and game.time>=ch.endAt then Comms.close(ch,'ended')
   elseif ch.deadline and game.time>=ch.deadline then
    local node=Comms.node(ch)
    log(ch,'listener','(no answer)')
    Comms.go(ch,node.onTimeout)
   else
    -- an NPC side answers once per node, through the node's npc rule
    local node=Comms.node(ch)
    local npcSide=not ch.listener.isPlayer
    if npcSide and node.npc and not ch.npcPicked then
     ch.npcPicked=true
     local pick=node.npc(ch)
     if pick then Comms.choose(ch,pick) end
    end
   end
  end
 end
end

function Comms.reset()
 for i=#Comms.channels,1,-1 do Comms.close(Comms.channels[i],'reset') end
 Comms.channels={}
end

return Comms
