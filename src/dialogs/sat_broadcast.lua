-- Broadcast satellite dialog (src/dialogs/sat_broadcast.lua): a satellite
-- hails passing ships with propaganda, market alerts, or crisis warnings.
--
-- ch.v carries the satellite record and its configured messages:
--   ch.v.sat       the satellite record (Sat.get)
--   ch.v.freq      the broadcast frequency number
--   ch.v.msgs      table of { text, type } message entries. type is one of:
--                    'propaganda' (faction loyalty), 'market' (price/trade),
--                    'crisis' (raids, blockades, alerts).
--   ch.v.idx       current message index (1-based)
--
-- The satellite "speaks" through {speaker.name} and {speaker.faction} tokens
-- resolved from the satellite record and its planet's controller.

local T = require('src.tuning')

-- Cycle through messages: go to the next one, or end when we've shown them all.
local function nextMsg(ch)
 ch.v.idx = ch.v.idx + 1
 if ch.v.idx <= #ch.v.msgs then return ch.v.idx end
 return 'end'
end

-- Whether to show the jam option: only if the satellite is still working.
local function jamShown(ch)
 local Sat = require('src.satellites')
 local r = ch.v.sat
 return r and not r.lost
end

return {
 start = 'hail',
 nodes = {
  -- Opening hail: satellite announces itself.
  hail = {
   text = '"Broadcast satellite {sat.name} on frequency {freq}. All local vessels are advised to monitor this channel."',
   timeout = T.inspectWindow,
   onTimeout = 'ignored',
   tick = function(ch)
    -- Close if the satellite husk was shot off the map.
    local Sat = require('src.satellites')
    local e = ch.v.satEntity
    if e and (e.removed or e.dead or (e.body and e.body:isDestroyed())) then
     ch.v.channelLost = true
     return 'lost'
    end
   end,
   npc = function(ch) return 2 end,
   options = {
    { "Listen", go = 'msg_1' },
    { "Jam signal", show = jamShown, pick = function(ch) return 'jam' end },
    { "Ignore" },
   },
  },

  -- Individual message nodes: each shows one message and offers next/end/jam.
  -- The type label (propaganda, market, crisis) is stored in ch.v.msgs[idx].type
  -- and shown in the "Next message" label so the player can skip what they don't want.
  msg_1 = {
   hold = true,
   tick = function(ch)
    if ch.v.channelLost then return 'lost' end
   end,
   options = function(ch)
    local m = ch.v.msgs and ch.v.msgs[ch.v.idx]
    local typeLabel = m and m.type and (' [' .. m.type:upper() .. ']') or ''
    local nextLabel = ch.v.idx < #ch.v.msgs and ('Next message' .. typeLabel) or 'End transmission'
    local opts = {
     { nextLabel, show = function() return ch.v.idx < #ch.v.msgs end, pick = function(ch) return nextMsg(ch) end },
     { "End transmission", pick = function(ch) return ch.v.idx < #ch.v.msgs and 'msg_' .. ch.v.idx or 'end' end },
    }
    if jamShown(ch) then opts[#opts + 1] = { "Jam signal", pick = function(ch) return 'jam' end } end
    return opts
   end,
  },
  msg_2 = {
   hold = true,
   tick = function(ch)
    if ch.v.channelLost then return 'lost' end
   end,
   options = function(ch)
    local m = ch.v.msgs and ch.v.msgs[ch.v.idx]
    local typeLabel = m and m.type and (' [' .. m.type:upper() .. ']') or ''
    local nextLabel = ch.v.idx < #ch.v.msgs and ('Next message' .. typeLabel) or 'End transmission'
    local opts = {
     { nextLabel, show = function() return ch.v.idx < #ch.v.msgs end, pick = function(ch) return nextMsg(ch) end },
     { "End transmission", pick = function(ch) return ch.v.idx < #ch.v.msgs and 'msg_' .. ch.v.idx or 'end' end },
    }
    if jamShown(ch) then opts[#opts + 1] = { "Jam signal", pick = function(ch) return 'jam' end } end
    return opts
   end,
  },
  msg_3 = {
   hold = true,
   tick = function(ch)
    if ch.v.channelLost then return 'lost' end
   end,
   options = function(ch)
    local m = ch.v.msgs and ch.v.msgs[ch.v.idx]
    local typeLabel = m and m.type and (' [' .. m.type:upper() .. ']') or ''
    local nextLabel = ch.v.idx < #ch.v.msgs and ('Next message' .. typeLabel) or 'End transmission'
    local opts = {
     { nextLabel, show = function() return ch.v.idx < #ch.v.msgs end, pick = function(ch) return nextMsg(ch) end },
     { "End transmission", pick = function(ch) return ch.v.idx < #ch.v.msgs and 'msg_' .. ch.v.idx or 'end' end },
    }
    if jamShown(ch) then opts[#opts + 1] = { "Jam signal", pick = function(ch) return 'jam' end } end
    return opts
   end,
  },
  msg_4 = {
   hold = true,
   tick = function(ch)
    if ch.v.channelLost then return 'lost' end
   end,
   options = function(ch)
    local m = ch.v.msgs and ch.v.msgs[ch.v.idx]
    local typeLabel = m and m.type and (' [' .. m.type:upper() .. ']') or ''
    local nextLabel = ch.v.idx < #ch.v.msgs and ('Next message' .. typeLabel) or 'End transmission'
    local opts = {
     { nextLabel, show = function() return ch.v.idx < #ch.v.msgs end, pick = function(ch) return nextMsg(ch) end },
     { "End transmission", pick = function(ch) return ch.v.idx < #ch.v.msgs and 'msg_' .. ch.v.idx or 'end' end },
    }
    if jamShown(ch) then opts[#opts + 1] = { "Jam signal", pick = function(ch) return 'jam' end } end
    return opts
   end,
  },

  -- Player jams the signal: standing penalty with the satellite's faction,
  -- the satellite logs the interference and cuts the channel.
  jam = {
   text = '"Unauthorized jamming detected. Incident logged. This channel is monitored."',
   tick = function(ch)
    local Rep = require('src.reputation')
    local Sat = require('src.satellites')
    local r = ch.v.sat
    local f = Sat.faction(r)
    if f then Rep.addStanding(ch.game.universe, f, -5) end
    if ch.listener.isPlayer then
     ch.game:toast('SIGNAL JAMMED', 2)
    end
   end,
   options = { { 'Acknowledged' } },
  },

  -- Player ignored the hail: channel closes quietly.
  ignored = { text = '"...Channel closing."' },

  -- Satellite was destroyed: cuts to static.
  lost = {
   text = '"...[SIGNAL LOST — carrier wave disrupted]..."',
   tick = function(ch)
    if ch.listener.isPlayer then
     ch.game:toast('BROADCAST SATELLITE DESTROYED', 2)
    end
   end,
   options = { { 'Channel closed' } },
  },

 -- Ending: the broadcast finishes naturally.
  ['end'] = { text = '"End of transmission. Broadcast satellite {sat.name}, standing by."' },
 },
}
