-- The established local-space edge response, shared by circular and lateral
-- boundaries. Distance increases outward braking, never the inward drift.
local T=require('src.tuning')
return function(over,outward,mass)
 if over<=0 then return 0 end
 local fade=math.min(1,over/T.edgeSoft)
 return -mass*(T.edgeDrift+math.max(0,outward)*T.edgeBrake*fade)
end
