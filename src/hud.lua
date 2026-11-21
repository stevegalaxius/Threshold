local Pose = require("src.render_pose")
--[[
	Heads-up display: armor, power, weapons with ammo counts, hold, kills
	info, pickup messages, off-screen enemy markers and the aim reticle.
	Styled as worn Y2K glass panels; placeholder until the real UI pass.
]]

local data = require("src.data")
local Input = require("src.input")
local Render = require("src.render")
local T = require("src.tuning")
local Fields = require("src.fields")

local HUD = { showHelp = true }

local lg = love.graphics
local drawScanTip
local floor, max, min, sqrt, atan2, cos, sin = math.floor, math.max, math.min, math.sqrt, math.atan2, math.cos, math.sin

local fonts
local function font(size)
	fonts = fonts or {}
	if not fonts[size] then fonts[size] = lg.newFont(size) end
	return fonts[size]
end

local AQUA = { 0.55, 0.92, 1.0 }
local INK = { 0.86, 0.96, 1.0 }
local DIM = { 0.55, 0.7, 0.78 }
local WARN = { 1.0, 0.45, 0.35 }

-- A glossy panel that's seen better days.
local function panel(x, y, w, h)
	lg.setColor(0.04, 0.1, 0.14, 0.78)
	lg.rectangle("fill", x, y, w, h, 10, 10)
	lg.setColor(0.6, 0.95, 1, 0.08)
	lg.rectangle("fill", x + 3, y + 3, w - 6, h * 0.35, 8, 8)       -- gloss
	lg.setColor(AQUA[1], AQUA[2], AQUA[3], 0.45)
	lg.setLineWidth(1)
	lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 10, 10)
	lg.setColor(0, 0, 0, 0.35)                                           -- scuffs
	lg.line(x + w * 0.62, y + 1, x + w * 0.7, y + h * 0.3)
	lg.line(x + 12, y + h - 2, x + 40, y + h - 9)
end

local function bar(x, y, w, h, frac, color, label, value)
	frac = max(0, min(1, frac))
	lg.setColor(0, 0, 0, 0.55)
	lg.rectangle("fill", x, y, w, h, 4, 4)
	lg.setColor(color[1], color[2], color[3], 0.9)
	if frac > 0 then lg.rectangle("fill", x, y, w * frac, h, 4, 4) end
	lg.setColor(1, 1, 1, 0.22)
	if frac > 0 then lg.rectangle("fill", x + 2, y + 1, (w - 4) * frac, h * 0.35, 3, 3) end
	lg.setFont(font(12))
	lg.setColor(INK)
	lg.print(label, x + 6, y + floor((h - 12) / 2))
	lg.printf(value, x, y + floor((h - 12) / 2), w - 6, "right")
end

local function weaponLines(p)
	local lines, index = {}, {}
	for _, w in ipairs(p.weapons) do
		local key = w.group .. ":" .. w.module.id .. ":" .. tostring(w.ammo)
		local line = index[key]
		if not line then
			line = { name = w.module.name, n = 0, kind = w.w.kind, ammo = w.ammo, group = w.group, starved = false, armed = 0, tubes = 0, arming = 0 }
			index[key] = line
			table.insert(lines, line)
		end
		line.n = line.n + 1
		local tubes = require("src.weapons").tubes(w)
		if tubes then
			line.tubes = line.tubes + tubes
			line.armed = line.armed + (w.armed or 0)
			local t = data.items[w.ammo].shot.armTime or 1
			line.arming = max(line.arming, (w.arming or 0) / t)
		end
		line.starved = line.starved or w.starved
	end
	local ORDER = { primary = 1, secondary = 2, tertiary = 3 }
	table.sort(lines, function(a, b) return ORDER[a.group] < ORDER[b.group] end)
	return lines
end

local function drawStatus(game)
	local p = game.player
	if not p or p.dead then return end
	local w, h = lg.getDimensions()
	local lines = weaponLines(p)
	local ph = 130 + #lines * 18
	local x, y, pw = 16, h - ph - 16, 330
	HUD.statusTop = y
	panel(x, y, pw, ph)

	local s = p.stats
	local lowArmor = p.armor / s.armor < 0.3
	bar(x + 12, y + 12, pw - 24, 18, p.armor / s.armor, lowArmor and WARN or { 0.4, 0.85, 0.95 }, "ARMOR", ("%d / %d"):format(floor(p.armor + 0.5), floor(s.armor + 0.5)))
	local powerLabel = p.afterburn and (p.burnerLocked and "AFTERBURNER  (reserve)" or "AFTERBURNER") or (p.burnerLocked and "POWER  (afterburner on reserve)" or "POWER")
	bar(x + 12, y + 34, pw - 24, 14, p.power / max(1, s.powerCap), p.burnerLocked and { 1.0, 0.7, 0.35 } or { 0.55, 0.75, 1.0 }, powerLabel, ("%d  (reactor %d/s)"):format(floor(p.power), floor(p.reactorOutput or 0)))
	-- capacitor charge protected by afterburner reserve mode
	lg.setColor(1, 1, 1, 0.5)
	local rx = x + 12 + (pw - 24) * T.boostRelight
	lg.line(rx, y + 33, rx, y + 49)

	lg.setFont(font(12))
	local Fuel=require('src.reactor_fuel')
	lg.setColor(Fuel.remaining(p)>0 and 0.75 or 1,0.8,0.65,1)
	lg.print(("FUEL: %d %s / %.0f%% active"):format(p.cargo[Fuel.item()] or 0,data.items[Fuel.item()].name,100*(p.fuelCharge or 0)/T.reactorFuelEnergy),x+12,y+54)
	local ly = y + 74
	for _, line in ipairs(lines) do
		local tag = ({ primary = "PRI", secondary = "SEC", tertiary = "TER" })[line.group] or ""
		local label = tag .. "  " .. (line.n > 1 and (line.n .. "x ") or "") .. line.name
		lg.setColor(line.group == "tertiary" and { 1, 0.85, 0.7 } or (line.group == "secondary" and { 0.8, 0.9, 1 } or INK))
		lg.print(label, x + 14, ly)
		local right, col
		if data.LASERS[line.kind] or line.kind == "drill" then
			right, col = line.starved and "NO POWER" or "power", line.starved and WARN or DIM
		else
			local n = p.cargo[line.ammo] or 0
			right = ("%d  %s"):format(n, data.items[line.ammo].name:lower())
			if line.tubes > 0 then
				-- tubes: armed / held, and a bar for the one re-arming
				right = ("%d/%d armed   "):format(line.armed, line.tubes) .. right
				if line.armed < line.tubes and line.arming > 0 then
					lg.setColor(1, 0.85, 0.5, 0.35)
					lg.rectangle("fill", x + 14, ly + 15, (pw - 28) * line.arming, 2)
				end
			end
			col = (n == 0) and WARN or ((n < 20 and data.items[line.ammo].family == "gun") and { 1, 0.8, 0.4 } or INK)
		end
		lg.setColor(col)
		lg.printf(right, x, ly, pw - 14, "right")
		ly = ly + 18
	end

	-- Hold
	local salvageValue, salvageCount = 0, 0
	for id, n in pairs(p.cargo) do
		local item = data.items[id]
		if item and item.kind == "salvage" and n > 0 then
			salvageValue = salvageValue + item.price * n
			salvageCount = salvageCount + n
		end
	end
	ly = ly + 4
	local cap = p.holdCap or s.hold
	bar(x + 12, ly, pw - 24, 14, p.holdUsed / max(0.01, cap), { 0.9, 0.75, 0.4 }, "HOLD",
		(p.hold and "%d / %d m3" or "%.1f / %.0f m3"):format(p.holdUsed, cap))
	lg.setFont(font(12))
	lg.setColor(DIM)
	lg.print(("salvage %d  (worth %d cr)"):format(salvageCount, salvageValue), x + 14, ly + 20)
	lg.printf(("%.0f t"):format(p.body:getMass()), x, ly + 20, pw - 14, "right")
end

-- 12450 -> "12,450 cr"
function HUD.credits(n)
	local s = tostring(floor(math.abs(n)))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. s .. " cr"
end

local function drawTopBar(game)
	local p = game.player
	local speed = 0
	if p and not p.dead then
		local vx, vy = p.body:getLinearVelocity()
		speed = sqrt(vx * vx + vy * vy)
	end
	local status = ("KILLS %d    SPEED %d    %s"):format(game.kills, floor(speed), HUD.credits(game.universe.credits))
	panel(16, 12, 380, 32)
	lg.setFont(font(14))
	lg.setColor(INK)
	lg.print(status, 28, 20)
	if game.field then
		lg.setFont(font(12))
		lg.setColor(DIM)
		lg.print(game.field.name, 28, 50)
	end
end

-- Where you can go: drivers, docks, the next braking ring and moon exits.
local function destinations(game)
	local out = {}
	for _, e in ipairs(game.entities) do
		local nextRing = e.kind == "catchring" and game.player and game.player.catching and game:nextCatchRing() == e
		if e.body and not e.body:isDestroyed() and (e.kind == "driver" or nextRing or (e.kind == "station" and e.dock)) then
			local x, y = Pose.position(e)
			out[#out + 1] = {
				label = nextRing and ("Braking ring " .. e.index) or e.kind == "driver" and (e.gate and e.name or "Mass driver") or e.name,
				x = x, y = y, radius = e.radius or e.ringR or 0,
				col = e.kind == "driver" and (e.color or { 0.55, 0.85, 1 }) or { 1, 0.8, 0.45 },
			}
		end
	end
	for _, g in ipairs(game.moonGates or {}) do
		out[#out + 1] = { label = g.label, x = g.x, y = g.y, radius = 0, col = { 0.6, 0.85, 1 } }
	end
	-- active site jobs on this map (src/quest_sites.lua)
	if game.universe then
		for _, m in ipairs(require("src.quests").markers(game)) do
			out[#out + 1] = { label = m.label, x = m.x, y = m.y, radius = 0, col = { 0.55, 1, 0.6 } }
		end
	end
	return out
end

local function planetsOf(game)
	local out = {}
	for _, e in ipairs(game.entities) do
		if e.kind == "planet" and e.body and not e.body:isDestroyed() and e.radius then
			local x, y = Pose.position(e)
			out[#out + 1] = { x = x, y = y, r = e.radius }
		end
	end
	return out
end

-- A straight line to the target that cuts through a planet steers to a
-- spot just off the limb instead, on the side the line passes nearest.
local function detour(planets, px, py, wx, wy)
	for _, P in ipairs(planets) do
		local dx, dy = wx - px, wy - py
		local L2 = dx * dx + dy * dy
		if L2 > 0 then
			local t = ((P.x - px) * dx + (P.y - py) * dy) / L2
			if t > 0 and t < 1 then
				local qx, qy = px + dx * t - P.x, py + dy * t - P.y
				local d = sqrt(qx * qx + qy * qy)
				if d < P.r * 1.05 then
					if d < 1 then qx, qy, d = -dy, dx, sqrt(L2) end
					local k = P.r * 1.3 / d
					return P.x + qx * k, P.y + qy * k, true
				end
			end
		end
	end
	return wx, wy, false
end

-- Compass strip along the top, moving as one piece with the ship's nose:
-- 15-degree ticks, N/E/S/W (N is screen-up) and a pip for each destination
-- at the bearing you'd steer (around a planet if the line goes through it).
-- Labels sit on up to three rows under the strip so they never overlap;
-- the nearest win a spot and the rest show just their pip. T / Shift+T
-- picks a destination: it's always labelled, and keeps the edge marker.
HUD.navTarget = nil
local STRIP_SPAN = math.pi * 2 / 3          -- +-60 degrees either side of the nose
local navList = {}
function HUD.cycleNav(dir)
	if #navList == 0 then return end
	local i = 0
	for k, d in ipairs(navList) do if d.label == HUD.navTarget then i = k end end
	i = (i + dir) % (#navList + 1)      -- one past the end clears the pick
	HUD.navTarget = navList[i] and navList[i].label or nil
end

local function drawStrip(game)
	local p = game.player
	navList = {}
	if not p or p.dead or not p.body or p.body:isDestroyed() or game.state == "docked" then return end
	local w = lg.getWidth()
	local sw, sh = 440, 26
	local x0, y0 = max(412, (w - sw) / 2), 12
	local px, py = Pose.position(p)
	local nose = Pose.angle(p)
	local function rel(a) return (a - nose + math.pi) % (2 * math.pi) - math.pi end
	local function sx(a) return x0 + sw / 2 + rel(a) / STRIP_SPAN * sw end
	panel(x0, y0, sw, sh)
	lg.setScissor(x0 - 60, y0, sw + 120, sh + 60)
	lg.setFont(font(12))
	for i = 0, 23 do
		local a = -math.pi / 2 + i * math.pi / 12
		if math.abs(rel(a)) <= STRIP_SPAN / 2 then
			local x = sx(a)
			local card = ({ [0] = "N", [6] = "E", [12] = "S", [18] = "W" })[i]
			lg.setColor(DIM)
			if card then
				lg.setColor(INK)
				lg.printf(card, x - 10, y0 + 6, 20, "center")
			else
				lg.line(x, y0 + sh - (i % 2 == 0 and 9 or 5), x, y0 + sh - 2)
			end
		end
	end
	lg.setColor(INK)
	lg.polygon("fill", x0 + sw / 2, y0 + sh - 6, x0 + sw / 2 - 5, y0 + sh + 1, x0 + sw / 2 + 5, y0 + sh + 1)
	local planets = planetsOf(game)
	local all = destinations(game)
	local picked
	for _, d in ipairs(all) do
		local dx, dy = d.x - px, d.y - py
		d.dist = sqrt(dx * dx + dy * dy)
		local tx, ty, around = detour(planets, px, py, d.x, d.y)
		d.around, d.a = around, atan2(ty - py, tx - px)
		if d.label == HUD.navTarget then picked = d end
	end
	if HUD.navTarget and not picked then HUD.navTarget = nil end
	table.sort(all, function(a, b)
		if (a == picked) ~= (b == picked) then return a == picked end
		return a.dist < b.dist
	end)
	navList = all
	local rows = { {}, {}, {} }
	lg.setFont(font(10))
	local f = lg.getFont()
	for k = #all, 1, -1 do             -- far ones first, so near pips draw on top
		local d = all[k]
		local r = rel(d.a)
		local inView = math.abs(r) <= STRIP_SPAN / 2
		local x = inView and sx(d.a) or (r > 0 and x0 + sw - 6 or x0 + 6)
		d.px, d.inView = x, inView
		local sel = d == picked
		lg.setColor(d.col[1], d.col[2], d.col[3], (sel or inView) and 1 or 0.45)
		-- across the planet: a hollow pip
		local mode = d.around and "line" or "fill"
		if sel then lg.rectangle(mode, x - 3, y0 + 1, 6, sh - 2)
		else lg.rectangle(mode, x - 2, y0 + 2, 4, 7) end
	end
	for _, d in ipairs(all) do         -- nearest (and the pick) claim label room first
		if d.inView or d == picked then
			local text = ("%s %.1fk%s"):format(d.label, d.dist / 1000, d.around and ", far side" or "")
			local tw = f:getWidth(text)
			local lx = d.px - tw / 2
			for ri, row in ipairs(rows) do
				local free = true
				for _, span in ipairs(row) do
					if lx < span[2] + 6 and lx + tw > span[1] - 6 then free = false break end
				end
				if free then
					row[#row + 1] = { lx, lx + tw }
					local ly = y0 + sh + 3 + (ri - 1) * 13
					lg.setColor(d.col[1], d.col[2], d.col[3], d == picked and 1 or 0.8)
					if ri > 1 then lg.line(d.px, y0 + sh, d.px, ly + 1) end
					lg.print(text, lx, ly)
					break
				end
			end
		end
	end
	if not picked then
		lg.setColor(DIM)
		lg.printf("T: pick a destination", x0, y0 + sh + 44, sw, "center")
	end
	lg.setScissor()
end

local HELP = {
	"W engine  S retro  A/D side",
	"mouse aim (ship points at it)",
	"LMB primary   RMB secondary   MMB tertiary",
	"(pick each slot's fire group and ammo in the hold)",
	"E tractor beam",
	"G fly a drone (drone uplink)",
	"Q patch hull (patch kits)",
	"U in the hold: use the item under the mouse",
	"tap E open wreck/container   hold E tow",
	"Tab cargo hold   M local map",
	"T / Shift+T pick a nav destination",
	"Shift afterburner",
	"wheel zoom   F1 debug panel",
	"fly into a mass driver to travel   F1 debug travel   F2 shipyard",
	"F5 save   F9 load (docking autosaves)",
	"H hide help   Esc pause",
}

local function drawHelp()
	if not HUD.showHelp then return end
	local w = lg.getWidth()
	local pw, ph = 230, 18 + #HELP * 16
	panel(w - pw - 16, 12, pw, ph)
	lg.setFont(font(12))
	lg.setColor(DIM)
	for i, line in ipairs(HELP) do lg.print(line, w - pw - 4, 12 + 8 + (i - 1) * 16) end
end

-- y: where the list starts (default near the top; screens over the
-- game pass a spot that doesn't cover them)
-- The bar under the ship while an item is being used (src/item_use.lua),
-- and a line per running effect (a heal or buff over time).
local function drawCast(game)
	local p = game.player
	if not p or p.dead then return end
	local w, h = lg.getDimensions()
	local y = h * 0.62
	local c = p.casting
	if c then
		local bw = 220
		local x = (w - bw) / 2
		panel(x - 8, y - 6, bw + 16, 34)
		lg.setColor(DIM)
		lg.rectangle("line", x, y + 14, bw, 8)
		lg.setColor(AQUA)
		lg.rectangle("fill", x, y + 14, bw * min(1, c.t / c.time), 8)
		lg.setFont(font(12))
		lg.setColor(INK)
		lg.printf(c.label, x, y - 2, bw, "center")
		y = y + 40
	end
	if p.auras then
		lg.setFont(font(11))
		local data = require("src.data")
		local seen = {}
		for _, a in ipairs(p.auras) do
			local item = data.items[a.source]
			local name = item and item.use and item.use.label or (item and item.name) or "?"
			if not seen[name] then
				seen[name] = true
				lg.setColor(AQUA)
				lg.printf(("%s  %ds"):format(name, math.ceil(a.dur - a.t)), 0, y, w, "center")
				y = y + 14
			end
		end
	end
end

local function drawToasts(game, y)
	local w = lg.getWidth()
	y = y or 70
	for _, t in ipairs(game.toasts) do
		local a = min(1, (t.life - t.t) * 3)
		if t.big then
			lg.setFont(font(28))
			lg.setColor(AQUA[1], AQUA[2], AQUA[3], a)
			lg.printf(t.text, 0, y, w, "center")
			y = y + 38
		else
			lg.setFont(font(14))
			local c = (t.style == "pickup") and { 1, 0.9, 0.6 } or WARN
			lg.setColor(c[1], c[2], c[3], a)
			lg.printf(t.text, 0, y, w, "center")
			y = y + 20
		end
	end
end

-- Arrows at the screen edge pointing at enemies you can't see.
local function drawOffscreen(game)
	local cam = game.camera
	local w, h = lg.getDimensions()
	local cx, cy = w / 2, h / 2
	-- where you can go: mass drivers and stations, labelled at the edge
	-- of the screen when they're off it, or under them when they're on it
	lg.setFont(font(12))
	local fnt = lg.getFont()
	local planets = planetsOf(game)
	local px, py = cam.x, cam.y
	if game.player and game.player.body and not game.player.body:isDestroyed() then px, py = Pose.position(game.player) end
	local placed = {}
	-- nudge a label down/up until it clears the ones already drawn
	local function place(lx, ly, lw, dir)
		for _ = 1, 8 do
			local hit = false
			for _, r in ipairs(placed) do
				if lx < r[1] + r[3] and lx + lw > r[1] and ly < r[2] + 14 and ly + 14 > r[2] then hit = true break end
			end
			if not hit then break end
			ly = ly + 14 * dir
		end
		placed[#placed + 1] = { lx, ly, lw }
		return ly
	end
	local m = 40
	local function mark(label, wx, wy, radius, col)
		local sx, sy = cam:toScreen(wx, wy)
		local r = radius * cam.zoom
		-- visible if any of it is on screen, not just its centre
		if sx + r < 0 or sx - r > w or sy + r < 0 or sy - r > h then
			if label ~= HUD.navTarget then return end
			local tx, ty = cam:toScreen(detour(planets, px, py, wx, wy))
			local a = atan2(ty - cy, tx - cx)
			local ex = cos(a) ~= 0 and ((cos(a) > 0 and w - m or m) - cx) / cos(a) or math.huge
			local ey = sin(a) ~= 0 and ((sin(a) > 0 and h - m or m + 40) - cy) / sin(a) or math.huge
			local t = min(ex, ey)
			local ax, ay = cx + cos(a) * t, cy + sin(a) * t
			lg.setColor(col[1], col[2], col[3], 0.85)
			lg.setLineWidth(1.5)
			lg.circle("line", ax, ay, 6, 24)
			lg.polygon("fill",
				ax + cos(a) * 13, ay + sin(a) * 13,
				ax + cos(a + 0.5) * 8, ay + sin(a + 0.5) * 8,
				ax + cos(a - 0.5) * 8, ay + sin(a - 0.5) * 8)
			lg.setLineWidth(1)
			local fw = fnt:getWidth(label)
			local lx = max(4, min(w - fw - 4, ax - fw / 2))
			local dir = ay > cy and -1 or 1
			lg.print(label, lx, place(lx, ay + (dir < 0 and -24 or 10), fw, dir))
		else
			lg.setColor(col[1], col[2], col[3], 0.8)
			local fw = min(300, fnt:getWidth(label))
			local lx = sx - fw / 2
			lg.printf(label, lx, place(lx, sy + r + 10, fw, 1), fw, "center")
		end
	end
	if game.state ~= "docked" then
		for _, d in ipairs(destinations(game)) do mark(d.label, d.x, d.y, d.radius, d.col) end
	end
	for _, e in ipairs(game.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead and e.aggro then
			local sx, sy = cam:toScreen(Pose.position(e))
			if sx < 0 or sx > w or sy < 0 or sy > h then
				local a = atan2(sy - cy, sx - cx)
				local m = 26
				local tx = cos(a) > 0 and (w - m - cx) / cos(a) or (m - cx) / cos(a)
				local ty = sin(a) > 0 and (h - m - cy) / sin(a) or (m - cy) / sin(a)
				local t = min(math.abs(tx), math.abs(ty))
				local ax, ay = cx + cos(a) * t, cy + sin(a) * t
				lg.setColor(e.color[1], e.color[2], e.color[3], 0.85)
				lg.polygon("fill",
					ax + cos(a) * 10, ay + sin(a) * 10,
					ax + cos(a + 2.4) * 8, ay + sin(a + 2.4) * 8,
					ax + cos(a - 2.4) * 8, ay + sin(a - 2.4) * 8)
			end
		end
	end
end

local function drawReticle(game, aimX, aimY)
	local p = game.player
	if not p or p.dead then return end
	local sx, sy
	if Input.device == "pad" then sx, sy = game.camera:toScreen(aimX, aimY) else sx, sy = love.mouse.getPosition() end
	lg.setColor(AQUA[1], AQUA[2], AQUA[3], 0.9)
	lg.setLineWidth(1.5)
	lg.circle("line", sx, sy, 9)
	lg.line(sx - 15, sy, sx - 6, sy); lg.line(sx + 6, sy, sx + 15, sy)
	lg.line(sx, sy - 15, sx, sy - 6); lg.line(sx, sy + 6, sx, sy + 15)
end

local function drawDeath(game)
	if game.state ~= "dead" then return end
	local w, h = lg.getDimensions()
	local a = min(1, (game.time - (game.deathTime or 0)) * 1.5)
	lg.setColor(0, 0, 0, 0.45 * a)
	lg.rectangle("fill", 0, 0, w, h)
	lg.setFont(font(40))
	lg.setColor(WARN[1], WARN[2], WARN[3], a)
	lg.printf("SHIP LOST", 0, h * 0.36, w, "center")
	lg.setFont(font(16))
	lg.setColor(INK[1], INK[2], INK[3], a)
	local home = game:homeStation()
	lg.printf(("You ejected in a pod. Hull, modules and hold are in the wreck.\nKills: %d"):format(game.kills), 0, h * 0.36 + 56, w, "center")
	lg.setColor(DIM[1], DIM[2], DIM[3], a)
	lg.printf(home and ("Press R (or Start) to take a new ship at %s"):format(home.name) or "Press R (or Start) to launch a new ship",
		0, h * 0.36 + 110, w, "center")
end

-- Read-only view of the player's grid hold (debug panel: Show hold grid).
-- A first look at the packing; the real inventory screen comes later.
-- Ammo and weapons share one colour per ammo family, matching the shot in
-- flight (Render COLORS), so a gun, its rounds and its tracer all read alike.
-- Slot overlays (SLOT_COLOR) use hues none of these use.
local KIND_COLOR = {
	gun = { 0.92, 0.88, 0.66 }, artillery = { 0.88, 0.72, 0.4 }, laser = { 0.95, 0.6, 0.68 },
	missile = { 0.55, 0.72, 0.95 }, torpedo = { 0.45, 0.8, 0.82 }, drone = { 0.5, 0.82, 0.6 },
	crate = { 0.6, 0.65, 0.75 }, salvage = { 0.65, 0.48, 0.35 },
	module = { 0.95, 0.95, 0.95 }, container = { 0.95, 0.55, 0.2 },
}
-- Hardpoint weapons are warm (cream, gold, rose), bay weapons cool (blue,
-- teal, green); a slot takes its first weapon's colour. The rest pick hues no ammo uses.
local SLOT_COLOR = {
	hardpoint = KIND_COLOR.gun, bay = KIND_COLOR.missile, engine = { 0.8, 0.47, 0.37 },
	reactor = { 0.95, 0.82, 0.35 }, utility = { 0.8, 0.8, 0.82 }, computer = { 0.8, 0.8, 0.82 },
}
local function itemColor(item)
	if item.kind == "ammo" then
		return KIND_COLOR[item.family] or INK
	end
	-- a module's item card carries only its id; its weapon and family are on the module
	local m = item.kind == "module" and data.modules[item.module or item.id] or item
	local w = m.weapon
	if w then
		if data.LASERS[w.kind] then return KIND_COLOR.laser end
		local fam = data.chambers(w)[1]
		if fam and KIND_COLOR[fam] then return KIND_COLOR[fam] end
	end
	if item.kind == "module" and SLOT_COLOR[m.family] then return SLOT_COLOR[m.family] end
	return KIND_COLOR[item.kind] or INK
end

local function drawHoldGrid(game)
	local p = game.player
	if not (T.dev.showHold and p and not p.dead and p.hold) then return end
	local sh = lg.getHeight()
	local grids = p.hold.grids
	-- One cell size for every grid, small enough that they all fit stacked.
	local rows, cols = 0, 0
	for _, g in ipairs(grids) do rows, cols = rows + g.h, max(cols, g.w) end
	local cs = floor(min(18, (sh - 360 - #grids * 22) / rows, 330 / cols))
	local pw = cols * cs + 24
	local ph = rows * cs + #grids * 22 + 20
	local x, y = 16, 84
	panel(x, y, pw, ph)
	local gy = y + 10
	for _, g in ipairs(grids) do
		lg.setFont(font(12))
		lg.setColor(DIM)
		lg.print(("%s  %d x %d"):format(g.name, g.w, g.h), x + 12, gy)
		gy = gy + 18
		local gx = x + 12
		lg.setColor(AQUA[1], AQUA[2], AQUA[3], 0.12)
		for cy = 0, g.h - 1 do
			for cx = 0, g.w - 1 do lg.rectangle("line", gx + cx * cs + 0.5, gy + cy * cs + 0.5, cs - 1, cs - 1) end
		end
		lg.setFont(font(9))
		for _, s in ipairs(g.stacks) do
			local item = data.items[s.id]
			local c = itemColor(item)
			local rx, ry, rw, rh = gx + s.x * cs + 1, gy + s.y * cs + 1, s.w * cs - 2, s.h * cs - 2
			lg.setColor(c[1], c[2], c[3], 0.3)
			lg.rectangle("fill", rx, ry, rw, rh, 2, 2)
			lg.setColor(c[1], c[2], c[3], 0.9)
			lg.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1, 2, 2)
			if cs >= 14 and s.n > 1 then
				lg.setColor(INK)
				lg.printf(s.n, rx, ry + rh - 11, rw - 2, "right")
			end
		end
		gy = gy + g.h * cs + 4
	end
end

-- Shared with the cargo screen (src/ui/cargo.lua) so it looks the same.
HUD.panel, HUD.font, HUD.itemColor = panel, font, itemColor
HUD.KIND_COLOR, HUD.SLOT_COLOR = KIND_COLOR, SLOT_COLOR
HUD.AQUA, HUD.INK, HUD.DIM, HUD.WARN = AQUA, INK, DIM, WARN

-- uiOpen: the cargo screen is up, so no aim reticle.
-- In a transit lane: where you're headed and how far is left.
local function drawTrip(game)
	local trip, lane, p = game.trip, game.lane, game.player
	if not trip or not lane or not p or p.dead then return end
	local w = lg.getWidth()
	local s = game:toLane(Pose.position(p))
	local frac = math.max(0, math.min(1, (s + lane.half) / (lane.half * 2)))
	local bw = 360
	lg.setFont(font(13))
	lg.setColor(AQUA)
	local label = trip.au > 0 and ("TRANSIT TO %s   %.2f AU"):format(Fields[trip.to].name:upper(), trip.au)
		or ("TRANSIT TO %s"):format(Fields[trip.to].name:upper())
	lg.printf(label, w / 2 - bw, 52, bw * 2, "center")
	bar(w / 2 - bw / 2, 72, bw, 14, frac, AQUA, "", ("%d%%"):format(floor(frac * 100)))
end

-- Inbound to a catcher: your speed against the fastest the driver will
-- catch, and how many braking rings are left.
local function drawCatch(game)
	local p = game.player
	if not p or p.dead or not p.catching then return end
	local w, h = lg.getDimensions()
	local vx, vy = p.body:getLinearVelocity()
	local speed = sqrt(vx * vx + vy * vy)
	local left = 0
	for _, e in ipairs(game.entities) do if e.kind == "catchring" and not e.passed then left = left + 1 end end
	local ok = speed <= T.catchBaySpeed
	lg.setFont(font(15))
	lg.setColor(ok and { 0.5, 1, 0.6 } or WARN)
	lg.printf(("INBOUND  %d px/s   catch at %d or less"):format(speed, T.catchBaySpeed), 0, h - 150, w, "center")
	lg.setFont(font(12))
	lg.setColor(DIM)
	lg.printf(("%d braking ring%s ahead"):format(left, left == 1 and "" or "s"), 0, h - 128, w, "center")
end

-- Deep Scanner (a computer): hover a wreck or container within its range
-- and see what's inside before you open it.
drawScanTip = function(game, mx, my)
	local p = game.player
	local sc = p and not p.dead and game:computer(p, "scanner")
	if not sc then return end
	local wx, wy = game.camera:toWorld(mx, my)
	local px, py = Pose.position(p)
	local target
	for _, e in ipairs(game.entities) do
		if (e.kind == "husk" or e.kind == "container") and not e.dead and e.hold and not e.sat then
			local ex, ey = Pose.position(e)
			if (ex - wx) ^ 2 + (ey - wy) ^ 2 < (e.radius + 20) ^ 2 and (ex - px) ^ 2 + (ey - py) ^ 2 < sc.radarRange ^ 2 then target = e end
		end
	end
	if not target then return end
	local count = {}
	local order = {}
	for _, g in ipairs(target.hold.grids) do
		for _, st in ipairs(g.stacks) do
			if not count[st.id] then table.insert(order, st.id) end
			count[st.id] = (count[st.id] or 0) + st.n
		end
	end
	local lines = { "SCAN: " .. (#order == 0 and "empty" or (#order .. " kinds of cargo")) }
	for i, id in ipairs(order) do
		if i > 8 then table.insert(lines, ("+%d more"):format(#order - 8)) break end
		table.insert(lines, ("%s  x%d"):format(data.items[id] and data.items[id].name or id, count[id]))
	end
	lg.setFont(font(12))
	local w = 0
	for _, l in ipairs(lines) do w = max(w, lg.getFont():getWidth(l)) end
	w = w + 16
	local h = #lines * 16 + 8
	local sw, sh = lg.getDimensions()
	local x, y = min(mx + 16, sw - w - 4), min(my + 16, sh - h - 4)
	lg.setColor(0.02, 0.06, 0.09, 0.9)
	lg.rectangle("fill", x, y, w, h, 5, 5)
	for i, l in ipairs(lines) do
		lg.setColor(i == 1 and { 0.55, 0.9, 1 } or INK)
		lg.print(l, x + 8, y + 4 + (i - 1) * 16)
	end
end

-- Name of the pickup floating under the cursor (and how many).
local function drawPickupTip(game)
	local mx, my = love.mouse.getPosition()
	local best, bd = nil, 24 * 24
	for _, k in ipairs(game.pickups or {}) do
		local sx, sy = game.camera:toScreen(k.x, k.y)
		local d = (sx - mx) ^ 2 + (sy - my) ^ 2
		if d < bd then best, bd = k, d end
	end
	if not best then return drawScanTip(game, mx, my) end
	local item = data.items[best.item]
	if not item then return end
	local text = item.name .. ((best.count or 1) > 1 and ("  x" .. best.count) or "")
	lg.setFont(font(12))
	local w, h = lg.getFont():getWidth(text) + 16, 20
	local sw, sh = lg.getDimensions()
	local x, y = min(mx + 16, sw - w - 4), min(my + 16, sh - h - 4)
	lg.setColor(0.02, 0.06, 0.09, 0.9)
	lg.rectangle("fill", x, y, w, h, 5, 5)
	lg.setColor(INK)
	lg.print(text, x + 8, y + 3)
end

function HUD.draw(game, aimX, aimY, uiOpen)
	-- a level swap hidden in the lane's glow: washing over (game.cover),
	-- then clearing once the new level is in (game.flash)
	local wash = 0
	if game.cover then
		local u = math.min(1, game.cover.t / game.cover.life)
		wash = u * u
	end
	if game.flash then
		local a = 1 - game.flash.t / game.flash.life
		wash = math.max(wash, (game.flash.peak or 0.8) * a * a)
	end
	if wash > 0 then
		lg.setColor(0.85, 0.95, 1, wash)
		lg.rectangle("fill", 0, 0, lg.getDimensions())
	end
	drawStrip(game)
	drawOffscreen(game)
	drawTrip(game)
	drawCatch(game)
	if not uiOpen then drawHoldGrid(game) end
	drawTopBar(game)
	drawDeath(game)
	if uiOpen then return end            -- the cargo screen covers the rest; main draws toasts on top of it
	HUD.statusTop = nil
	drawStatus(game)
	require("src.notify").draw(game, (HUD.statusTop or lg.getHeight() - 16) - 10)
	drawCast(game)
	drawHelp()
	drawToasts(game)
	drawReticle(game, aimX, aimY)
	drawPickupTip(game)
end

HUD.drawToasts = drawToasts

return HUD
