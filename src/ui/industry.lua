--[[
	The Industry tab of the station screen, at stations with installed
	facilities (src/world_layout.lua facilities, src/industry.lua). One
	card per installation: its capacity and policy, then each recipe with
	its share of the capacity, what it's doing now (Industry.status),
	what it needs (available / on hand) and what it makes (stock / room
	and the local price, or the ship and where it goes).

	Read-only. src/ui/cargo.lua owns the tabs.
]]

local data = require("src.data")
local HUD = require("src.hud")
local Station = require("src.ui.station")

local View = { scroll = 0 }

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min
local PAD, GAP = 14, 12
local GOOD, WAIT = { 0.4, 1, 0.55 }, { 1, 0.78, 0.3 }

local POLICY = {
	fixed = "Fixed shares", profit = "Follows profit", adaptive = "Follows demand", orders = "Builds to order",
}

local function station(game)
	local p = game.player
	return p and p.dockState and p.dockState.station
end

function View.has(st)
	if not st then return false end
	local I = require("src.industry")
	return next(I.installations(require("src.stockpile").key(st))) ~= nil
end

local function itemName(id) return data.items[id] and data.items[id].name or id end

local function recipeName(c)
	local out = {}
	for _, o in ipairs(require("src.commodities").outputs(c)) do
		out[#out + 1] = o.kind == "ship" and data.hulls[o.hull].name or itemName(o.item)
	end
	return table.concat(out, " + ")
end

local function statusColor(text)
	if text:find("^Producing") or text:find("^Building") or text:find("^Consuming") then return GOOD end
	if text:find("^Waiting") or text:find("^Queued") or text:find("^Paused") or text:find("^Idle") then return WAIT end
	return HUD.DIM
end

-- Each installation as a block of rows, built fresh each frame.
local function cards(game, st)
	local I, C, S = require("src.industry"), require("src.commodities"), require("src.stockpile")
	local u, key = game.universe, S.key(st)
	local ids = {}
	for id in pairs(I.installations(key)) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local inst = I.installations(key)[id]
		local def = I.definition(id, inst)
		local card = { id = id, capacity = inst.capacity, policy = POLICY[def.policy] or def.policy, recipes = {} }
		for _, rid in ipairs(def.recipes) do
			local c = C.byId[rid]
			if c then
				if not c.stockless then S.count(u, key, c.item) end   -- catch production up
				local r = { name = recipeName(c), share = I.scale(u, key, c), status = I.status(u, key, id, c), time = c.time or 1, lines = {} }
				for _, input in ipairs(C.inputs(c)) do
					r.lines[#r.lines + 1] = { "in", ("%s %s each"):format(input.n < 1 and ("%.2f"):format(input.n) or input.n, itemName(input.item)),
						("%d available / %d on hand"):format(S.available(u, key, input.item), S.count(u, key, input.item)) }
				end
				for _, o in ipairs(C.outputs(c)) do
					if o.kind == "ship" then
						local lot, dealer = require("src.dealers").state(u, key)
						r.lines[#r.lines + 1] = { "out", "1 " .. data.hulls[o.hull].name,
							lot and ("to the lot \194\183 %d there"):format(#lot.lots) or "to the dealership" }
					else
						local price = c.market ~= false and require("src.markets").price(u, key, o.item)
						r.lines[#r.lines + 1] = { "out", ("%d %s"):format(o.n, itemName(o.item)),
							("%d / %d in stock%s"):format(S.count(u, key, o.item), o.cap or c.cap or 0,
								price and ("  \194\183  %s each"):format(HUD.credits(floor(price + 0.5))) or "") }
					end
				end
				card.recipes[#card.recipes + 1] = r
			end
		end
		out[#out + 1] = card
	end
	return out
end

local function cardHeight(card)
	local h = 44
	for _, r in ipairs(card.recipes) do h = h + 46 + #r.lines * 18 + 8 end
	return h
end

function View.draw(game, mx, my)
	local st = station(game)
	if not st then return end
	local x, y, w, h = Station.body()
	local list = cards(game, st)
	if #list == 0 then
		Station.panel(x, y, w, h)
		lg.setFont(HUD.font(15)); lg.setColor(HUD.DIM)
		lg.printf("Nothing is produced here.", x + PAD, y + PAD, w - PAD * 2)
		return
	end
	-- two columns of cards, packed top to bottom
	local cols = w >= 900 and 2 or 1
	local cw = floor((w - GAP * (cols - 1)) / cols)
	local colY = {}
	for i = 1, cols do colY[i] = y - View.scroll end
	local bottom = y
	lg.setScissor(x, y, w, h)
	for _, card in ipairs(list) do
		local k = 1
		for i = 2, cols do if colY[i] < colY[k] then k = i end end
		local cx, cy, ch = x + (k - 1) * (cw + GAP), colY[k], cardHeight(card)
		Station.panel(cx, cy, cw, ch)
		lg.setFont(HUD.font(18)); lg.setColor(HUD.INK)
		lg.print((card.id:gsub("_", " "):gsub("^%l", string.upper)), cx + PAD, cy + 10)
		lg.setFont(HUD.font(13)); lg.setColor(HUD.DIM)
		lg.printf(("%s \194\183 %g units / hour"):format(card.policy, card.capacity), cx, cy + 14, cw - PAD, "right")
		local ry = cy + 44
		for _, r in ipairs(card.recipes) do
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.08)
			lg.rectangle("fill", cx + 8, ry - 4, cw - 16, 46 + #r.lines * 18, 4, 4)
			lg.setFont(HUD.font(15)); lg.setColor(HUD.INK)
			lg.print(r.name, cx + PAD, ry)
			lg.setFont(HUD.font(12)); lg.setColor(HUD.DIM)
			lg.printf(("%d%% of capacity \194\183 %g h per batch"):format(floor(r.share * 100 + 0.5), r.time), cx, ry + 2, cw - PAD, "right")
			-- share bar
			lg.setColor(0, 0, 0, 0.35); lg.rectangle("fill", cx + PAD, ry + 21, cw - PAD * 2, 3)
			lg.setColor(HUD.AQUA); lg.rectangle("fill", cx + PAD, ry + 21, (cw - PAD * 2) * min(1, max(0, r.share)), 3)
			lg.setFont(HUD.font(13)); lg.setColor(statusColor(r.status))
			lg.print(r.status, cx + PAD, ry + 26)
			local ly = ry + 46
			for _, line in ipairs(r.lines) do
				lg.setFont(HUD.font(12))
				lg.setColor(HUD.DIM); lg.print(line[1] == "in" and "NEEDS" or "MAKES", cx + PAD, ly)
				lg.setColor(HUD.INK); lg.print(line[2], cx + PAD + 56, ly)
				lg.setColor(HUD.DIM); lg.printf(line[3], cx, ly, cw - PAD, "right")
				ly = ly + 18
			end
			ry = ly + 8
		end
		colY[k] = cy + ch + GAP
		bottom = max(bottom, colY[k] + View.scroll)
	end
	lg.setScissor()
	View.maxScroll = max(0, bottom - y - h)
	View.scroll = min(View.scroll, View.maxScroll)
end

function View.wheelmoved(game, dy)
	View.scroll = max(0, min(View.maxScroll or 0, View.scroll - dy * 40))
end

return View
