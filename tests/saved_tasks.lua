return function()
 local Tasks,Save=require('src.tasks'),require('src.save')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local kind='saved-task-regression'
 local r={id='saved-worker',role='trader',state='docked',taskStatus='delivering cargo',
  ship={cargo={scrap=5}},task={id='task/1',kind=kind,phase='delivery',source='origin',target='destination'}}
 local u={npcs={[r.id]=r},tasks={nextId=1,offers={['task/1']={id='task/1',kind=kind,owner=r.id,state='reserved'}}}}
 check(Tasks.arrive(u,r,'destination',1)==false,'unknown task did not suspend safely at arrival')
 check(not r.task and r.suspendedTask.phase=='delivery' and r.ship.cargo.scrap==5,'suspension discarded phase or cargo')
 check(not Tasks.choose(u,r,'destination',2),'unsupported work was replaced by another task')
 Tasks.clean(u,2)
 check(u.tasks.offers['task/1'].owner==r.id,'cleanup released a suspended live reservation')
 local saved=assert(Save.decode(Save.encode(u)));r=saved.npcs[r.id]
 check(r.suspendedTask.kind==kind and r.ship.cargo.scrap==5,'save/load lost suspended work')
 Tasks.register(kind,{
  roles={trader=true},eligible=function()return true end,
  prepare=function()error('resuming a loaded job must not load another shipment')end,
  complete=function(world,worker,t,node)
   if node~=t.target then return false end
   world.delivered=(world.delivered or 0)+worker.ship.cargo.scrap;worker.ship.cargo.scrap=0
   return true
  end,
 })
 local task=Tasks.choose(saved,r,'destination',3)
 check(task and task.phase=='delivery' and not r.suspendedTask and r.taskStatus=='delivering cargo',
  'restoring support did not resume the existing phase and activity')
 check(Tasks.arrive(saved,r,'destination',3) and saved.delivered==5 and not saved.tasks.offers['task/1'].owner,
  'restored task did not deliver once and release its reservation')
 Tasks.arrive(saved,r,'destination',4)
 check(saved.delivered==5,'repeated arrival delivered suspended cargo twice')
 local dead=assert(Save.decode(Save.encode(u)));dead.npcs['saved-worker'].state='dead'
 Tasks.clean(dead,5)
 check(not dead.tasks.offers['task/1'].owner and not dead.npcs['saved-worker'].task,'dead suspended worker resumed or retained its reservation')
 Tasks.definitions[kind]=nil
 print(('SAVED TASK COMPATIBILITY TEST PASSED (%d checks)'):format(checks))
end
