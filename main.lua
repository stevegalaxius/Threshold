--[[
	Entry point. LÖVE calls the love.* functions below; the game itself
	lives in src/, and all content (hulls, modules, ammo, enemies) in data/.

	The simulation runs on a fixed 120 Hz step so physics behaves the same
	at any frame rate; drawing happens once per frame.
]]

io.stdout:setvbuf("no")  -- print() shows up immediately in the console
love.graphics.setDefaultFilter("nearest", "nearest")

local data = require("src.data")
local T = require("src.tuning")
local Game = require("src.game")
local Input = require("src.input")
local Render = require("src.render")
local HUD = require("src.hud")
local Debug = require("src.debugui")
local Cargo = require("src.ui.cargo")

local STEP = 1 / 120
local accumulator = 0
local game
local autotest
local lastIntent = { aimX = 0, aimY = 0 }

function love.load(args)
	data.load()
	for _, a in ipairs(args or {}) do
		if a == "--autotest" then autotest = require("src.autotest") end
	end
	Debug.init()
	game = Game.new()
	love.mouse.setVisible(false)
	if autotest then
		autotest.start(game)
	elseif require("src.save").newest() then
		game:loadFrom()                    -- carry on from the latest save
	end
end

-- Closing the game saves it (unless you're dead or it's the autotest).
function love.quit()
	if not autotest and game and game.player and not game.player.dead then game:autosave() end
end

function love.update(dt)
	dt = math.min(dt, 1 / 15)
	Debug.update(dt, game)

	local intent
	if autotest then
		intent = autotest.intent(game, dt)
	else
		intent = Input.read(game, Debug.blocksMouse() or Cargo.isOpen(game), Debug.blocksKeyboard())
		-- With the cargo screen up the mouse is busy, so hold the aim
		-- straight ahead instead of chasing the cursor.
		local p = game.player
		if Cargo.isOpen(game) and p and not p.dead then
			local x, y = p.body:getPosition()
			local a = p.body:getAngle()
			intent.aimX, intent.aimY = x + math.cos(a) * 700, y + math.sin(a) * 700
		end
	end
	lastIntent = intent
	game:setPlayerIntent(intent)

	accumulator = accumulator + dt * T.timeScale
	while accumulator >= STEP do
		game:step(STEP)
		accumulator = accumulator - STEP
	end
	game:frame(dt, intent.aimX, intent.aimY)
	Cargo.update(game)
	love.mouse.setVisible(Debug.blocksMouse() or Cargo.isOpen(game))

	if autotest then autotest.update(game, dt) end
end

function love.draw()
	Render.world(game)
	HUD.draw(game, lastIntent.aimX, lastIntent.aimY, Cargo.isOpen(game))
	if Cargo.isOpen(game) then
		Cargo.draw(game)
		HUD.drawToasts(game, love.graphics.getHeight() - 110)
	end
	Debug.draw()
end

local function relaunch()
	if game.state == "dead" then game:respawn() end
end

function love.keypressed(key)
	if Debug.blocksKeyboard() then return end
	if Cargo.keypressed(game, key) then return end
	if game.state == "docked" and (key == "e" or key == "return" or key == "kpenter") then game:undock(); return end
	if key == "escape" then love.event.quit()
	elseif key == "f1" then Debug.toggle()
	elseif key == "h" then HUD.showHelp = not HUD.showHelp
	elseif key == "r" then relaunch()
	elseif key == "q" then game:cycleAux()
	elseif key == "f2" then game:nextField()
	elseif key == "f5" then game:saveTo("quick")
	elseif key == "f9" then Cargo.close(game); game:loadFrom()
	end
end

function love.gamepadpressed(_, button)
	if game.state == "docked" and button == "a" then game:undock(); return end
	if button == "start" then relaunch()
	elseif button == "y" then game:cycleAux()
	elseif button == "back" then Debug.toggle()
	end
end

function love.mousepressed(x, y, button)
	if Debug.blocksMouse() then return end
	Cargo.mousepressed(game, x, y, button)
end

function love.mousereleased(x, y, button)
	if Debug.blocksMouse() then return end
	Cargo.mousereleased(game, x, y, button)
end

function love.wheelmoved(_, y)
	if Debug.blocksMouse() then return end
	if y > 0 then game.camera:zoomBy(1.1) elseif y < 0 then game.camera:zoomBy(1 / 1.1) end
end
