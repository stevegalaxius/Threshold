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
-- A satellite (e.sat) speaks as itself: its record's name, its planet's faction.
local function satRecord(game,e)
 return e and e.sat and game and require('src.satellites').get(game.universe,e.sat)
end
function Comms.nameOf(e,game)
 if not e then return '?' end
 local r=satRecord(game,e)
 if r then return r.name or 'satellite' end
 if e.isPlayer then return e.hull and e.hull.name or 'your ship' end
 return e.def and e.def.name or (e.hull and e.hull.name) or 'unknown ship'
end
function Comms.factionOf(game,e)
 local Rep=require('src.reputation')
 if not e or e.isPlayer then return nil end
 local sr=satRecord(game,e)
 if sr then return require('src.satellites').faction(sr) end
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
 return {name=Comms.nameOf(e,ch.game),faction=Comms.factionName(ch.game,e)}
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

-- A node's own options: a list, or function(ch) -> list for ones that
-- change with the conversation.
local function nodeOptions(ch,node)
 local o=node and node.options
 if type(o)=='function' then o=o(ch) end
 return o or {}
end

-- The options shown for the current node: { label, enabled, option }.
function Comms.options(ch)
 local node=Comms.node(ch)
 local out={}
 local list={}
 for _,o in ipairs(nodeOptions(ch,node)) do list[#list+1]=o end
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
   ch.endAt=#nodeOptions(ch,node)==0 and not node.hold and ch.game.time+Comms.T.endingLinger or nil
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

-- why: 'ended', 'lost contact', 'replaced' (by: the channel taking over),
-- 'reset'. The script's onClose(ch, why, by) hears it.
function Comms.close(ch,why,by)
 if not ch or ch.closed then return end
 ch.closed=true;ch.why=why
 for i,c in ipairs(Comms.channels) do if c==ch then table.remove(Comms.channels,i);break end end
 if ch.speaker and ch.speaker.comms==ch then ch.speaker.comms=nil end
 if ch.listener and ch.listener.comms==ch then ch.listener.comms=nil end
 if ch.script.onClose then ch.script.onClose(ch,why,by) end
end

-- Open a conversation. vars: the script's variables (ch.v). Replaces any
-- channel either ship already has open.
local function attach(game,scriptId,speaker,listener,vars)
 Comms.nextId=Comms.nextId+1
 local ch={id=Comms.nextId,scriptId=scriptId,script=Comms.script(scriptId),game=game,
  speaker=speaker,listener=listener,v=vars or {},log={},opened=game.time}
 local old1,old2=speaker.comms,listener.comms
 speaker.comms,listener.comms=ch,ch
 Comms.channels[#Comms.channels+1]=ch
 Comms.close(old1,'replaced',ch);Comms.close(old2,'replaced',ch)
 speaker.comms,listener.comms=ch,ch
 return ch
end
function Comms.open(game,scriptId,speaker,listener,vars)
 local ch=attach(game,scriptId,speaker,listener,vars)
 Comms.go(ch,ch.script.start)
 if not ch.closed and listener.isPlayer then
  -- a script can word its own notice (a satellite's broadcast)
  local who=Comms.factionName(game,speaker)..' '..Comms.nameOf(speaker,game)
  local n=ch.script.notice
  require('src.notify').post(game.universe,{kind='comms',title=(n and n.title or 'Incoming hail: ')..who,
   text=n and n.text or 'Press C to answer',key='comms:'..ch.id})
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
 Comms.restorePending(game)
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
   elseif Comms.node(ch).tick and Comms.node(ch).tick(ch) then
    Comms.go(ch,Comms.node(ch).tick(ch))
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

-- Drop every open conversation (a map change or a load). keepPending
-- leaves the ones a load is waiting to restore.
function Comms.reset(keepPending)
 for i=#Comms.channels,1,-1 do Comms.close(Comms.channels[i],'reset') end
 Comms.channels={}
 if not keepPending then Comms.pending=nil end
end

-- Saving. A conversation is saved by who is in it (the player, or an A-Life
-- record id), its script, node, time left and variables. A script with
-- live references in ch.v gives save(ch) -> plain table and restore(game,
-- ch, saved) -> false to give up; otherwise ch.v is saved as it is.
-- Loading keeps them pending until both ships are on the map again (the
-- A-Life ships come online over the first moments), then reopens them
-- without re-running the node's enter.
local function idOf(e) return e.isPlayer and 'player' or e.alifeId end
local function find(game,id)
 if id=='player' then return game.player end
 return game.alifeOnline and game.alifeOnline[id]
end
Comms.T.restoreWait=15
function Comms.capture(game)
 local out={}
 for _,ch in ipairs(Comms.channels) do
  local a,b=idOf(ch.speaker),idOf(ch.listener)
  if a and b and not ch.endAt then
   local v=ch.script.save and ch.script.save(ch) or require('src.persistence').copy(ch.v)
   out[#out+1]={script=ch.scriptId,node=ch.node,speaker=a,listener=b,v=v,log=require('src.persistence').copy(ch.log),
    left=Comms.remaining(ch),field=game.fieldId}
  end
 end
 for _,saved in ipairs(Comms.pending or {}) do out[#out+1]=saved end
 game.universe.comms=#out>0 and out or nil
end
function Comms.load(game)
 local u=game.universe
 Comms.pending=u.comms;u.comms=nil
 Comms.pendingUntil=nil
end
function Comms.restorePending(game)
 if not Comms.pending then return end
 Comms.pendingUntil=Comms.pendingUntil or game.time+Comms.T.restoreWait
 local keep={}
 for _,saved in ipairs(Comms.pending) do
  local a,b=find(game,saved.speaker),find(game,saved.listener)
  if saved.field~=game.fieldId then
   -- a different map: drop it
  elseif a and b and not gone(a) and not gone(b) then
   local ch=attach(game,saved.script,a,b,saved.v)
   ch.node,ch.log,ch.enteredAt=saved.node,saved.log or {},game.time
   ch.deadline=saved.left and game.time+saved.left or nil
   if ch.script.restore and ch.script.restore(game,ch,saved.v)==false then Comms.close(ch,'lost contact') end
  elseif game.time<Comms.pendingUntil then keep[#keep+1]=saved end
 end
 Comms.pending=#keep>0 and keep or nil
end

return Comms
