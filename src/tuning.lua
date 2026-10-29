--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Side/retro thrusters",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "dragScale",      label = "Drag (sets top speed)",  min = 0.1, max = 3,    value = 1,    precision = 2 },
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
	{ key = "boostSpeed",     label = "Afterburner kick (px/s)", min = 0,  max = 800,  value = 280,  precision = 0 },
	{ key = "boostCost",      label = "Afterburner power cost", min = 0,   max = 100,  value = 25,   precision = 0 },
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

-- Developer cheats, toggled from the debug panel.
T.dev = { god = false, infiniteAmmo = false }

return T
