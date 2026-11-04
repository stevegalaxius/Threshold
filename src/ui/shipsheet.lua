--[[
	Pieces the Hangar and Shipyard tabs share for showing one ship:

	  Sheet.outline   the hull, nose right, with its hardpoints numbered
	                  (the same markers as the Equipment panel)
	  Sheet.slots     a row per slot: number, family and size, module
	  Sheet.numbers   handling numbers for a hull, loadout and cargo mass
	  Sheet.compare   a label / value / difference table
	  Sheet.bar       a labelled meter (armor, hold)

	Every function takes a y and returns the y under what it drew, so the
	callers stack sections with a running cursor instead of fixed offsets.
]]

local data = require("src.data")
local stats = require("src.stats")
local HullShape = require("src.hullshape")
local HUD = require("src.hud")
local T = require("src.tuning")

local Sheet = {}
local lg = love.graphics
local max, min = math.max, math.min

local LABEL = { hardpoint = "HARDPOINT", bay = "BAY", engine = "ENGINE",
	reactor = "REACTOR", utility = "UTILITY", computer = "COMPUTER" }

function Sheet.slotLabel(slot)
	return LABEL[slot.family] .. (slot.size ~= "any" and (" " .. slot.size) or "")
end

function Sheet.isWeapon(slot) return slot.family == "hardpoint" or slot.family == "bay" end

-- Hull outline centred in the box, with numbered markers on placed slots.
function Sheet.outline(hull, paint, x, y, w, h, alpha)
	alpha = alpha or 1
	local shape = hull.shape
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	for k = 1, #shape, 2 do
		x1, x2 = min(x1, shape[k]), max(x2, shape[k])
		y1, y2 = min(y1, shape[k + 1]), max(y2, shape[k + 1])
	end
	local sc = min((w - 20) / (x2 - x1), (h - 10) / (y2 - y1))
	local ox, oy = x + w / 2 - (x1 + x2) / 2 * sc, y + h / 2 - (y1 + y2) / 2 * sc
	lg.push()
	lg.translate(ox, oy)
	lg.scale(sc)
	HullShape.draw(hull, paint, function(c) return { c[1], c[2], c[3], 0.12 * alpha } end,
		function(c) return { c[1], c[2], c[3], 0.85 * alpha } end, 1.5 / sc)
	lg.pop()
	lg.setLineWidth(1)
	lg.setFont(HUD.font(10))
	for i, slot in ipairs(hull.slots) do
		if slot.x then
			local sx, sy = ox + slot.x * sc, oy + (slot.y or 0) * sc
			lg.setColor(0.02, 0.06, 0.09, 0.9 * alpha)
			lg.circle("fill", sx, sy, 7)
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.8 * alpha)
			lg.circle("line", sx, sy, 7)
			lg.printf(i, sx - 7, sy - 6, 14, "center")
		end
	end
	return y + h
end

-- One compact row per slot. Returns the y under the last row drawn; rows
-- past maxY are left off with a "+n more" line.
function Sheet.slots(hull, loadout, x, y, w, maxY)
	local RH = 17
	for i, slot in ipairs(hull.slots) do
		if maxY and y + RH * 2 > maxY and i < #hull.slots then
			lg.setFont(HUD.font(11))
			lg.setColor(HUD.DIM)
			lg.print(("+%d more slots"):format(#hull.slots - i + 1), x, y + 1)
			return y + RH
		end
		local id = loadout and loadout[i]
		local m = id and data.modules[id]
		lg.setColor(0, 0, 0, 0.3)
		lg.rectangle("fill", x, y, w, RH - 2, 3, 3)
		lg.setFont(HUD.font(10))
		lg.setColor(Sheet.isWeapon(slot) and HUD.AQUA or HUD.DIM)
		lg.print((slot.x and (i .. " ") or "  ") .. Sheet.slotLabel(slot), x + 5, y + 2)
		lg.setFont(HUD.font(11))
		if m then lg.setColor(HUD.INK) else lg.setColor(HUD.WARN[1], HUD.WARN[2], HUD.WARN[3], 0.8) end
		lg.printf(m and m.name or "empty", x, y + 1, w - 5, "right")
		y = y + RH
	end
	return y
end

-- Handling numbers, in the same terms as the Equipment readout.
function Sheet.numbers(hull, loadout, cargoMass)
	local s = stats.compute(hull, loadout)
	local m = (s.mass + (cargoMass or 0)) * T.massScale
	local thrust = max(s.thrust, s.sideThrust * T.sideScale) * T.FORCE_PER_KN * T.thrustScale
	local weapons = 0
	for _, slot in ipairs(hull.slots) do if Sheet.isWeapon(slot) then weapons = weapons + 1 end end
	return {
		{ "Armor", s.armor, "%d" },
		{ "Hold", s.hold, "%d m3" },
		{ "Weapon slots", weapons, "%d" },
		{ "Top speed", math.sqrt(thrust / (hull.drag * T.dragScale)), "%.0f px/s" },
		{ "Acceleration", thrust / m, "%.0f px/s2" },
		{ "Turn", s.turn, "%.0f" },
		{ "Spare power", s.powerNet, "%+.0f/s" },
		{ "Mass", m, "%.0f t", lower = true },
	}
end

-- rows from Sheet.numbers; against (optional) the same for another ship.
-- Better is green, worse is red (mass: lower is better).
function Sheet.compare(rows, against, x, y, w)
	local RH = 19
	for k, r in ipairs(rows) do
		local yy = y + (k - 1) * RH
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		lg.print(r[1], x, yy)
		lg.setColor(HUD.INK)
		lg.printf(r[3]:format(r[2]), x, yy, w - 62, "right")
		local o = against and against[k]
		if o then
			local d = r[2] - o[2]
			local tiny = math.abs(d) < 0.5
			local good = (d > 0) ~= (r.lower == true)
			lg.setFont(HUD.font(11))
			if tiny then lg.setColor(HUD.DIM) elseif good then lg.setColor(0.4, 1, 0.55) else lg.setColor(HUD.WARN) end
			lg.printf(tiny and "=" or (d > 0 and "+" or "-") .. ("%.0f"):format(math.abs(d)), x, yy + 1, w, "right")
		end
	end
	return y + #rows * RH
end

-- "Armor   322 / 380" over a thin meter.
function Sheet.bar(label, value, total, x, y, w)
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.print(label, x, y)
	lg.setColor(HUD.INK)
	lg.printf(("%d / %d"):format(value, total), x, y, w, "right")
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.14)
	lg.rectangle("fill", x, y + 17, w, 4, 2, 2)
	lg.setColor(HUD.AQUA)
	lg.rectangle("fill", x, y + 17, w * max(0, min(1, total > 0 and value / total or 0)), 4, 2, 2)
	return y + 27
end

-- A small section label.
function Sheet.label(text, x, y)
	lg.setFont(HUD.font(10))
	lg.setColor(HUD.DIM)
	lg.print(text:upper(), x, y)
	return y + 15
end

-- A button: col tints it, enabled == false greys it out.
function Sheet.button(r, label, hot, col, enabled)
	col = col or HUD.AQUA
	local a = enabled == false and 0.06 or (hot and 0.4 or 0.18)
	lg.setColor(col[1], col[2], col[3], a)
	lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
	lg.setFont(HUD.font(13))
	lg.setColor(enabled == false and HUD.DIM or HUD.INK)
	lg.printf(label, r.x, r.y + (r.h - 14) / 2, r.w, "center")
end

Sheet.GREEN = { 0.3, 1, 0.5 }

return Sheet
