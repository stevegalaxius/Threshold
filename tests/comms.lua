-- Comms (src/comms.lua): scripts, tokens, options, timeouts and NPC
-- answers; the robbery and inspection scripts on the real player ship.
return function(game)
 local Comms=require('src.comms')
 local T=require('src.tuning')
 local Rep=require('src.reputation')
 Comms.reset()
 local function ship(name) return {kind='ship',def={name=name},cargo={}} end
 -- 1. a toy script: tokens, show/enabled, pick, timeout, endings
 Comms.register('test_toy',{start='a',nodes={
  a={text='{speaker.name} to {listener.name}: {offer}?',timeout=5,onTimeout='late',
   options={{'Yes',go='b'},{'Hidden',show=function() return false end},{'Greyed',enabled=function() return false end},
    {'Stay',pick=function(ch) ch.v.stayed=true;return false end}}},
  b={text='done',enter=function(ch) ch.v.entered=true end},
  late={text='too late'},
 }})
 local a,b=ship('Alpha'),ship('Bravo')
 local ch=Comms.open(game,'test_toy',a,b,{offer='tea'})
 assert(ch.log[1].text=='Alpha to Bravo: tea?','tokens: '..ch.log[1].text)
 local opts=Comms.options(ch)
 assert(#opts==3 and opts[2].label=='Greyed' and not opts[2].enabled,'show/enabled filtering')
 Comms.choose(ch,2);assert(ch.node=='a','a greyed option was chosen')
 Comms.choose(ch,3);assert(ch.node=='a' and ch.v.stayed,'pick returning false should stay')
 Comms.choose(ch,1);assert(ch.node=='b' and ch.v.entered and ch.endAt,'go/enter/ending')
 game.time=game.time+Comms.T.endingLinger+.1;Comms.update(game)
 assert(ch.closed and not a.comms and not b.comms,'ending did not close the channel')
 ch=Comms.open(game,'test_toy',a,b,{offer='tea'})
 game.time=game.time+6;Comms.update(game)
 assert(ch.node=='late','timeout did not fire')
 -- extensions add options without touching the script (quests' hook)
 Comms.extend('test_toy','a',function(_,list) list[#list+1]={'Quest',go='b'} end)
 ch=Comms.open(game,'test_toy',a,b,{offer='tea'})
 local labels={};for _,o in ipairs(Comms.options(ch)) do labels[#labels+1]=o.label end
 assert(labels[#labels]=='Quest','extension option missing')
 a.dead=true;Comms.update(game);assert(ch.closed,'a dead speaker kept the channel open')
 Comms.extensions['test_toy/a']=nil
 -- 2. robbery: the NPC side answers through the script's npc rule
 local R=require('src.robbery')
 local pirate,victim=ship('Pirate'),ship('Hauler')
 local d=require('src.handover').open(game,'robbery',pirate,victim,4,T.robberyWindow,function() return true end)
 d.answered=true                                   -- skip the odds roll: script path only
 d.channel=Comms.open(game,'robbery',pirate,victim,{request=d,amount=4})
 assert(d.channel.v.owed==4 and d.channel.log[1].text:find('jettison 4'),'robbery demand text')
 Comms.choose(d.channel,#Comms.options(d.channel))
 assert(d.refused and victim.aggressor==pirate and d.channel.node=='refused','NPC refusal')
 -- haggle: a success cuts the demand, a failure halves the time left
 local real=math.random
 math.random=function() return 0 end
 local d2={amount=10,paid=0,deadline=game.time+20}
 assert(R.haggle(game,d2) and d2.amount==6,'haggle success')
 math.random=function() return .99 end
 local d3={amount=10,paid=0,deadline=game.time+20}
 assert(not R.haggle(game,d3) and math.abs(d3.deadline-game.time-10)<1e-6,'haggle failure')
 -- 3. inspection on the player's real hold
 local p=game.player
 local Hold=require('src.inventory.hold')
 assert(Hold.add(p.hold,'fentanyl',5)==5 or (p.cargo and true),'could not load test cargo')
 p.cargo=Hold.totals(p.hold)
 local u=game.universe
 u.credits=10000
 local Con=require('src.contraband')
 assert(Con.inspects(u,'estates') and not Con.inspects(u,'jove'),'who inspects')
 local police=ship('Patrol')
 local before=Rep.standing(u,'estates')
 math.random=function() return 0 end
 ch=Con.inspect(game,police,p,'estates')
 assert(ch.v.units==5 and ch.v.value==5*900,'manifest')
 Comms.choose(ch,1)                                -- Comply
 math.random=real
 assert(ch.node=='caught' and (Hold.totals(p.hold).fentanyl or 0)==0,'contraband not seized')
 assert(u.credits==10000-4500 and Rep.standing(u,'estates')<before,'fine or standing')
 Comms.close(ch)
 -- running: wanted until it lapses
 ch=Con.inspect(game,police,p,'estates')
 Comms.choose(ch,#Comms.options(ch))
 assert(ch.node=='ran' and Con.wanted(u,'estates') and police.aggressor==p,'running')
 u.clock=u.clock+T.wantedTime+1;Con.prune(u)
 assert(not Con.wanted(u,'estates'),'wanted did not lapse')
 Comms.reset()
 print('ok  comms: scripts, tokens, timeouts, extensions, robbery and inspection')
end
