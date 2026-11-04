-- Mine output for placeholder ore jobs. Phobos and Deimos refill slowly; ore
-- transport offers on the shared task board (src/transport.lua) are only
-- eligible while their mine has stock, and picking one up takes from it.
local J={}
J.mines={'phobos','deimos'}
J.oreTo='mars'
function J.state(u,clock)
 u.jobs=u.jobs or {}
 u.jobs.mines=u.jobs.mines or {}
 for _,area in ipairs(J.mines) do
  local m=u.jobs.mines[area]
  if not m then m={stock=20,clock=clock};u.jobs.mines[area]=m end
  m.reservations=nil -- legacy per-trader reservations; the task board owns those now
  m.stock=math.min(80,m.stock+math.max(0,clock-m.clock)/12)
  m.clock=math.max(clock,m.clock)
 end
 return u.jobs
end
function J.available(u,area,clock) return math.floor(J.state(u,clock).mines[area].stock) end
function J.take(u,area,amount,clock)
 local m=J.state(u,clock).mines[area]
 if math.floor(m.stock)<amount then return false end
 m.stock=m.stock-amount;return true
end
return J
