--[[
	Player controls -> intent. Keyboard + mouse and gamepad both work, and
	whichever you touched last is the one that aims.

	Thrust is relative to where the ship points, which is at your aim, except
	on a battleship (helm = "turn"), where A/D turn the hull and the mouse
	only aims the turrets.

	Keyboard/mouse                 Gamepad
	  W / S     main engine / retro  left stick up/down
	  A / D     side thrusters (battleship: turn)  left stick left/right
	  mouse     aim                  right stick    aim
	  left btn  primary weapons      right trigger  primary weapons
	  right btn missiles             left trigger / right bumper  missiles
	  Shift     afterburner          A              afterburner
]]

local Input = { device = "kbm", padAimX = 1, padAimY = 0 }

local DEADZONE = 0.22

local function stick(j, ax, ay)
	local x, y = j:getGamepadAxis(ax), j:getGamepadAxis(ay)
	local l = math.sqrt(x * x + y * y)
	if l < DEADZONE then return 0, 0, 0 end
	local s = math.min(1, (l - DEADZONE) / (1 - DEADZONE)) / l
	return x * s, y * s, l
end

function Input.gamepad()
	for _, j in ipairs(love.joystick.getJoysticks()) do
		if j:isGamepad() then return j end
	end
end

-- uiBlocksMouse: true while the pointer is over the debug panel.
function Input.read(game, uiBlocksMouse, keyboardBlocked)
	local intent = { thrust = 0, strafe = 0, firePrimary = false, fireSecondary = false, boost = false }
	local p = game.player
	local px, py = 0, 0
	if p and not p.dead then px, py = p.body:getPosition() end

	-- Keyboard / mouse
	if not keyboardBlocked then
		local k = love.keyboard.isDown
		if k("w") or k("up") then intent.thrust = intent.thrust + 1 end
		if k("s") or k("down") then intent.thrust = intent.thrust - 1 end
		if k("d") or k("right") then intent.strafe = intent.strafe + 1 end
		if k("a") or k("left") then intent.strafe = intent.strafe - 1 end
		intent.boost = k("lshift") or k("rshift") or k("space")
	end
	if not uiBlocksMouse then
		intent.firePrimary = love.mouse.isDown(1)
		intent.fireSecondary = love.mouse.isDown(2)
	end
	if intent.thrust ~= 0 or intent.strafe ~= 0 or intent.firePrimary then Input.device = "kbm" end

	-- Gamepad
	local j = Input.gamepad()
	if j then
		local mx, my = stick(j, "leftx", "lefty")
		local ax, ay, al = stick(j, "rightx", "righty")
		local rt = j:getGamepadAxis("triggerright") > 0.3
		local lt = j:getGamepadAxis("triggerleft") > 0.3 or j:isGamepadDown("rightshoulder")
		if mx ~= 0 or my ~= 0 or al > 0 or rt or lt then Input.device = "pad" end
		if Input.device == "pad" then
			intent.thrust = intent.thrust - my
			intent.strafe = intent.strafe + mx
			if al > 0 then
				local l = math.sqrt(ax * ax + ay * ay)
				Input.padAimX, Input.padAimY = ax / l, ay / l
			end
			intent.firePrimary = intent.firePrimary or rt
			intent.fireSecondary = intent.fireSecondary or lt
			intent.boost = intent.boost or j:isGamepadDown("a")
		end
	end

	-- Aim point in the world.
	if Input.device == "pad" then
		intent.aimX, intent.aimY = px + Input.padAimX * 700, py + Input.padAimY * 700
	else
		intent.aimX, intent.aimY = game.camera:toWorld(love.mouse.getPosition())
	end
	return intent
end

return Input
