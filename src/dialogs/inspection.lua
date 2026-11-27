-- A police cargo inspection (src/contraband.lua opens it and owns the
-- rules). ch.v: faction, list/units/value (what's illegal aboard), bribe.
local T=require('src.tuning')
local function Con() return require('src.contraband') end
local function Rep() return require('src.reputation') end
local function u(ch) return ch.game.universe end
local function run(ch)
 Con().flag(u(ch),ch.v.faction)
 Rep().addStanding(u(ch),ch.v.faction,-T.inspectRunStanding)
 ch.speaker.aggressor=ch.listener
 return 'ran'
end
return {
 start='hail',
 nodes={
  hail={
   text='"{speaker.faction} patrol. {listener.name}, hold position for a cargo scan."',
   timeout=T.inspectWindow, onTimeout='ignored',
   npc=function(ch) return 1 end,
   options={
    { "Comply", go='scan' },
    { "Offer {bribe} cr", show=function(ch) return (u(ch).credits or 0)>=ch.v.bribe end, pick=function(ch)
      local chance=T.bribeChance[ch.v.faction] or .3
      if math.random()<chance then Con().charge(u(ch),ch.v.bribe);return 'waved' end
      Rep().addStanding(u(ch),ch.v.faction,-T.bribeStanding)
      return 'bribeRefused'
     end },
    { "Run", pick=run },
   } },
  scan={
   enter=function(ch)
    if ch.v.units>0 and math.random()<T.inspectDetect then return 'caught' end
    return 'clean'
   end },
  caught={
   enter=function(ch)
    ch.v.seized=Con().describe(ch.v.list)
    Con().seize(ch.listener,ch.v.list)
    ch.v.fine=Con().charge(u(ch),ch.v.value*T.inspectFine)
    Rep().addStanding(u(ch),ch.v.faction,-T.inspectStanding)
   end,
   text='"Contraband: {seized}. Seized. Fine of {fine} cr assessed."' },
  clean={ text='"Scan clear. Safe travels."' },
  waved={ text='"...Scanner must be on the blink. Move along."' },
  bribeRefused={
   text='"Attempted bribery is noted. Scanning now."',
   timeout=8, onTimeout='scan',
   options={ { "Continue", go='scan' }, { "Run", pick=run } } },
  ran={ text='"All units: {listener.name} is running from inspection."' },
  ignored={ enter=run },
 },
}
