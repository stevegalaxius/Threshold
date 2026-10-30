--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Side/retro thrusters",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "dragScale",      label = "Drag (sets top speed)",  min = 0,   max = 3,    value = 0.5,    precision = 2 },
	{ key = "linearDamping",  label = "Linear damping (drift)", min = 0,   max = 2,    value = 0.04, precision = 2 },
	{ key = "massScale",      label = "Mass",                   min = 0.25, max = 3,   value = 1,    precision = 2 },
	{ key = "turnScale",      label = "Turn torque",            min = 0.1, max = 3,    value = 1,    precision = 2 },
	{ key = "maxTurnRate",    label = "Max turn rate (rad/s)",  min = 1,   max = 15,   value = 6.5,  precision = 1 },
	{ key = "aimGain",        label = "Aim snappiness",         min = 1,   max = 30,   value = 9,    precision = 1 },
	{ key = "turnResponse",   label = "Turn response",          min = 1,   max = 60,   value = 18,   precision = 1 },
	{ key = "knockbackScale", label = "Hit knockback",          min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "recoilScale",    label = "Recoil",                 min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "ramSpeed",       label = "Ram: min impact speed",  min = 0,   max = 400,  value = 90,   precision = 0 },
	{ key = "ramDamageScale", label = "Ram damage",             min = 0,   max = 0.003, value = 0.0005, precision = 5 },
	{ key = "boostThrust",    label = "Afterburner thrust (x main)", min = 1, max = 6, value = 3,  precision = 2 },
	{ key = "boostDrain",     label = "Afterburner drain (capacity/s)", min = 0, max = 2, value = 0.15, precision = 2 },
	{ key = "boostRelight",   label = "Afterburner relights at (capacity)", min = 0, max = 1, value = 0.3, precision = 2 },
	{ key = "thrustRecharge", label = "Power recharge while thrusting", min = 0, max = 1, value = 0.35, precision = 2 },
	{ key = "currentScale",   label = "Planet current speed",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "gunFalloff",     label = "Gun rounds: damage lost at max range", min = 0, max = 1, value = 0.6, precision = 2 },
	{ key = "artilleryFuse",  label = "Artillery proximity fuse (x splash)", min = 0, max = 1, value = 0.2, precision = 2 },
	{ key = "asteroidToughness", label = "Asteroid toughness (hp per r^2)", min = 0.005, max = 0.3, value = 0.05, precision = 3 },
	{ key = "asteroidImpact", label = "Asteroid impact damage", min = 0, max = 20, value = 4, precision = 1 },
	{ key = "huskToughness",  label = "Husk toughness (x ship armor)", min = 0.05, max = 2, value = 0.5, precision = 2 },
	{ key = "tractorBase",    label = "Tractor beam base range", min = 50, max = 800, value = 260, precision = 0 },
	{ key = "enemyDamage",    label = "Enemy damage",           min = 0,   max = 2,    value = 0.7,  precision = 2 },
	{ key = "camLead",        label = "Camera lead",            min = 0,   max = 0.6,  value = 0.3,  precision = 2 },
	{ key = "shake",          label = "Screenshake",            min = 0,   max = 2,    value = 1,    precision = 2 },
	{ key = "timeScale",      label = "Game speed",             min = 0.1, max = 2,    value = 1,    precision = 2 },
}

for _, s in ipairs(T.specs) do T[s.key] = s.value end

function T.reset()
	for _, s in ipairs(T.specs) do T[s.key] = s.value end
end

-- Fixed conversion factors between data units and physics units.
T.FORCE_PER_KN = 100      -- 1 kN of engine thrust = this much force in pixel units
T.TORQUE_PER_TURN = 1000  -- 1 point of "turn" = this much torque

-- Share of a dead ship's fitted modules that survive in its husk.
T.moduleSalvage = 0.5

-- Station storage grid, in 1 m3 cells (every station has its own).
T.storageW, T.storageH = 16, 12

-- Looting and towing. A tap of the tractor key (shorter than tapTime
-- seconds) on a wreck or container opens it; holding it tows a container
-- on a towLength pixel line, and you can't fly faster than towSpeed.
T.tapTime = 0.25
T.towLength, T.towSpeed = 70, 220
T.towStiffness, T.towDamping = 15, 6
-- Loose loaded containers drifting in each field.
T.fieldContainers = 6

-- The ship you're given when you start out or lose yours.
T.starterHull = "halcyon_wisp"
-- Level enemies leave you alone until you come this close (or shoot them).
T.aggroRange = 2600
-- Jump gates: how close to a gate's centre takes you through, and how long
-- after arriving before a gate will take you again.
T.gateRadius, T.gateCooldown = 150, 4

-- Developer cheats, toggled from the debug panel.
T.dev = { god = false, infiniteAmmo = false, showHold = false }

return T
