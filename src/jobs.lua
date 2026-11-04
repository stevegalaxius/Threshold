-- Mars smart terrains: finite mining output and reserved hauling work.
local J={}
local Fields=require('src.fields')
local L=require('src.locations')
local data=require('src.data')
local MINES={'phobos','deimos'}
function J.state(u,clock)
 u.jobs=u.jobs or {mines={},delivered={}}
 for _,area in ipairs(MINES) do
  local m=u.jobs.mines[area]
  if not m then m={stock=20,clock=clock,reservations={}};u.jobs.mines[area]=m end
  m.stock=math.min(80,m.stock+math.max(0,clock-m.clock)/12)
  m.clock=math.max(clock,m.clock)
  for id in pairs(m.reservations) do
   local r=u.npcs[id]
   if not r or r.state=='dead' or r.state=='escaped' or not r.job or r.job.mine~=area then m.reservations[id]=nil end
  end
 end
 return u.jobs
end
local function capacity(r)
 local used=0
 for id,n in pairs(r.ship.cargo or {}) do used=used+(data.items[id].volume or 1)*n end
 return math.max(0,math.floor((data.hulls[r.ship.hull].hold or 0)-used))
end
-- Called exactly once at a completed docking stay, online or offline.
function J.depart(u,r,station,clock)
 local state=J.state(u,clock)
 local job=r.job
 if job and station==L.station(job.mine,'trade') and job.phase=='pickup' then
  local m=state.mines[job.mine]
  local amount=math.min(job.amount,math.floor(m.stock),capacity(r))
  m.stock=m.stock-amount;m.reservations[r.id]=nil
  r.ship.cargo=r.ship.cargo or {};r.ship.cargo.martian_ore=(r.ship.cargo.martian_ore or 0)+amount
  job.amount,job.phase=amount,'delivery'
  return true
 end
 if job and station==job.home and job.phase=='delivery' then
  local cargo=r.ship.cargo or {}
  local amount=math.min(job.amount,cargo.martian_ore or 0)
  cargo.martian_ore=(cargo.martian_ore or 0)-amount
  state.delivered[station]=(state.delivered[station] or 0)+amount
  r.job=nil
 end
 if r.job then return true end
 if station:sub(1,5)~='mars/' then return true end
 local best,available
 for _,area in ipairs(MINES) do
  local m=state.mines[area];local reserved,count=0,0
  for _,amount in pairs(m.reservations) do reserved=reserved+amount;count=count+1 end
  local free=math.floor(m.stock)-reserved
  if count<2 and free>=5 and (not available or free>available) then best,available=area,free end
 end
 local amount=math.min(10,capacity(r),available or 0)
 if not best or amount<5 then r.jobStatus='waiting for hauling work';return false end
 r.job={mine=best,home=station,amount=amount,phase='pickup',assigned=clock}
 state.mines[best].reservations[r.id]=amount
 r.tradeHome=station;r.tripDestination=best;r.jobStatus=nil
 return true
end
return J
