-- Shared ship weapon artwork for flight and the Shipyard preview.
local lg = love.graphics
local TURRET = { S = 4, M = 6, L = 9 }
local V = {}
function V.draw(w, col, dark, lineWidth)
		local s = w.slot
		local len = ({ S = 7, M = 10, L = 16 })[w.module.size] or 8
		local thick = (w.module.size == "L") and 5 or ((w.module.size == "M") and 4 or 3)
		if w.mount == "turret" then len, thick = len * 1.5, thick + 1 end
		lg.push()
		lg.translate(s.x or 0, s.y or 0)
		lg.rotate(w.aim or 0)
		lg.setColor(0.75, 0.78, 0.82)
		if w.w.kind == "laser" then lg.setColor(0.6, 0.95, 1) end
		if w.group == "auxiliary" then
			lg.rectangle("fill", -4, -4, 8, 8)
		else
			local n, gap = w.w.barrels or 1, w.w.barrelGap or 8
			for b = 1, n do
				local off = (b - (n + 1) / 2) * gap
				lg.rectangle("fill", 0, off - thick / 2, len, thick)
			end
		end
		if w.mount == "turret" then
			local r = TURRET[w.module.size] or 5
			lg.setColor(dark)
			lg.circle("fill", 0, 0, r)
			lg.setColor(col)
			lg.setLineWidth(lineWidth or 1.5)
			lg.circle("line", 0, 0, r)
		end
		lg.pop()
end
return V
