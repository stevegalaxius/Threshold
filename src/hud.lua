--[[
	Heads-up display: armor, power, weapons with ammo counts, hold, wave
	info, pickup messages, off-screen enemy markers and the aim reticle.
	Styled as worn Y2K glass panels; placeholder until the real UI pass.
]]

local data = require("src.data")
local Input = require("src.input")
local Render = require("src.render")
local T = require("src.tuning")

local HUD = { showHelp = true }

local lg = love.graphics
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
		local key = w.module.id
		local line = index[key]
		if not line then
			line = { name = w.module.name, n = 0, kind = w.w.kind, ammo = w.ammo, group = w.group, starved = false }
			index[key] = line
			table.insert(lines, line)
		end
		line.n = line.n + 1
		line.starved = line.starved or w.starved
	end
	local ORDER = { primary = 1, secondary = 2, auxiliary = 3 }
	table.sort(lines, function(a, b) return ORDER[a.group] < ORDER[b.group] end)
	return lines
end

local function drawStatus(game)
	local p = game.player
	if not p or p.dead then return end
	local w, h = lg.getDimensions()
	local lines = weaponLines(p)
	local ph = 112 + #lines * 18
	local x, y, pw = 16, h - ph - 16, 330
	panel(x, y, pw, ph)

	local s = p.stats
	local lowArmor = p.armor / s.armor < 0.3
	bar(x + 12, y + 12, pw - 24, 18, p.armor / s.armor, lowArmor and WARN or { 0.4, 0.85, 0.95 }, "ARMOR", ("%d / %d"):format(floor(p.armor + 0.5), floor(s.armor + 0.5)))
	local powerLabel = p.afterburn and "AFTERBURNER" or (p.burnerLocked and "POWER  (afterburner cooling)" or "POWER")
	bar(x + 12, y + 34, pw - 24, 14, p.power / max(1, s.powerCap), p.burnerLocked and { 1.0, 0.7, 0.35 } or { 0.55, 0.75, 1.0 }, powerLabel, ("%d  (+%d/s)"):format(floor(p.power), floor(s.powerNet)))
	-- tick where the afterburner relights after running dry
	lg.setColor(1, 1, 1, 0.5)
	local rx = x + 12 + (pw - 24) * T.boostRelight
	lg.line(rx, y + 33, rx, y + 49)

	lg.setFont(font(12))
	local ly = y + 56
	for _, line in ipairs(lines) do
		local tag = ({ primary = "LMB", secondary = "RMB", auxiliary = "MMB" })[line.group] or ""
		local label = tag .. "  " .. (line.n > 1 and (line.n .. "x ") or "") .. line.name
		lg.setColor(line.group == "auxiliary" and { 1, 0.85, 0.7 } or (line.group == "secondary" and { 0.8, 0.9, 1 } or INK))
		lg.print(label, x + 14, ly)
		local right, col
		if line.kind == "laser" then
			right, col = line.starved and "NO POWER" or "power", line.starved and WARN or DIM
		else
			local n = p.cargo[line.ammo] or 0
			right = ("%d  %s"):format(n, data.items[line.ammo].name:lower())
			col = (n == 0) and WARN or ((n < 20 and line.kind == "gun") and { 1, 0.8, 0.4 } or INK)
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

local function drawTopBar(game)
	local p = game.player
	local speed = 0
	if p and not p.dead then
		local vx, vy = p.body:getLinearVelocity()
		speed = sqrt(vx * vx + vy * vy)
	end
	local status = ("WAVE %d    KILLS %d    SPEED %d"):format(game.wave, game.kills, floor(speed))
	if not game.wavesOn then status = status .. "    (waves off)" end
	panel(16, 12, 330, 32)
	lg.setFont(font(14))
	lg.setColor(INK)
	lg.print(status, 28, 20)
	if game.field then
		lg.setFont(font(12))
		lg.setColor(DIM)
		lg.print(game.field.name .. "   (F2 next field)", 28, 50)
	end
end

local HELP = {
	"W engine  S retro  A/D side",
	"mouse aim (ship points at it)",
	"LMB primary   RMB secondary   MMB auxiliary",
	"Q auxiliary ammo size   E tractor beam",
	"tap E open wreck/container   hold E tow",
	"Tab cargo hold",
	"Shift afterburner",
	"wheel zoom   F1 debug panel",
	"F2 next playing field",
	"H hide help   Esc quit",
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

local function drawToasts(game)
	local w = lg.getWidth()
	local y = 70
	for _, t in ipairs(game.toasts) do
		local a = min(1, (t.life - t.t) * 3)
		if t.text:match("^WAVE") then
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
	for _, e in ipairs(game.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead then
			local sx, sy = cam:toScreen(e.body:getPosition())
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
	lg.printf(("You ejected in a pod. Hull, modules and hold are gone.\nWaves survived: %d    Kills: %d"):format(max(0, game.wave - 1), game.kills), 0, h * 0.36 + 56, w, "center")
	lg.setColor(DIM[1], DIM[2], DIM[3], a)
	lg.printf("Press R (or Start) to launch a new ship", 0, h * 0.36 + 110, w, "center")
end

-- Read-only view of the player's grid hold (debug panel: Show hold grid).
-- A first look at the packing; the real inventory screen comes later.
local KIND_COLOR = {
	gun = { 0.45, 0.75, 1 }, artillery = { 1, 0.55, 0.4 }, missile = { 0.4, 0.9, 0.65 },
	torpedo = { 0.95, 0.8, 0.35 }, drone = { 0.8, 0.55, 1 }, crate = { 0.6, 0.65, 0.75 }, salvage = { 0.75, 0.6, 0.45 },
	module = { 0.95, 0.95, 0.95 }, container = { 0.95, 0.55, 0.2 },
}

local function itemColor(item)
	if item.kind == "ammo" then return KIND_COLOR[item.family] or INK end
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
HUD.AQUA, HUD.INK, HUD.DIM, HUD.WARN = AQUA, INK, DIM, WARN

-- uiOpen: the cargo screen is up, so no aim reticle.
function HUD.draw(game, aimX, aimY, uiOpen)
	drawOffscreen(game)
	if not uiOpen then drawHoldGrid(game) end
	drawTopBar(game)
	drawDeath(game)
	if uiOpen then return end            -- the cargo screen covers the rest; main draws toasts on top of it
	drawStatus(game)
	drawHelp()
	drawToasts(game)
	drawReticle(game, aimX, aimY)
end

HUD.drawToasts = drawToasts

return HUD
