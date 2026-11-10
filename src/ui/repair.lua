--[[
	The Repair tab of the station screen, at stations whose definition
	lists "repair" in services. Every ship you have here (the one you're
	flying first, then stored ones) gets a row: armor meter, what's
	missing and what fixing it costs at this station's rate
	(Game.repairRate). Repair starts a paid-as-completed job; Repair all
	starts one for each damaged ship. Plate shortages slow the work.

	This only draws and reports clicks; src/ui/cargo.lua owns the tabs.
]]

local data = require("src.data")
local HUD = require("src.hud")
local Station = require("src.ui.station")
local Sheet = require("src.ui.shipsheet")
local Hangar = require("src.ui.hangar")

local Repair = {}

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min
local PAD, ROW_H, HEAD = 14, 72, 52

local function inRect(r, x, y)
	return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Repair.layout(game)
	local p = game.player
	local st = p and p.dockState and p.dockState.station
	if not st then return nil end
	local sw, sh = lg.getDimensions()
	local y = 112
	local ph = max(360, sh - y - 80)
	local tw = min(sw - 48, 820)
	local x = floor((sw - tw) / 2)
	local L = { x = x, y = y, w = tw, h = ph, station = st, rows = {} }
	local owners = { p }
	for _, rec in ipairs(game:hangar(st)) do owners[#owners + 1] = rec end
	local visible = max(1, floor((ph - HEAD - 60) / ROW_H))
	for i, owner in ipairs(owners) do
		if i <= visible then
			local ry = y + HEAD + (i - 1) * ROW_H
			table.insert(L.rows, { owner = owner, x = x + PAD, y = ry, w = tw - PAD * 2, h = ROW_H - 6,
				button = { x = x + tw - PAD - 210, y = ry + 16, w = 200, h = 32 } })
		end
	end
	L.more = #owners - #L.rows
	L.all = { x = x + tw - PAD - 210, y = y + ph - PAD - 34, w = 200, h = 34 }
	return L
end

local function buttonLabel(game, st, owner)
	if owner.repairOrder then return ('Cancel (%d pts left)'):format(math.ceil(owner.repairOrder.remaining)),true end
	local missing, cost = game:repairQuote(st, owner)
	if missing <= 0 then return "No damage", false end
	local rate = game.repairRate(st)
	local afford = rate > 0 and min(missing, floor(game:credits() / rate)) or missing
	if afford <= 0 then return "Not enough credits", false end
	if afford < missing then return ("Repair %d pts \194\183 %s"):format(afford, HUD.credits(afford * rate)), true end
	return ("Repair \194\183 %s"):format(HUD.credits(cost)), true
end

function Repair.draw(game, mx, my)
	local L = Repair.layout(game)
	if not L then return end
	local st, p = L.station, game.player
	Station.panel(L.x, L.y, L.w, L.h)
	lg.setFont(HUD.font(18))
	lg.setColor(HUD.INK)
	lg.print("Repair bay \194\183 " .. st.name, L.x + PAD, L.y + 12)
	lg.setFont(HUD.font(14))
	lg.setColor(HUD.DIM)
	lg.printf(("%s per armor point"):format(HUD.credits(game.repairRate(st))), L.x, L.y + 16, L.w - PAD, "right")
	local P=require('src.repair_materials')
	local available=P.available(game.universe,st.key or st.locationId)
	lg.setFont(HUD.font(11))
	lg.print(('Steel on hand: %.1f plates | 1 plate / %d armor | %s'):format(available/P.points,P.points,
	 available>0 and 'normal repair speed' or 'emergency repairs at quarter speed'),L.x+PAD,L.y+35)

	local total = 0
	for _, r in ipairs(L.rows) do
		local owner = r.owner
		local flying = owner == p
		local hull = flying and p.hull or data.hulls[owner.hull]
		local missing, cost, full = game:repairQuote(st, owner)
		total = total + cost
		lg.setColor(0, 0, 0, 0.3)
		lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
		local col = flying and p.color or owner.color or p.color
		Hangar.drawHull(hull, r.x + 8, r.y + 8, 90, r.h - 16, false, col, 1)
		lg.setFont(HUD.font(16))
		lg.setColor(HUD.INK)
		lg.print(hull.name, r.x + 112, r.y + 8)
		lg.setFont(HUD.font(12))
		lg.setColor(flying and { 0.4, 1, 0.55 } or HUD.DIM)
		lg.print(flying and "FLYING" or game:shipParkingLabel(st, owner), r.x + 112, r.y + 30)
		local bx, bw = r.x + 250, r.button.x - r.x - 270
		local armor = floor(owner.armor or full)
		Sheet.bar("Armor", armor, full, bx, r.y + 10, bw)
		lg.setFont(HUD.font(12))
		if missing > 0 then lg.setColor(HUD.WARN) else lg.setColor(HUD.DIM) end
		lg.print(missing > 0 and ("%d missing"):format(missing) or "undamaged", bx, r.y + 42)
		local label, ok = buttonLabel(game, st, owner)
		Sheet.button(r.button, label, inRect(r.button, mx, my), Sheet.GREEN, ok)
	end
	if L.more > 0 then
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		lg.print(("+%d more ships (Repair all covers them)"):format(L.more), L.x + PAD, L.all.y - 24)
	end
	lg.setFont(HUD.font(14))
	lg.setColor(HUD.DIM)
	lg.print(total > 0 and ("Everything here: %s"):format(HUD.credits(total)) or "Nothing here needs repair.",
		L.x + PAD, L.all.y + 8)
	Sheet.button(L.all, "Repair all", inRect(L.all, mx, my), Sheet.GREEN, total > 0 and game:credits() > 0)
end

-- What a click asks for: { repair = owner }, { repairAll = true } or nil.
function Repair.mousepressed(game, mx, my, button)
	local L = Repair.layout(game)
	if not L or button ~= 1 then return nil end
	for _, r in ipairs(L.rows) do
		if inRect(r.button, mx, my) then return r.owner.repairOrder and {cancelRepair=r.owner} or {repair=r.owner} end
	end
	if inRect(L.all, mx, my) then return { repairAll = true } end
end

return Repair
