--[[
	The Services pane of the station screen's Manage tab (src/ui/stall.lua):
	what this station uses up just by having people aboard (food, water:
	src/station_needs.lua), and the crews on shore leave here
	(src/crew_fatigue.lua). One card per service: its base use, what the
	crews resting here add, stock on hand and how long it lasts.

	Read-only.
]]
local HUD = require("src.hud")
local Station = require("src.ui.station")
local L = require("src.locations")

local View = {}
local lg = love.graphics
local floor = math.floor
local PAD, GAP = 14, 12
local GOOD, WAIT = { 0.4, 1, 0.55 }, { 1, 0.78, 0.3 }

local function key(game)
	local st = game.player and game.player.dockState and game.player.dockState.station
	return st and L.canonical(st.key or st.locationId)
end

function View.has(st) return st ~= nil and not st.sat end

local function text(x, y, w, s, size, color, align)
	lg.setFont(HUD.font(size or 14)); lg.setColor(color or HUD.INK)
	lg.printf(s, x, y, w, align or "left")
end

local function hours(h)
	if h == math.huge then return "no use" end
	if h >= 48 then return ("%d days"):format(floor(h / 24)) end
	if h >= 1 then return ("%.1f h"):format(h) end
	return ("%d min"):format(floor(h * 60))
end

function View.draw(game, mx, my, x, y, w, h)
	local k = key(game)
	if not k then return end
	if not x then x, y, w, h = Station.body() end
	local u = game.universe
	local Services = require("src.station_needs")
	-- shore leave first: the crews these numbers feed
	local leave = Services.shoreLeave(u, k)
	Station.panel(x, y, w, 76)
	text(x + PAD, y + 10, w - PAD * 2, "SHORE LEAVE", 13, HUD.DIM)
	text(x + PAD, y + 30, w - PAD * 2, leave.resting == 1 and "1 crew resting here" or ("%d crews resting here"):format(leave.resting), 18)
	text(x + PAD, y + 10, w - PAD * 2, ("%s rates \194\183 from %s / min"):format(leave.kind:gsub("^%l", string.upper), HUD.credits(floor(leave.rate + 0.5))), 13, HUD.DIM, "right")
	text(x + PAD, y + 52, w - PAD * 2, "NPC crews pay to rest here after long runs, and eat and drink while they do.", 12, HUD.DIM)
	local rows = Services.status(u, k)
	local cy = y + 76 + GAP
	if #rows == 0 then
		Station.panel(x, cy, w, 60)
		text(x + PAD, cy + PAD, w - PAD * 2, "This station uses no food or water.", 15, HUD.DIM)
		return
	end
	local cols = w >= 760 and 2 or 1
	local cw = floor((w - GAP * (cols - 1)) / cols)
	for i, s in ipairs(rows) do
		local c = (i - 1) % cols
		local cx = x + c * (cw + GAP)
		local ry = cy + floor((i - 1) / cols) * (150 + GAP)
		Station.panel(cx, ry, cw, 150)
		text(cx + PAD, ry + 10, cw - PAD * 2, s.name, 18)
		local col = s.condition == "Supplied" and GOOD or WAIT
		text(cx + PAD, ry + 12, cw - PAD * 2, s.condition, 14, s.condition == "Out" and HUD.WARN or col, "right")
		local lines = {
			{ "Station use", ("%g %s / h"):format(floor(s.base * 10 + 0.5) / 10, s.unit) },
			{ "Resting crews", ("+%g %s / h"):format(floor(s.resident * 10 + 0.5) / 10, s.unit) },
			{ "On hand", ("%d %s"):format(s.stock, s.unit) },
			{ "Lasts", s.make > 0 and ("%s (grows %g / h)"):format(hours(s.hours), s.make) or hours(s.hours) },
		}
		for j, line in ipairs(lines) do
			local ly = ry + 40 + (j - 1) * 24
			text(cx + PAD, ly, cw - PAD * 2, line[1], 13, HUD.DIM)
			text(cx + PAD, ly, cw - PAD * 2, line[2], 13, HUD.INK, "right")
		end
	end
end

return View
