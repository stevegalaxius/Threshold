-- Focused area-object persistence checks: love . --persisttest
return function(game)
	local Save = require("src.save")
	local Hold = require("src.inventory.hold")
	local Ship = require("src.ship")
	local Fields = require("src.fields")
	local checks = 0
	local function check(ok, message) assert(ok, message); checks = checks + 1 end
	local function near(a, b) return math.abs(a - b) < 0.001 end
	local function clear()
		for i = #game.entities, 1, -1 do
			local e = game.entities[i]
			if e.kind == "husk" or e.kind == "container" then game:remove(e) end
		end
		game.pickups = {}
	end
	local function find(id)
		for _, e in ipairs(game.entities) do if e.persistenceId == id then return e end end
	end
	game.autosaveOff = true
	game:loadField("asteroids")
	clear()
	local h = game:spawnWreck("derelict_tug", 900, 1200, 0.4, 35, -12)
	h.hp = h.hp * 0.6
	local loose
	for _, pc in ipairs(h.pieces) do if not pc.core then loose = pc break end end
	check(loose ~= nil, "test wreck has no detachable part")
	game:breakOff(h, loose)
	for _, pc in ipairs(h.pieces) do if not pc.core then pc.hp = pc.hp * 0.4; break end end
	-- A real ship wreck exercises hull definitions and packed containers.
	local ship = game:spawnEnemy("freighter", 2200, 1200)
	local freighter = game:spawnHusk(ship, 2200, 1200, 0.7, 20, 30, 0.1)
	game:remove(ship)
	local inner = Hold.new({ { key = "main", name = "Cargo", w = 8, h = 4 } })
	Hold.add(inner, "rounds_s", 37)
	check(Hold.placeStack(freighter.hold, { id = "cargo_container", n = 1, inner = inner }), "could not seed nested cargo")
	freighter.loot = Hold.totals(freighter.hold)
	local box = game:spawnContainer(1400, 1900, "cargo_container", false)
	Hold.add(box.hold, "scrap", 3)
	box.loot = Hold.totals(box.hold)
	game:containerMass(box)
	box.hp = box.hp * 0.5
	box.body:setLinearVelocity(11, -7)
	game:spawnPickup(1800, 2200, "rounds_s", 9)
	local snapshot = game:captureArea()
	local savedHull, savedContainer = h.persistenceId, box.persistenceId
	check(snapshot.version == 1 and snapshot.capturedAt == game.universe.clock, "snapshot schema missing")
	check(#snapshot.objects == 4 and #snapshot.pickups == 1, "wrong snapshot population")
	check(snapshot.objects[1].pieces and #snapshot.objects[1].pieces == #h.pieces, "broken part state missing")
	local encodedObjects = Save.encode(snapshot.objects)
	game:loadField("giant")
	game.universe.clock = game.universe.clock + 10000
	game:loadField("asteroids")
	local restored = game:captureArea()
	check(#restored.objects == 4 and #restored.pickups == 1, "return duplicated or lost objects")
	for i, r in ipairs(restored.objects) do
		local before = snapshot.objects[i]
		check(r.id == before.id and r.kind == before.kind, "persistent identity changed")
		check(near(r.x, before.x) and near(r.y, before.y), "unloaded object did not pause in place")
		check(near(r.vx, before.vx) and near(r.vy, before.vy) and near(r.spin, before.spin), "object motion changed")
		check(near(r.hp, before.hp), "object damage reset")
		check(Save.encode(r.hold) == Save.encode(before.hold), "loot layout or nested cargo changed")
		check(Save.encode(r.pieces or {}) == Save.encode(before.pieces or {}) and r.part == before.part, "wreck parts or salvage shares changed")
	end
	check(find(savedHull) and find(savedContainer), "objects could not be identified after travel")
	check(Save.encode(snapshot.objects) == encodedObjects, "restoration mutated the previous snapshot")
	local wreck = find(savedHull)
	local previous = #wreck.pieces
	for _, pc in ipairs(wreck.pieces) do
		if not pc.core then
			local x, y = wreck.body:getWorldPoint(pc.part.cx, pc.part.cy)
			game:damage(wreck, pc.hp + 1, nil, "test", x, y)
			break
		end
	end
	check(#wreck.pieces == previous - 1, "restored wreck cannot break apart")
	local saved = game:saveState()
	local decoded, err = Save.decode(Save.encode(saved))
	check(decoded ~= nil, err)
	check(Save.upgrade(decoded).version == 2, "save version not upgraded")
	game:spawnPickup(0, 0, "scrap", 99)
	game:loadState(decoded)
	check(#game.pickups == #saved.areas.asteroids.pickups, "load overwrote saved state with the abandoned live scene")
	check(find(savedContainer).hp == box.hp, "save/load lost container damage")
	check(game.universe.nextObjectId == saved.nextObjectId, "persistent ID allocator was not restored")
	-- Single-piece hulls use spine/circle fixtures rather than breakable parts.
	local drone = game:spawnEnemy("swarmer", 3000, 3000)
	local simple = game:spawnHusk(drone, 3000, 3000, 0.2, 3, 4, 0.1)
	game:remove(drone)
	check(not simple.pieces, "single-piece test hull unexpectedly has parts")
	game:captureArea()
	local simpleId, simpleFixtures = simple.persistenceId, #simple.body:getFixtures()
	check(simpleId > saved.nextObjectId, "new persistent IDs reused saved IDs")
	game:loadField("giant")
	game:loadField("asteroids")
	local simpleAgain = find(simpleId)
	check(simpleAgain and #simpleAgain.body:getFixtures() == simpleFixtures,
		"single-piece wreck fixtures were not restored")
	-- Confirm restored bodies can run through normal physics and rendering.
	for _ = 1, 3 do game:step(1 / 120) end
	require("src.render").world(game)
	check(not simpleAgain.body:isDestroyed(), "restored wreck did not survive simulation")
	-- Empty snapshots suppress generated baseline containers as well as old loot.
	clear()
	game:loadField("giant")
	game:loadField("asteroids")
	check(#game.pickups == 0, "collected loot respawned")
	local selected = 0
	for _, e in ipairs(game.entities) do if e.kind == "husk" or e.kind == "container" then selected = selected + 1 end end
	check(selected == 0, "empty area refilled its containers")
	-- An already visited but currently unloaded area must also survive disk serialization.
	game:loadField("giant")
	local all = assert(Save.decode(Save.encode(game:saveState())))
	game:loadState(all)
	game:loadField("asteroids")
	check(#game.entities > 0 and #game:captureArea().objects == 0, "unloaded area's empty snapshot was lost")
	-- Real moon travel releases the original world, then recreates its objects.
	game:loadField("earth")
	game:spawnPickup(30000, 0, "scrap", 5)
	game:captureArea()
	local id = game.pickups[#game.pickups].persistenceId
	local oldWorld = game.world
	game:launchTrip("luna", { bearing = 0, length = Fields.moons.luna.gap })
	local mid = assert(Save.decode(Save.encode(game:saveState())))
	check(mid.areas.earth and #mid.areas.earth.pickups > 0, "mid-transit save lost the departure area")
	game:arrive(false)
	check(oldWorld:isDestroyed(), "onward travel did not release the source physics world")
	game:launchTrip("earth", { bearing = math.pi, length = Fields.moons.luna.gap })
	game:arrive(false)
	local found = 0
	for _, p in ipairs(game.pickups) do if p.persistenceId == id and p.count == 5 then found = found + 1 end end
	check(found == 1, "moon round trip lost or duplicated dropped cargo")
	check(game.universe.areas.lane == nil, "transient lanes were accidentally cached as a single area")
	-- Unloaded planetary objects follow the same current as sleeping debris.
	game:loadField("earth")
	local orbitBox = game:spawnContainer(22000, 0, "cargo_container", false)
	game:captureArea()
	local orbitId = orbitBox.persistenceId
	local expected = game:currentSpeed(22000) / 22000 * 120
	game:loadField("giant")
	game.universe.clock = game.universe.clock + 120
	game:loadField("earth")
	local moved = find(orbitId)
	local ox, oy = moved.body:getPosition()
	check(near(ox, 22000 * math.cos(expected)) and near(oy, 22000 * math.sin(expected)),
		"planetary cargo stayed frozen instead of following the current")
	check(math.abs(math.sqrt(ox * ox + oy * oy) - 22000) < 0.01, "orbital catch-up changed altitude")
	-- Retained scenes must move objects too, including an immediate turnback.
	game:launchTrip("luna", { bearing = 0, length = Fields.moons.luna.gap })
	game.universe.clock = game.universe.clock + 60
	game:arrive(true)
	moved = find(orbitId)
	ox, oy = moved.body:getPosition()
	check(near(ox, 22000 * math.cos(expected * 1.5)) and near(oy, 22000 * math.sin(expected * 1.5)),
		"retained source scene ignored elapsed orbital time")
	-- Old saves start with no snapshots; loading them cannot retain current clutter.
	local old = { version = 1, field = "asteroids", stations = {}, clock = 0, credits = 5000 }
	check(next(Save.upgrade(old).areas) == nil, "old save migration needs optional area data")
	game:loadState(old)
	check(not game.universe.areas.earth, "loading an old save retained the previous world's snapshots")
	check(Save.upgrade({ version = 999 }) == nil, "future save version accepted")
	print(("area persistence: %d checks passed"):format(checks))
end
