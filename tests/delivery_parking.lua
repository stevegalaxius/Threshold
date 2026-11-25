return function()
 local ShipDelivery,Tasks=require('src.ship_delivery'),require('src.tasks')
 local Dealer,Parking=require('src.dealers'),require('src.dealer_parking')
 local source,target='station:belt_2','station:ring_1'
 local u={clock=0,npcs={},stations={},dealers={
  [source]={lots={},serial=0},
  [target]={lots={},serial=20},
 }}
 local def=Tasks.definitions.ship_delivery
 local function offer()
  local stock,spec=Dealer.state(u,source)
  local lot=Dealer.roll(spec,stock,'mack_mustang')
  stock.lots[#stock.lots+1]=lot
  return Tasks.post(u,{kind='ship_delivery',source=source,target=target,hull=lot.hull,lot=lot.id,price=lot.price})
 end
 local function assign(o,id,station)
  local carrier={id=id,ship={hull='mack_longhorn_carrier',carried={}}}
  local task=require('src.persistence').copy(o)
  if def.prepare(u,carrier,task,station,u.clock) then
   u.npcs[id]=carrier;carrier.task=task
   o.owner,o.state=id,'reserved'
  end
  return carrier
 end
 local first=offer()
 local a=assign(first,'npc/delivery-first',target)
 assert(a.task and first.parking and not first.loaded,'outbound carrier did not reserve destination space')
 local saved=require('src.persistence').copy(u)
 assert(#Parking.claims(saved,target)==1,'saved delivery lost its berth claim')
 local spare=Parking.plan(u,target,first.hull,1,'outside')[1]
 assert(spare and (not spare.mooring or spare.mooring~=first.parking.mooring),
  'unrelated parking reused a delivery claim')
 Tasks.release(u,a,'test cancellation',u.clock)
 assert(#Parking.claims(u,target)==0 and Dealer.find(u,source,first.lot),'cancelled pickup lost the hull or retained parking')

 local b=assign(first,'npc/delivery-second',source)
 assert(b.task and first.loaded and first.parking,'pickup proceeded without a destination claim')
 local claim=first.parking
 assert(Tasks.arrive(u,b,target,u.clock),'carrier could not unload into its reserved space')
 local lot=Dealer.state(u,target).lots[1]
 assert(lot and lot.id==21 and lot.mooring==claim.mooring and
  (not claim.bay or lot.bay.x==claim.bay.x and lot.bay.y==claim.bay.y),'unloaded hull lost its assigned space')
 assert(#Parking.claims(u,target)==0,'settled delivery retained parking')
 assert(ShipDelivery.pending(u,target)==nil,'settled delivery remained on the board')

 local blocked=offer()
 local stock,spec=Dealer.state(u,target)
 for _=#stock.lots+1,spec.lots do stock.lots[#stock.lots+1]={hull=blocked.hull} end
 local c=assign(blocked,'npc/delivery-blocked',source)
 assert(not c.task and not blocked.parking and Dealer.find(u,source,blocked.lot),
  'carrier collected a hull for a full destination')
 -- Player orders also occupy real destination space before departure.
 local playerLot=Dealer.find(u,source,blocked.lot)
 Tasks.state(u).offers[blocked.id]=nil
 stock.lots={lot}
 u.credits=1e9
 u.npcs['npc/available-carrier']={state='idle',node=source,workProfile='ship_hauler',
  ship={hull='mack_longhorn_carrier'}}
 local order=assert(ShipDelivery.orderPlayer(u,{source=source,target=target,
  lot=playerLot.id,hull=playerLot.hull,price=playerLot.price}))
 assert(#Parking.claims(u,target)==1 and playerLot.playerDelivery==order.id,'player order did not claim parking')
 assert(ShipDelivery.cancelPlayer(u,order.id) and #Parking.claims(u,target)==0 and not playerLot.playerDelivery,
  'cancelled player order retained its parking or source lot reservation')
 local lost=offer()
 local carrier=assign(lost,'npc/delivery-lost',source)
 assert(carrier.task and lost.loaded and lost.parking,'missing claim on loaded hull')
 carrier.state='dead'
 Tasks.release(u,carrier,'dead',u.clock)
 assert(not Tasks.state(u).offers[lost.id] and #Parking.claims(u,target)==0,
  'carrier loss kept a parking claim or reposted the collected hull')
 print('ok  delivery parking: reservation, cancellation, settlement and full destination')
end
