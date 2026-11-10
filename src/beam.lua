-- The one tractor beam that catches ships: a station's docking runway and a
-- mass driver's (or acceleration gate's) breech both use it. The caller says
-- where the ship should be heading in the beam's frame; the beam pushes its
-- velocity there and turns its nose.
--
-- NPCs are held firmly: their engines are off while the beam has them (the
-- docking and launch steps run instead of their AI) and the pull has no cap,
-- so they're caught the same way every time. The player's pull is capped at
-- T.beamGrip, so they can fight it, overshoot it or slide out.
local T=require('src.tuning')
local B={}
local min,max,sqrt,pi=math.min,math.max,math.sqrt,math.pi
local function wrap(a) return (a+pi)%(2*pi)-pi end

-- e: the ship. t: seconds in the beam. near: 0 at the beam's mouth, 1 at
-- its end. fvx,fvy: the beam's own velocity at the ship. wx,wy: the
-- velocity wanted relative to it. nose: the heading wanted. spin: the
-- frame's angular velocity (a turning station). extra(ax,ay): any other
-- acceleration the beam cancels (cloud-top gravity).
function B.grip(t,near) return min(1,t/1.0)*(.35+.65*near) end
function B.hold(game,e,o)
 local b=e.body
 local grip=B.grip(o.t,o.near)
 local vx,vy=b:getLinearVelocity()
 local k=2.2*grip
 local ax,ay=(o.fvx+o.wx-vx)*k,(o.fvy+o.wy-vy)*k
 if e==game.player then
  local a=sqrt(ax*ax+ay*ay)
  local cap=T.beamGrip*(.5+.5*grip)
  if a>cap then ax,ay=ax/a*cap,ay/a*cap end
 end
 if o.gx then ax,ay=ax-o.gx,ay-o.gy end
 local m=b:getMass()
 b:applyForce(ax*m,ay*m)
 -- the player keeps their own nose: turning it for them would point their
 -- engine where the beam wants and take away the way out
 if e==game.player then return grip end
 local w=b:getAngularVelocity()
 local turn=wrap(o.nose-b:getAngle())*1.4*grip+(o.spin or 0)
 b:setAngularVelocity(w+(turn-w)*min(1,3*(o.dt or 1/60)))
 return grip
end
return B
