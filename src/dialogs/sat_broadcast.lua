--[[
	A broadcast satellite's hail (src/satellites.lua, Sat.broadcast): a
	satellite calls out to the passing player on its frequency and, if they
	tune in, plays its owner's paper: headlines, the area's price watch,
	station idents (Sat.broadcastItems). It's one-way: the player listens,
	skips on, tunes out, or jams it.

	ch.v (set by Sat.broadcast):
	  sat       the satellite's id (its record: Sat.get)
	  satName, area, owner, freq   for the text
	  items     { text, kind } to play, kind 'news' | 'market' | 'ident'
	  idx       the item playing now (0 before the first)

	The speaker is the satellite's husk, so the channel drops if it's shot
	down (Comms.update: lost contact); flying out of range fades it out.

	Jamming is free to do but not unseen: the owner loses a little standing
	with the player and the satellite stays silent for Sat.jamQuiet.
]]
local T=require('src.tuning')

local KIND={news='NEWS',market='MARKET',ident='STATION'}

local function Sat() return require('src.satellites') end
local function item(ch) return ch.v.items[ch.v.idx] end
local function more(ch) return ch.v.idx<#ch.v.items end

-- Out of reach: the speaker's husk farther than twice the hail range.
local function outOfRange(ch)
 local a,b=ch.speaker.body,ch.listener.body
 if not a or not b or a:isDestroyed() or b:isDestroyed() then return false end
 local ax,ay=a:getPosition();local bx,by=b:getPosition()
 local R=Sat().broadcastRange*2
 return (ax-bx)^2+(ay-by)^2>R*R
end
local function fading(ch) if outOfRange(ch) then return 'faded' end end

local function jam(ch) return 'jam' end
local function canJam(ch) return Sat().faction(Sat().get(ch.game.universe,ch.v.sat))~=nil end

return {
 start='hail',
 notice={title='Broadcast: ',text='Press C to tune in',chip='BCAST',verb='tune in'},
 nodes={
  hail={
   text='"{satName}, broadcasting for {owner} on {freq} MHz. All vessels in {area}, tune in for traffic and market news."',
   timeout=T.inspectWindow,onTimeout='ignored',
   tick=fading,
   options={
    {'Tune in',pick=function(ch) ch.v.idx=1;return 'play' end},
    {'Jam the signal',show=canJam,pick=jam},
    {'Tune out',go='tuned_out'},
   },
  },

  -- One item a visit: the node re-enters itself for the next.
  play={
   hold=true,
   tick=fading,
   text=function(ch)
    local it=item(ch)
    if not it then return '"Nothing further on this frequency."' end
    return ('[%s] %s'):format(KIND[it.kind] or 'BULLETIN',it.text)
   end,
   options=function(ch)
    local nxt=ch.v.items[ch.v.idx+1]
    local opts={}
    if nxt then
     opts[#opts+1]={'Next: '..(KIND[nxt.kind] or 'bulletin'):lower(),pick=function(ch) ch.v.idx=ch.v.idx+1;return 'play' end}
    else
     opts[#opts+1]={'End of bulletin',go='signoff'}
    end
    opts[#opts+1]={'Tune out',go='tuned_out'}
    if canJam(ch) then opts[#opts+1]={'Jam the signal',pick=jam} end
    return opts
   end,
  },

  jam={
   enter=function(ch)
    local u=ch.game.universe
    local r=Sat().get(u,ch.v.sat)
    local f=Sat().faction(r)
    if r then r.jammedAt=u.clock or 0 end
    if f then require('src.reputation').addStanding(u,f,-2) end
   end,
   text='"-- carrier lost --" The {owner} channel dissolves into static. Someone will have logged that.',
  },
  ignored={text='"{satName}, standing by on {freq}."'},
  tuned_out={text='You tune out. {satName} keeps broadcasting to the empty lanes.'},
  signoff={text='"That is all from {satName}. {owner}: safe lanes, open markets."'},
  faded={text='"...{freq}... ...k-- ..." The signal fades as you leave range.'},
 },
}
