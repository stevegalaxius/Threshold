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
	if autotest then autotest.start(game) end
end

function love.update(dt)
	dt = math.min(dt, 1 / 15)
	Debug.update(dt, game)

	local intent
	if autotest then
		intent = autotest.intent(game, dt)
	else
		intent = Input.read(game, Debug.blocksMouse(), Debug.blocksKeyboard())
	end
	lastIntent = intent
	game:setPlayerIntent(intent)

	accumulator = accumulator + dt * T.timeScale
	while accumulator >= STEP do
		game:step(STEP)
		accumulator = accumulator - STEP
	end
	game:frame(dt, intent.aimX, intent.aimY)
	love.mouse.setVisible(Debug.blocksMouse())

	if autotest then autotest.update(game, dt) end
end

function love.draw()
	Render.world(game)
	HUD.draw(game, lastIntent.aimX, lastIntent.aimY)
	Debug.draw()
end

local function relaunch()
	if game.state == "dead" then
		game:clearEnemies()
		game.pickups = {}
		game.wave, game.kills, game.waveTimer = 0, 0, 2.5
		game:spawnPlayer()
	end
end

function love.keypressed(key)
	if Debug.blocksKeyboard() then return end
	if key == "escape" then love.event.quit()
	elseif key == "f1" then Debug.toggle()
	elseif key == "h" then HUD.showHelp = not HUD.showHelp
	elseif key == "r" then relaunch()
	elseif key == "q" then game:cycleAux()
	elseif key == "f2" then game:nextField()
	end
end

function love.gamepadpressed(_, button)
	if button == "start" then relaunch()
	elseif button == "y" then game:cycleAux()
	elseif button == "back" then Debug.toggle()
	end
end

function love.wheelmoved(_, y)
	if Debug.blocksMouse() then return end
	if y > 0 then game.camera:zoomBy(1.1) elseif y < 0 then game.camera:zoomBy(1 / 1.1) end
end
