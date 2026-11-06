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
local Orrery = require("src.ui.orrery")
local LocalMap = require("src.ui.localmap")
local Traffic=require("src.ui.npc_traffic")
local TransitView = require("src.ui.transitview")
local Pause = require("src.ui.pause")
local Editor = require("src.editor")

local STEP = 1 / 120
local accumulator = 0
local game
local autotest
local lastIntent = { aimX = 0, aimY = 0 }

--[[
	Render interpolation. Physics steps at a fixed 120 Hz, so a frame can
	land 1 or 2 steps after the last one and a moving ship jumps unevenly
	against the smooth camera (a one-pixel shimmer when zoomed in). Each
	frame, bodies are put where they'd be between their last two steps
	(alpha = leftover time / STEP) for the camera and drawing, then put
	back exactly before the next physics step.
]]
-- Each remember is numbered, so a body that only joined during the step
-- (sleeping debris woken as the player comes near, still carrying the
-- position it was remembered at before it slept) isn't drawn between that
-- stale spot and where it really is.
local lerpTick = 0
local function remember(g)
	lerpTick = lerpTick + 1
	for _, e in ipairs(g.entities) do
		local b = e.body
		if b and not b:isDestroyed() then
			e.lerpX, e.lerpY = b:getPosition()
			e.lerpA = b:getAngle()
			e.lerpTick = lerpTick
		else
			e.lerpX = nil
		end
	end
end

local function interpolate(g, alpha)
	for _, e in ipairs(g.entities) do
		local b = e.body
		if e.lerpX and e.lerpTick == lerpTick and b and not b:isDestroyed() then
			local x, y = b:getPosition()
			local a = b:getAngle()
			e.realX, e.realY, e.realA = x, y, a
			local da = (a - e.lerpA + math.pi) % (2 * math.pi) - math.pi
			b:setTransform(e.lerpX + (x - e.lerpX) * alpha, e.lerpY + (y - e.lerpY) * alpha, a - da * (1 - alpha))
			e.shownX, e.shownY = b:getPosition()
		else
			e.realX = nil
		end
	end
end

local function restore(g)
	for _, e in ipairs(g.entities) do
		if e.realX and e.body and not e.body:isDestroyed() then
			-- unless something moved it since (a teleport, a respawn)
			local x, y = e.body:getPosition()
			if x == e.shownX and y == e.shownY then e.body:setTransform(e.realX, e.realY, e.realA) end
		end
		e.realX = nil
	end
end

function love.load(args)
	-- Headless test runs: print an error and quit instead of showing the
	-- error screen, which waits for a click and never exits.
	for _, a in ipairs(args or {}) do
		if a:match("^%-%-%a+test$") then
			love.errorhandler = function(msg)
				print("Error: " .. tostring(msg) .. "\n" .. debug.traceback("", 2))
				os.exit(1)
			end
		end
	end
	data.load()
	for _, a in ipairs(args or {}) do
		if a == "--autotest" then autotest = require("src.autotest") end
	end
	Debug.init()
	game = Game.new()
	-- Test runs: the A-Life smoke test, one navigation test, and the editor's.
	local suites = {
		["--smoketest"] = "tests.smoke", ["--navtest"] = "tests.trader_navigation",
		["--editortest"] = "tests.editor_loadout", ["--editorfoldertest"] = "tests.editor_folders",
		["--weaponeditortest"] = "tests.weapon_editor", ["--dockeditortest"] = "tests.dock_editor",
		["--lighttooltest"] = "tests.light_tool", ["--painttest"] = "tests.paint",
		["--ammotest"] = "tests.weapon_ammo", ["--ramtest"] = "tests.collisions",
	}
	for _, a in ipairs(args or {}) do
		if suites[a] then
			game.autosaveOff = true
			local ok, err = xpcall(function() require(suites[a])(game) end, debug.traceback)
			if not ok then print(err) end
			love.event.quit(ok and 0 or 1)
			return
		end
	end
	love.mouse.setVisible(false)
	if autotest then
		autotest.start(game)
	elseif require("src.save").newest() then
		game:loadFrom()                    -- carry on from the latest save
	end
end

-- Closing the game saves it (unless you're dead or it's the autotest).
function love.quit()
	if not autotest and game and game.player and not game.player.dead then
		Cargo.clearTrade(game)          -- goods out on the trade grid go home first
		game:autosave()
	end
end

function love.update(dt)
	dt = math.min(dt, 1 / 15)
	Debug.update(dt, game)
	LocalMap.update(game)
	if Editor.isOpen() then
		-- the Shipyard pauses the game while it's up
		Editor.update(dt)
		love.mouse.setVisible(true)
		return
	end
	if Pause.isOpen() then
		love.mouse.setVisible(true)
		if autotest then autotest.update(game, dt) end
		return
	end

	local intent
	if autotest then
		intent = autotest.intent(game, dt)
	else
		intent = Input.read(game, Debug.blocksMouse() or Cargo.isOpen(game) or Orrery.isOpen(game) or LocalMap.isOpen(game) or Traffic.isOpen(game), Debug.blocksKeyboard() or LocalMap.isOpen(game) or Traffic.isOpen(game))
		-- With the cargo screen up the mouse is busy, so hold the aim
		-- straight ahead instead of chasing the cursor.
		local p = game.player
		if (Cargo.isOpen(game) or LocalMap.isOpen(game) or Traffic.isOpen(game)) and p and not p.dead then
			local x, y = p.body:getPosition()
			local a = p.body:getAngle()
			intent.aimX, intent.aimY = x + math.cos(a) * 700, y + math.sin(a) * 700
		end
	end
	lastIntent = intent
	game:setPlayerIntent(intent)

	restore(game)
	accumulator = accumulator + dt * T.timeScale
	while accumulator >= STEP do
		remember(game)
		local before=game.inputTranslation
		game:step(STEP)
		if game.inputTranslation~=before then
			local shift=game.inputTranslation
			if intent.aimX then intent.aimX=intent.aimX+shift.x end
			if intent.aimY then intent.aimY=intent.aimY+shift.y end
		end
		accumulator = accumulator - STEP
	end
	interpolate(game, accumulator / STEP)
	game:frame(dt, intent.aimX, intent.aimY)
	Cargo.update(game)
	love.mouse.setVisible(Debug.blocksMouse() or Cargo.isOpen(game) or Orrery.isOpen(game) or LocalMap.isOpen(game) or Traffic.isOpen(game))

	if autotest then autotest.update(game, dt) end
end

function love.draw()
	if Traffic.isOpen(game) then Traffic.draw(game);return end
	if Editor.isOpen() then
		Editor.draw()
		Debug.draw()
		return
	end
	if LocalMap.isOpen(game) then
		LocalMap.draw(game)
		Pause.draw(game)
		Debug.draw()
		return
	end
	if TransitView.isOpen(game) then
		TransitView.draw(game)
		HUD.drawToasts(game, 130)
		Pause.draw(game)
		Debug.draw()
		return
	end
	Render.world(game)
	if game.state ~= "docked" then
		HUD.draw(game, lastIntent.aimX, lastIntent.aimY, Cargo.isOpen(game))
	end
	if Cargo.isOpen(game) then
		Cargo.draw(game)
		HUD.drawToasts(game, Cargo.toastY(game))
	end
	if game.state ~= "docked" then Orrery.draw(game) end
	Pause.draw(game)
	Debug.draw()
end

local function relaunch()
	if game.state == "dead" then game:respawn() end
end

function love.textinput(text)
 Cargo.textinput(game,text)
end

function love.keypressed(key)
	if key == "f1" then Debug.toggle(); return end
	if key == "f6" then Debug.toggleALife(); return end
	if key=="f4" then Traffic.toggle(game);return end
	if Traffic.keypressed(game,key) then return end
	if Editor.keypressed(key) then return end
	if Debug.blocksKeyboard() then return end
	if Pause.keypressed(game, key) then return end
	if LocalMap.isOpen(game) and LocalMap.keypressed(game, key) then return end
	if Orrery.keypressed(game, key) then return end
	if LocalMap.keypressed(game, key) then return end
	if Cargo.keypressed(game, key) then return end
	if game.state == "docked" and (key == "e" or key == "return" or key == "kpenter") then game:undock(); return end
	if key == "escape" then Pause.toggle(game)
	elseif key == "h" then HUD.showHelp = not HUD.showHelp
	elseif key == "r" then relaunch()
	elseif key == "g" then game:toggleDroneControl()
	elseif key == "f2" then Editor.toggle(game)
	elseif key == "f5" then Cargo.clearTrade(game); game:saveTo("quick")
	elseif key == "f9" then Cargo.close(game); game:loadFrom()
	end
end

function love.gamepadpressed(_, button)
	if button == "start" and game.state ~= "dead" then Pause.toggle(game) return end
	if Pause.isOpen() or Editor.isOpen() or LocalMap.isOpen(game) or Traffic.isOpen(game) then return end
	if game.state == "docked" and button == "a" then game:undock(); return end
	if button == "start" then relaunch()
	elseif button == "back" then Debug.toggle()
	end
end

function love.mousepressed(x, y, button)
	if Traffic.mousepressed(game,x,y,button) then return end
	if Editor.mousepressed(x, y, button) then return end
	if Debug.blocksMouse() then return end
	if Pause.mousepressed(game, x, y, button) then return end
	if LocalMap.mousepressed(game, x, y, button) then return end
	if Orrery.mousepressed(game, x, y, button) then return end
	Cargo.mousepressed(game, x, y, button)
end

function love.mousereleased(x, y, button)
	if Traffic.isOpen(game) then return end
	if Editor.mousereleased(x, y, button) then return end
	if Debug.blocksMouse() then return end
	if LocalMap.mousereleased(game) then return end
	Cargo.mousereleased(game, x, y, button)
end

function love.wheelmoved(x, y)
	if Traffic.wheelmoved(game,y) then return end
	if Editor.wheelmoved(x, y) then return end
	if Debug.blocksMouse() then return end
	if Pause.isOpen() then return end
	if LocalMap.wheelmoved(game, y) then return end
	if Cargo.wheelmoved(game,y) then return end
	if y > 0 then game.camera:zoomBy(1.1) elseif y < 0 then game.camera:zoomBy(1 / 1.1) end
end
