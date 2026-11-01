-- Run the real game integration checks with: love . --worldtest
return function(game)
	local checks = 0
	local function check(ok, message)
		assert(ok, message)
		checks = checks + 1
	end
	local data = require("src.data")
	local Fields = require("src.fields")
	local Game = require("src.game")
	local Ship = require("src.ship")
	local Export = require("src.editor.export")
	local Render = require("src.render")
	game:loadField("mars")
	game.autosaveOff = true
	local traders, rocks = 0, 0
	for _, e in ipairs(game.entities) do
		if e.route then traders = traders + 1 end
		if e.kind == "asteroid" and e.debris == "rock" then rocks = rocks + 1 end
	end
	check(traders == 9, "Mars should have nine local traders")
	check(rocks < 20, "Mars should have sparse rocks")
	for _, id in ipairs({ "phobos", "deimos", "io", "callisto", "enceladus", "titania" }) do
		local moon = Fields.moons[id]
		game:loadField(moon.parent)
		local gate
		for _, g in ipairs(game.moonGates) do if g.to == id then gate = g end end
		check(gate ~= nil, "missing outward gate to " .. id)
		game:launchTrip(id, { bearing = gate.a, length = gate.length })
		check(game.trip.moon and game.trip.to == id, "missing moon highway to " .. id)
		Render.world(game)
		game:arrive(false)
		check(game.fieldId == id, "wrong arrival field for " .. id)
		local st
		for _, e in ipairs(game.entities) do if e.kind == "station" then st = e break end end
		check(st ~= nil, "missing destination station for " .. id)
		check(data.markets[st.name] ~= nil, "missing market for " .. st.name)
		if id == "phobos" or id == "deimos" then
			local design = Export.fromStation(st.def.id)
			check(design.kind == "station" and #design.parts > 20, "mine should open as editable parts")
			local def, problem = data.defineStation(Export.stationDef(design))
			check(def and #def.docks == 1, problem or "mine export lost its tractor dock")
			local d = st.dock
			local x, y = game.dockWorld(st, 1, d.x2 + d.capture / 2, 0)
			game.player.body:setPosition(x, y)
			game.player.body:setLinearVelocity(0, 0)
			game:updateDocking(1 / 60)
			check(game.player.dockState ~= nil, "mine tractor failed to capture")
		end
		game:dockInstantly(game.player, st)
		local saved = game:saveState()
		game:loadState(saved)
		check(game.fieldId == id and game.player.dockState ~= nil, "docked save/load failed for " .. id)
		game:undock()
		local back = game.moonGates[1]
		check(back and back.to == moon.parent, "missing return gate for " .. id)
		game:launchTrip(back.to, { bearing = back.a, length = back.length })
		game:arrive(false)
		check(game.fieldId == moon.parent, "return highway failed for " .. id)
	end
	game:loadField("earth")
	local fare = game:driverFare("pluto")
	check(fare > 0 and fare < math.huge, "invalid Pluto fare")
	game.driverMenu = { driver = game:findDriver() }
	require("src.ui.orrery").keypressed(game, "-")
	check(game.player.launch and game.player.launch.to == "pluto", "Pluto menu shortcut selected the wrong planet")
	game:launchTrip("pluto")
	game:arrive(false)
	check(game.fieldId == "pluto" and game:findDriver(), "Pluto is not reachable by mass driver highway")
	check(Fields.orbits.pluto and not Fields.moons.pluto, "Pluto must be a planetary destination")
	require("tests.highway_handoff")(game)
	game:loadField("phobos", { player = Ship.record(game.player) })
	game.camera.x, game.camera.y, game.camera.zoom = 0, 0, 0.09
	local canvas = love.graphics.newCanvas(1280, 720)
	love.graphics.setCanvas(canvas)
	Render.world(game)
	love.graphics.setCanvas()
	canvas:newImageData():encode("png", "phobos-strip-mine.png")
	print(("world expansion: %d checks passed"):format(checks))
end
