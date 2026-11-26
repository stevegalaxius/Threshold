return function()
	local Game = require("src.game")
	local Ship = require("src.ship")
	local Weapons = require("src.weapons")
	local Security = require("src.security")
	local Combat = require("src.combat")
	local Rep = require("src.reputation")
	local game = Game.new({preview=true})
	game.world:destroy()
	game.world = love.physics.newWorld()
	game.entities, game.alifeOnline, game.projectiles = {}, {}, {}
	local u = game.universe
	u.npcs = {}

	local function ship(x, y, record)
		local e = Ship.new(game, {hull="intaki_wisp", x=x, y=y})
		game.entities[#game.entities+1] = e
		if record then
			record.id = "npc/" .. tostring(e.id)
			e.alifeId, e.alifeRecord = record.id, record
			u.npcs[record.id] = record
		end
		return e
	end

	local police = ship(0, 0, {
		affiliation="estates", authorizations={{kind="police", issuer="estates", jurisdiction="earth"}},
	})
	local escort = ship(200, 0, {affiliation="estates"})
	local courier = ship(500, 0, {affiliation=Rep.CARTEL, task={kind="transport"}})
	assert(Security.target(game, police) == courier, "patrol missed a hostile faction courier")
	local originalArmor = courier.armor
	local escortArmor = escort.armor
	game.projectiles[1] = {kind="gun", owner=police, x=-150, y=0, vx=1000, vy=0, life=1,
		damage=8, knockback=0}
	Weapons.updateProjectiles(game, 0.8)
	assert(courier.armor < originalArmor and courier.aggressor == police,
		"patrol rounds passed through a hostile faction or hit without provoking retaliation")
	assert(escort.armor == escortArmor and #game.projectiles == 0, "a direct shot landed on an ally")

	Rep.setStance(u, "estates", Rep.CARTEL, "friendly")
	assert(not Combat.hostile(game, police, courier), "newly friendly crew stayed eligible for auto-targeting")
	assert(not game:raycast(90, 0, 600, 0, police, false, true), "new faction alliance failed to protect a ship")
	local hit = game:raycast(90, 0, 600, 0, police)
	assert(hit and hit.entity == escort, "physical visibility ray ignored the ship obstructing it")
	Rep.setStance(u, "estates", Rep.CARTEL, nil)

	local pilot = ship(0, 200)
	pilot.isPlayer = true
	game.player = pilot
	local drone = ship(130, 200)
	drone.drone, drone.owner = true, pilot
	local neutral = ship(250, 200, {})
	local raider = ship(800, 200, {wildcat={site="test"}, homeStation="station:cordelia_1", task={kind="raid"}})
	assert(not Rep.crewFaction(raider.alifeRecord), "a wildcat inherited its port's faction")
	assert(Combat.hostile(game, pilot, raider) and not Combat.hostile(game, pilot, neutral),
		"player guidance did not distinguish a raider from neutral traffic")
	assert(Combat.allied(u, pilot, drone) and not Combat.hostile(game, pilot, drone), "owned drone treated as a target")
	hit = game:raycast(20, 200, 400, 200, pilot, false, true)
	assert(hit and hit.entity == neutral, "direct fire missed an unaffiliated ship or hit an owned drone")

	pilot.intent.aimX, pilot.intent.aimY = 800, 200
	local originalComputer = game.computer
	game.computer = function(_, _, kind) if kind == "guidance" then return {radarRange=2000, lockCone=20} end end
	game:updateComputers(1/60)
	assert(pilot.lock == raider, "guidance locked an ally or a neutral ship on the aim line")
	raider.alifeRecord.task.kind = "wildcat_home"
	game:updateComputers(1/60)
	assert(not pilot.lock, "guidance kept a lock after the threat ended")
	game.computer = originalComputer

	local scripted = game:spawnEnemy("swarmer", 500, 400, {idle=true})
	assert(Combat.hostile(game, pilot, scripted) and Combat.sceneEnemy(scripted),
		"scripted enemies lost their encounter behavior")
	local defender, hunter = ship(0, 500), ship(500, 500)
	defender.siteEnemy, hunter.siteHunter = true, true
	assert(Combat.hostile(game, defender, hunter) and Combat.hostile(game, hunter, defender),
		"site defenders and bounty hunters stopped recognizing each other")
	game.world:destroy()
	print("ok  faction combat: hostile projectiles, retaliation, friendly fire, owned drones, guidance and site opponents")
end
