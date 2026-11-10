-- Decision trace: why each persistent NPC did what it did.
-- Any module that changes an NPC's mind writes one line here, on the record
-- itself (so it survives going online/offline and save/load). The F6
-- inspector reads it. Keep lines short: "<why> -> <what>".
local Tr={}
local LIMIT=40
-- r: the record (or a live entity with alifeRecord/alifeId and game).
function Tr.note(r,clock,source,text)
 if not r then return end
 local t=r.trace;if not t then t={};r.trace=t end
 local last=t[#t]
 if last and last.source==source and last.text==text then last.n=(last.n or 1)+1;last.clock=clock;return end
 t[#t+1]={clock=clock,source=source,text=text}
 while #t>LIMIT do table.remove(t,1) end
end
-- For an online entity: its record and the clock.
function Tr.entity(game,e,source,text)
 local r=e and e.alifeId and game.universe.npcs[e.alifeId]
 if r then Tr.note(r,game.universe.clock,source,text) end
end
-- Who is driving this record right now (the first that claims it wins).
function Tr.controller(game,r,e)
 if r.state=='dead' or r.state=='escaped' then return r.state end
 if r.fuelStatus=='stranded' then return 'distress (stranded)' end
 if r.encounter then return 'encounter vs '..r.encounter.target end
 if e and e.asked then return 'handover: giving to '..tostring(e.asked.asker.alifeId or 'player')..' ('..e.asked.kind..')' end
 if e and e.request then return 'handover: asking '..tostring(e.request.giver.alifeId or 'player')..' ('..e.request.kind..')' end
 if r.service then return 'upkeep: '..r.service.need..' at '..r.service.station end
 if r.worldRecovery then return 'world recovery' end
 if r.piracy then return 'piracy: '..r.piracy.phase end
 if r.action then return 'action: '..r.action.kind..(r.action.operation and ':'..r.action.operation or '')..(r.action.pausedAt and ' (paused)' or '') end
 return r.task and ('job: '..r.task.kind) or 'looking for work: '..(r.workProfile or r.label or '?')
end
return Tr
