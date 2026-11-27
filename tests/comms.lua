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
 assert(ch.node=='scanning','comply should start a scan')
 game.time=game.time+T.inspectScanTime*2+.1;Comms.update(game)
 math.random=real
 assert(ch.node=='caught' and (Hold.totals(p.hold).fentanyl or 0)==0,'contraband not seized')
 assert(u.credits==10000-4500 and Rep.standing(u,'estates')<before,'fine or standing')
 Comms.close(ch)
 -- dumping during an inspection counts as found, and the patrol scoops it up
 Hold.add(p.hold,'fentanyl',2);p.cargo=Hold.totals(p.hold)
 ch=Con.inspect(game,police,p,'estates')
 local pickups=#game.pickups
 require('src.inventory.hold').take(p.hold,'fentanyl',2);p.cargo=Hold.totals(p.hold)
 game:eject(p,'fentanyl',2)
 assert(#game.pickups==pickups and ch.v.dumpedValue==1800,'dumped contraband was not scooped')
 local credits=u.credits
 Comms.choose(ch,1);game.time=game.time+T.inspectScanTime*2+.1;Comms.update(game)
 assert(ch.node=='caught' and u.credits==credits-1800,'dumped contraband was not fined')
 Comms.close(ch)
 -- complying and then flying off is running
 local px,py=p.body:getPosition()
 police.body={getPosition=function() return px,py end}
 ch=Con.inspect(game,police,p,'estates')
 Comms.choose(ch,1)
 police.body={getPosition=function() return px+T.inspectLeash+100,py end}
 Comms.update(game)
 assert(ch.node=='ran' and Con.wanted(u,'estates'),'leaving mid-scan was not running')
 u.contraband.wanted={};police.body=nil;police.aggressor=nil
 -- a pirate's demand takes over an inspection: the patrol goes for the pirate
 ch=Con.inspect(game,police,p,'estates')
 local raider=ship('Pirate')
 local d4=require('src.handover').open(game,'robbery',raider,p,1,T.robberyWindow,function() return true end)
 d4.channel=Comms.open(game,'robbery',raider,p,{request=d4,amount=1})
 assert(ch.closed and police.aggressor==raider and p.comms==d4.channel,'police did not turn on the pirate')
 -- save and restore: the demand comes back on the same ships
 raider.alifeId='npc/test';game.alifeOnline=game.alifeOnline or {};game.alifeOnline['npc/test']=raider
 Comms.capture(game)
 assert(u.comms and #u.comms==1 and u.comms[1].speaker=='npc/test','capture')
 require('src.handover').close(d4);Comms.reset()
 Comms.load(game);Comms.update(game)
 local back=p.comms
 assert(back and back.scriptId=='robbery' and back.speaker==raider and raider.request and raider.request.channel==back,'restore')
 require('src.handover').close(raider.request);Comms.reset();game.alifeOnline['npc/test']=nil
 -- packed containers: counted when the scan has depth, seized from inside
 local bigHold=Hold.new({{key='main',name='Main',w=12,h=12}})
 local inner=Hold.new({{key='main',name='Box',w=4,h=4}})
 Hold.add(inner,'fentanyl',3)
 assert(Hold.placeStack(bigHold,{id='cargo_container',n=1,inner=inner}),'could not pack the container')
 local smuggler={kind='ship',hold=bigHold,cargo=Hold.totals(bigHold),hull=p.hull,loadout={},stats=p.stats}
 local _,shallow=Con.manifest(u,'estates',smuggler,false)
 local deepList,deep=Con.manifest(u,'estates',smuggler,true)
 assert(shallow==0 and deep==3 and deepList[1].packed,'packed contraband: shallow '..shallow..' deep '..deep)
 Con.seize(smuggler,deepList)
 assert((Hold.totals(inner).fentanyl or 0)==0,'packed contraband not seized')
 -- a dumped container full of it is found and taken whole
 local box=Hold.new({{key='main',name='Box',w=4,h=4}});Hold.add(box,'amphetamines',4)
 ch=Con.inspect(game,police,p,'estates')
 local before=#game.entities
 game:eject(p,'cargo_container',1,box)
 assert(#game.entities==before and ch.v.dumped and ch.v.dumped[1].id=='amphetamines','dumped container not seized')
 Comms.close(ch)
 -- the Deep Scanner is how a patrol scans: without one it looks by eye
 assert(not Con.method(game,police).scanner and Con.method(game,{loadout={'scanner'},hull={slots={{}}}}).deep,'scan method')
 -- running: wanted until it lapses
 ch=Con.inspect(game,police,p,'estates')
 Comms.choose(ch,#Comms.options(ch))
 assert(ch.node=='ran' and Con.wanted(u,'estates') and police.aggressor==p,'running')
 u.clock=u.clock+T.wantedTime+1;Con.prune(u)
 assert(not Con.wanted(u,'estates'),'wanted did not lapse')
 Comms.reset()
 print('ok  comms: scripts, tokens, timeouts, extensions, robbery and inspection')
end
