-- A police cargo inspection (src/contraband.lua opens it and owns the
-- rules). ch.v: faction, list/units/value (what's illegal aboard), bribe,
-- dumped/dumpedValue (contraband thrown out during the inspection).
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
-- Leaving scan range before it's over is running, whatever was said.
local function leash(ch) if not Con().inRange(ch) then return 'fled' end end
-- Everything illegal that's still aboard, merged with what was dumped.
local function found(ch)
 local list,n,value=Con().manifest(u(ch),ch.v.faction,ch.listener)
 return list,n,value
end
return {
 start='hail',
 -- a pirate's demand takes over: the patrol goes after the pirate
 onClose=function(ch,why,by)
  if why=='replaced' and by and by.scriptId=='robbery' and by.listener==ch.listener then
   ch.speaker.aggressor=by.speaker
   if ch.listener.isPlayer then ch.game:toast('PATROL ENGAGING PIRATES',2) end
  end
 end,
 nodes={
  hail={
   text='"{speaker.faction} patrol. {listener.name}, hold position for a cargo scan."',
   timeout=T.inspectWindow, onTimeout='ignored', tick=leash,
   npc=function(ch) return 1 end,
   options={
    { "Comply", go='scanning' },
    { "Offer {bribe} cr", show=function(ch) return (u(ch).credits or 0)>=ch.v.bribe end, pick=function(ch)
      local chance=T.bribeChance[ch.v.faction] or .3
      if math.random()<chance and not ch.v.dumped then Con().charge(u(ch),ch.v.bribe);return 'waved' end
      Rep().addStanding(u(ch),ch.v.faction,-T.bribeStanding)
      return 'bribeRefused'
     end },
    { "Run", pick=run },
   } },
  scanning={
   text='"Scanning. Hold position."',
   timeout=T.inspectScanTime, onTimeout='scan', tick=leash, hold=true,
   options={ { "Run", pick=run } } },
  scan={
   enter=function(ch)
    local list,n,value=found(ch)
    ch.v.list,ch.v.units,ch.v.value=list,n,value
    if ch.v.dumped or n>0 and math.random()<T.inspectDetect then return 'caught' end
    return 'clean'
   end },
  caught={
   enter=function(ch)
    local all={}
    for _,s in ipairs(ch.v.list) do all[#all+1]=s end
    for _,s in ipairs(ch.v.dumped or {}) do all[#all+1]=s end
    ch.v.seized=Con().describe(all)
    Con().seize(ch.listener,ch.v.list)
    ch.v.fine=Con().charge(u(ch),(ch.v.value+(ch.v.dumpedValue or 0))*T.inspectFine)
    Rep().addStanding(u(ch),ch.v.faction,-T.inspectStanding)
   end,
   text='"Contraband: {seized}. Seized. Fine of {fine} cr assessed."' },
  clean={ text='"Scan clear. Safe travels."' },
  waved={ text='"...Scanner must be on the blink. Move along."' },
  bribeRefused={
   text='"Attempted bribery is noted. Scanning now."',
   timeout=T.inspectScanTime, onTimeout='scan', tick=leash, hold=true,
   options={ { "Run", pick=run } } },
  ran={ text='"All units: {listener.name} is running from inspection."' },
  fled={ enter=run },
  ignored={ enter=run },
 },
}
