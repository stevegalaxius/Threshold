--[[
	The Shipyard's drawing canvas: the view (pan and zoom), the grid, the
	design's parts, and the mouse tools that draw and edit them.

	Ship space has the nose along +x, like data/hulls.lua. Every function
	takes the editor state E (src/editor/init.lua).
]]

local HullShape = require("src.hullshape")

local Canvas = {}

local lg = love.graphics
local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt

local VERTEX_PX = 8      -- how close the mouse has to be to grab a vertex
local EDGE_PX = 6        -- or an edge, to insert a point on it
local SLOT_PX = 7        -- radius of a slot's hardpoint marker

local SLOT_COLORS = {
	primary = { 1, 0.45, 0.35 }, secondary = { 1, 0.7, 0.3 }, auxiliary = { 0.9, 0.5, 1 },
	engine = { 0.4, 0.8, 1 }, reactor = { 0.5, 1, 0.5 }, utility = { 0.8, 0.8, 0.8 },
	thruster = { 0.4, 1, 0.9 }, computer = { 0.8, 0.8, 1 },
}
Canvas.SLOT_COLORS = SLOT_COLORS

-- The placed slot under a screen point.
function Canvas.slotAt(E, sx, sy)
	for i, slot in ipairs(E.design.slots or {}) do
		if slot.x then
			local x, y = Canvas.toScreen(E, slot.x, slot.y or 0)
			if (x - sx) ^ 2 + (y - sy) ^ 2 <= (SLOT_PX + 3) ^ 2 then return i end
		end
	end
	return nil
end

-- View transform ----------------------------------------------------------

function Canvas.toScreen(E, x, y)
	local v = E.view
	return lg.getWidth() / 2 + (x - v.x) * v.zoom, lg.getHeight() / 2 + (y - v.y) * v.zoom
end

function Canvas.toWorld(E, sx, sy)
	local v = E.view
	return (sx - lg.getWidth() / 2) / v.zoom + v.x, (sy - lg.getHeight() / 2) / v.zoom + v.y
end

function Canvas.snap(E, x, y)
	if not E.snap or love.keyboard.isDown("lalt", "ralt") then return floor(x + 0.5), floor(y + 0.5) end
	local g = E.grid
	return floor(x / g + 0.5) * g, floor(y / g + 0.5) * g
end

function Canvas.zoomAt(E, sx, sy, factor)
	local wx, wy = Canvas.toWorld(E, sx, sy)
	E.view.zoom = max(0.1, min(40, E.view.zoom * factor))
	local nx, ny = Canvas.toWorld(E, sx, sy)
	E.view.x, E.view.y = E.view.x + wx - nx, E.view.y + wy - ny
end

-- Geometry ----------------------------------------------------------------

local function inside(shape, x, y)
	local hit = false
	local n = #shape
	local jx, jy = shape[n - 1], shape[n]
	for k = 1, n, 2 do
		local ix, iy = shape[k], shape[k + 1]
		if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then hit = not hit end
		jx, jy = ix, iy
	end
	return hit
end
Canvas.inside = inside

local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = l2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
	local qx, qy = ax + dx * t, ay + dy * t
	return sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

-- The mirror image of an outline across the axis, winding kept.
function Canvas.reflected(shape)
	local out = {}
	for k = #shape - 1, 1, -2 do
		table.insert(out, shape[k]); table.insert(out, -shape[k + 1])
	end
	return out
end

function Canvas.area(shape)
	local a = 0
	local n = #shape
	for k = 1, n, 2 do
		local j = (k + 2 > n) and 1 or k + 2
		a = a + shape[k] * shape[j + 1] - shape[j] * shape[k + 1]
	end
	return abs(a) / 2
end

function Canvas.centre(shape)
	local cx, cy, n = 0, 0, #shape / 2
	for k = 1, #shape, 2 do cx, cy = cx + shape[k], cy + shape[k + 1] end
	return cx / n, cy / n
end

-- Which part is under a world point (topmost first), skipping hidden and
-- locked ones. Mirror twins count as their part.
function Canvas.partAt(E, x, y)
	local parts = E.design.parts
	for i = #parts, 1, -1 do
		local p = parts[i]
		if not p.hidden and not p.locked then
			if inside(p.shape, x, y) then return i end
			if p.mirror and inside(Canvas.reflected(p.shape), x, y) then return i end
		end
	end
	return nil
end

-- The vertex of the selected part near a screen point (index of its x).
function Canvas.vertexAt(E, sx, sy)
	local p = E.sel and E.design.parts[E.sel]
	if not p or p.locked then return nil end
	local s = p.shape
	for k = 1, #s, 2 do
		local vx, vy = Canvas.toScreen(E, s[k], s[k + 1])
		if abs(vx - sx) <= VERTEX_PX and abs(vy - sy) <= VERTEX_PX then return k end
	end
	return nil
end

-- The edge of the selected part near a screen point: the index of the
-- vertex it starts at.
function Canvas.edgeAt(E, sx, sy)
	local p = E.sel and E.design.parts[E.sel]
	if not p or p.locked then return nil end
	local s = p.shape
	local n = #s
	for k = 1, n, 2 do
		local j = (k + 2 > n) and 1 or k + 2
		local ax, ay = Canvas.toScreen(E, s[k], s[k + 1])
		local bx, by = Canvas.toScreen(E, s[j], s[j + 1])
		if segDist(sx, sy, ax, ay, bx, by) <= EDGE_PX then return k end
	end
	return nil
end

-- Mouse tools ---------------------------------------------------------------

function Canvas.mousepressed(E, sx, sy, button)
	local wx, wy = Canvas.toWorld(E, sx, sy)
	if button == 2 and E.tool == "draw" and E.drawing then
		-- right click while drawing takes the last point back
		table.remove(E.drawing); table.remove(E.drawing)
		if #E.drawing == 0 then E.drawing = nil end
		return
	end
	if button == 2 or button == 3 then
		E.drag = { kind = "pan", sx = sx, sy = sy, vx = E.view.x, vy = E.view.y }
		return
	end
	if button ~= 1 then return end
	local now = love.timer.getTime()
	local double = E.lastClick and now - E.lastClick.t < 0.3 and abs(E.lastClick.x - sx) < 6 and abs(E.lastClick.y - sy) < 6
	E.lastClick = { t = now, x = sx, y = sy }

	if E.tool == "draw" then
		local px, py = Canvas.snap(E, wx, wy)
		local d = E.drawing
		if d and #d >= 6 then
			local fx, fy = Canvas.toScreen(E, d[1], d[2])
			if abs(fx - sx) <= VERTEX_PX and abs(fy - sy) <= VERTEX_PX then
				E.finishDrawing()
				return
			end
		end
		E.drawing = E.drawing or {}
		table.insert(E.drawing, px); table.insert(E.drawing, py)
		return
	end

	if E.tool == "rect" then
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "rect", x1 = px, y1 = py, x2 = px, y2 = py }
		return
	end

	-- select tool: a vertex of the selected part, an edge (double click
	-- inserts a point), a part, or nothing
	local si = E.showSlots ~= false and Canvas.slotAt(E, sx, sy)
	if si then
		E.slotSel = si
		E.drag = { kind = "slot", i = si, pushed = false }
		return
	end
	local k = Canvas.vertexAt(E, sx, sy)
	if k then
		E.vsel = k
		E.drag = { kind = "vertex", k = k, pushed = false }
		return
	end
	if double then
		local e = Canvas.edgeAt(E, sx, sy)
		if e then
			E.pushUndo()
			local px, py = Canvas.snap(E, wx, wy)
			local s = E.design.parts[E.sel].shape
			table.insert(s, e + 2, py)
			table.insert(s, e + 2, px)
			E.vsel = e + 2
			E.drag = { kind = "vertex", k = e + 2, pushed = true }
			return
		end
	end
	local i = Canvas.partAt(E, wx, wy)
	E.vsel = nil
	if i then
		E.sel = i
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "part", lx = px, ly = py, pushed = false }
	else
		E.sel = nil
	end
end

function Canvas.mousemoved(E, sx, sy)
	local d = E.drag
	if not d then return end
	if d.kind == "pan" then
		E.view.x = d.vx - (sx - d.sx) / E.view.zoom
		E.view.y = d.vy - (sy - d.sy) / E.view.zoom
		return
	end
	local wx, wy = Canvas.toWorld(E, sx, sy)
	local px, py = Canvas.snap(E, wx, wy)
	if d.kind == "rect" then
		d.x2, d.y2 = px, py
	elseif d.kind == "vertex" then
		local s = E.design.parts[E.sel].shape
		if s[d.k] ~= px or s[d.k + 1] ~= py then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			s[d.k], s[d.k + 1] = px, py
		end
	elseif d.kind == "slot" then
		local slot = E.design.slots[d.i]
		if slot and (slot.x ~= px or slot.y ~= py) then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			slot.x, slot.y = px, py
		end
	elseif d.kind == "part" then
		local dx, dy = px - d.lx, py - d.ly
		if dx ~= 0 or dy ~= 0 then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			local s = E.design.parts[E.sel].shape
			for k = 1, #s, 2 do s[k], s[k + 1] = s[k] + dx, s[k + 1] + dy end
			d.lx, d.ly = px, py
		end
	end
end

function Canvas.mousereleased(E, sx, sy, button)
	local d = E.drag
	E.drag = nil
	if d and d.kind == "rect" then
		local x1, x2 = min(d.x1, d.x2), max(d.x1, d.x2)
		local y1, y2 = min(d.y1, d.y2), max(d.y1, d.y2)
		if x2 - x1 >= 1 and y2 - y1 >= 1 then
			E.addPart({ x1, y1, x2, y1, x2, y2, x1, y2 })
		end
	end
end

-- Drawing -------------------------------------------------------------------

local function grid(E)
	local w, h = lg.getWidth(), lg.getHeight()
	local x1, y1 = Canvas.toWorld(E, 0, 0)
	local x2, y2 = Canvas.toWorld(E, w, h)
	local g = E.grid
	while g * E.view.zoom < 6 do g = g * 2 end
	lg.setLineWidth(1)
	for x = floor(x1 / g) * g, x2, g do
		local sx = Canvas.toScreen(E, x, 0)
		local major = x % (g * 8) == 0
		lg.setColor(1, 1, 1, major and 0.09 or 0.035)
		lg.line(sx, 0, sx, h)
	end
	for y = floor(y1 / g) * g, y2, g do
		local _, sy = Canvas.toScreen(E, 0, y)
		local major = y % (g * 8) == 0
		lg.setColor(1, 1, 1, major and 0.09 or 0.035)
		lg.line(0, sy, w, sy)
	end
	-- the axes: the ship's spine (y = 0) and its centre (x = 0)
	local ox, oy = Canvas.toScreen(E, 0, 0)
	lg.setColor(0.4, 0.7, 1, 0.35)
	lg.line(0, oy, w, oy)
	lg.line(ox, 0, ox, h)
	-- the nose arrow
	lg.setColor(0.4, 0.7, 1, 0.8)
	local ax = ox + 60
	lg.polygon("fill", ax + 12, oy, ax, oy - 6, ax, oy + 6)
	lg.print("nose", ax + 16, oy - 7)
end

function Canvas.draw(E)
	lg.push("all")
	lg.clear(0.04, 0.045, 0.06)
	grid(E)
	local v = E.view
	lg.push()
	lg.translate(lg.getWidth() / 2 - v.x * v.zoom, lg.getHeight() / 2 - v.y * v.zoom)
	lg.scale(v.zoom)

	E.errors = {}
	-- each part on its own, so a broken one shows red without hiding the rest
	local col = E.paint
	-- break-apart preview: parts that can be shot off drift out from the
	-- core and back
	local corePart = E.coreIndex and E.design.parts[E.coreIndex]
	local ccx, ccy = 0, 0
	if corePart and #corePart.shape >= 2 then ccx, ccy = Canvas.centre(corePart.shape) end
	local spread = (1 - math.cos(love.timer.getTime() * 1.6)) * 0.5 * 40
	for i, p in ipairs(E.design.parts) do
		if not p.hidden then
			local list = { p }
			if p.mirror then
				local twin = {}
				for k, x in pairs(p) do twin[k] = x end
				twin.shape = Canvas.reflected(p.shape)
				table.insert(list, twin)
			end
			for _, q in ipairs(list) do
				local moved = E.preview == "break" and i ~= E.coreIndex and q.breakable ~= false and q.collide ~= false and #q.shape >= 2
				if moved then
					local qx, qy = Canvas.centre(q.shape)
					local dx, dy = qx - ccx, qy - ccy
					local l = math.max(sqrt(dx * dx + dy * dy), 1)
					lg.push()
					lg.translate(dx / l * spread, dy / l * spread)
				end
				local s, tris = HullShape.check(q.shape)
				if not s then
					E.errors[i] = tris
					lg.setColor(1, 0.2, 0.2, 0.35)
					if #q.shape >= 6 then lg.polygon("line", q.shape) end
				else
					local pc = HullShape.color(q, col)
					local wreck = E.preview == "wreck" or E.preview == "break"
					local fillCol = wreck and { pc[1] * 0.12, pc[2] * 0.12, pc[3] * 0.12 } or { pc[1] * 0.22, pc[2] * 0.22, pc[3] * 0.22 }
					if q.layer == "glow" then fillCol = wreck and { 0.05, 0.05, 0.05 } or pc end
					if q.layer == "detail" then fillCol = wreck and fillCol or { pc[1] * 0.5, pc[2] * 0.5, pc[3] * 0.5 } end
					if E.preview == "collision" and q.collide == false then fillCol = { 0.15, 0.15, 0.15, 0.4 } end
					lg.setColor(fillCol)
					if q.layer == "glow" and not wreck then lg.setBlendMode("add") end
					for _, t in ipairs(tris) do lg.polygon("fill", t) end
					lg.setBlendMode("alpha")
					if q.layer == nil or q.layer == "hull" then
						lg.setColor(wreck and { pc[1] * 0.35, pc[2] * 0.35, pc[3] * 0.35 } or pc)
						lg.setLineWidth(1.5 / v.zoom)
						lg.polygon("line", s)
					end
					if E.preview == "collision" and q.collide ~= false then
						lg.setColor(0.3, 1, 0.5, 0.5)
						lg.setLineWidth(1 / v.zoom)
						for _, t in ipairs(tris) do lg.polygon("line", t) end
					end
				end
				if moved then lg.pop() end
			end
		end
	end

	-- the live ship's collision body, built the way Ship.new builds it: a
	-- row of circles of the hull's radius along the spine, tail to nose
	local r = E.radius()
	if r and r > 0 then
		local noseX, tailX = 0, 0
		for _, p in ipairs(E.design.parts) do
			if not p.hidden then
				for k = 1, #p.shape, 2 do noseX, tailX = max(noseX, p.shape[k]), min(tailX, p.shape[k]) end
			end
		end
		local s1, s2 = tailX + r, noseX - r
		if s2 < s1 then s1, s2 = (s1 + s2) / 2, (s1 + s2) / 2 end
		local n = math.ceil((s2 - s1) / r) + 1
		lg.setColor(0.6, 0.85, 1, E.preview == "collision" and 0.5 or 0.15)
		lg.setLineWidth(1 / v.zoom)
		for k = 0, n - 1 do
			local cx = (n > 1) and (s1 + (s2 - s1) * k / (n - 1)) or s1
			lg.circle("line", cx, 0, r, 48)
		end
	end
	lg.pop()

	-- slot hardpoints: where guns fire from and engines burn
	for i, slot in ipairs(E.design.slots or {}) do
		if slot.x then
			local sx, sy = Canvas.toScreen(E, slot.x, slot.y or 0)
			local c = SLOT_COLORS[slot.family] or { 1, 1, 1 }
			lg.setColor(c[1], c[2], c[3], E.slotSel == i and 1 or 0.75)
			lg.setLineWidth(E.slotSel == i and 2.5 or 1.5)
			lg.circle("line", sx, sy, SLOT_PX)
			lg.print(("%d%s"):format(i, slot.family:sub(1, 1):upper()), sx + SLOT_PX + 2, sy - 7)
		end
	end

	-- selection: outline, vertices, centre
	local p = E.sel and E.design.parts[E.sel]
	if p and not p.hidden then
		local pts = {}
		for k = 1, #p.shape, 2 do
			local sx, sy = Canvas.toScreen(E, p.shape[k], p.shape[k + 1])
			table.insert(pts, sx); table.insert(pts, sy)
		end
		lg.setLineWidth(2)
		lg.setColor(E.errors[E.sel] and { 1, 0.3, 0.3 } or { 1, 0.85, 0.3 })
		if #pts >= 6 then lg.polygon("line", pts) end
		for k = 1, #pts, 2 do
			local big = k == E.vsel
			lg.setColor(big and { 1, 1, 1 } or { 1, 0.85, 0.3 })
			lg.rectangle(big and "fill" or "line", pts[k] - 4, pts[k + 1] - 4, 8, 8)
		end
	end

	-- the outline being drawn, and the rubber band to the mouse
	local mx, my = love.mouse.getPosition()
	if E.drawing then
		local pts = {}
		for k = 1, #E.drawing, 2 do
			local sx, sy = Canvas.toScreen(E, E.drawing[k], E.drawing[k + 1])
			table.insert(pts, sx); table.insert(pts, sy)
		end
		local wx, wy = Canvas.snap(E, Canvas.toWorld(E, mx, my))
		local ex, ey = Canvas.toScreen(E, wx, wy)
		table.insert(pts, ex); table.insert(pts, ey)
		lg.setColor(0.5, 1, 0.6)
		lg.setLineWidth(1.5)
		if #pts >= 4 then lg.line(pts) end
		for k = 1, #pts - 2, 2 do lg.rectangle("line", pts[k] - 3, pts[k + 1] - 3, 6, 6) end
		if E.mirrorNew then
			-- where the mirror twin will land
			lg.setColor(0.5, 1, 0.6, 0.3)
			local mp = {}
			for k = 1, #pts, 2 do
				local wx2, wy2 = Canvas.toWorld(E, pts[k], pts[k + 1])
				local sx2, sy2 = Canvas.toScreen(E, wx2, -wy2)
				table.insert(mp, sx2); table.insert(mp, sy2)
			end
			if #mp >= 4 then lg.line(mp) end
		end
	end
	if E.drag and E.drag.kind == "rect" then
		local d = E.drag
		local ax, ay = Canvas.toScreen(E, d.x1, d.y1)
		local bx, by = Canvas.toScreen(E, d.x2, d.y2)
		lg.setColor(0.5, 1, 0.6)
		lg.rectangle("line", min(ax, bx), min(ay, by), abs(bx - ax), abs(by - ay))
	end

	-- the cursor's position in ship space
	local wx, wy = Canvas.snap(E, Canvas.toWorld(E, mx, my))
	lg.setColor(1, 1, 1, 0.6)
	lg.print(("%d, %d   zoom %.1fx"):format(wx, wy, v.zoom), 340, lg.getHeight() - 22)
	lg.pop()
end


return Canvas
