--[[
	The Shipyard's drawing canvas: the view (pan and zoom), the grid, the
	design's parts, and the mouse tools that draw and edit them.

	Ship space has the nose along +x, like data/hulls.lua. Every function
	takes the editor state E (src/editor/init.lua).
]]

local HullShape = require("src.hullshape")
local data = require("src.data")

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
	-- the grid as drawn: zoomed out, its lines double up until they're
	-- far enough apart to see, and snapping follows what you see
	local g = E.grid
	while g * E.view.zoom < 6 do g = g * 2 end
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

-- The light near a screen point: part index and light index.
-- The nearest one within LIGHT_PX, so a tight row is still pickable.
local LIGHT_PX = 10
function Canvas.lightAt(E, sx, sy, radius)
	local parts = E.design.parts
	local best, bi, bj = (radius or LIGHT_PX) ^ 2, nil, nil
	for i = #parts, 1, -1 do
		local p = parts[i]
		if not p.hidden and not p.locked then
			for j, l in ipairs(p.lights or {}) do
				local x, y = Canvas.toScreen(E, l.x, l.y)
				local d = (x - sx) ^ 2 + (y - sy) ^ 2
				if d <= best then best, bi, bj = d, i, j end
			end
		end
	end
	return bi, bj
end

-- Remove every light within `radius` screen px of a point (the eraser).
function Canvas.eraseLights(E, sx, sy, radius)
	local gone = false
	for _, p in ipairs(E.design.parts) do
		if p.lights and not p.hidden and not p.locked then
			for j = #p.lights, 1, -1 do
				local x, y = Canvas.toScreen(E, p.lights[j].x, p.lights[j].y)
				if (x - sx) ^ 2 + (y - sy) ^ 2 <= radius ^ 2 then table.remove(p.lights, j); gone = true end
			end
			if #p.lights == 0 then p.lights = nil end
		end
	end
	if gone then E.lsel = nil end
	return gone
end

-- The berth under a screen point (stations): within its pad, or 10 px of
-- its centre when zoomed out.
function Canvas.berthAt(E, sx, sy)
	local best, bd
	for i, b in ipairs(E.design.berths or {}) do
		local bx, by = Canvas.toScreen(E, b.x, b.y)
		local d = sqrt((bx - sx) ^ 2 + (by - sy) ^ 2)
		local reach = max(10, b.size * 0.5 * E.view.zoom)
		if d <= reach and (not bd or d < bd) then best, bd = i, d end
	end
	return best
end

-- The turret under a screen point (stations).
function Canvas.turretAt(E, sx, sy)
	local best, bd
	for i, t in ipairs(E.design.turrets or {}) do
		local tx, ty = Canvas.toScreen(E, t.x, t.y)
		local d = sqrt((tx - sx) ^ 2 + (ty - sy) ^ 2)
		if d <= 10 and (not bd or d < bd) then best, bd = i, d end
	end
	return best
end

-- Heading (whole degrees) from a berth's spot toward a point; with no
-- drag, out from the station's centre.
local function berthHeading(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	if dx * dx + dy * dy < 16 then dx, dy = x1, y1 end
	if dx == 0 and dy == 0 then return 0 end
	return floor(math.deg(math.atan2(dy, dx)) + 0.5) % 360
end

-- A new light like the light tool's settings.
local function newLight(E, x, y)
	local l = { x = x, y = y, kind = E.lightKind }
	if E.lightKind == "strobe" then l.rate = 1 end
	return l
end

-- Mouse tools ---------------------------------------------------------------

local function pressed(E, sx, sy, button)
	local wx, wy = Canvas.toWorld(E, sx, sy)
	if button == 2 and E.tool == "draw" and E.drawing then
		-- right click while drawing takes the last point back
		table.remove(E.drawing); table.remove(E.drawing)
		if #E.drawing == 0 then E.drawing = nil end
		return
	end
	if button == 2 and E.tool == "light" then
		-- right drag with the light tool erases lights under the cursor
		E.pushUndo()
		E.drag = { kind = "erase" }
		Canvas.eraseLights(E, sx, sy, E.eraseRadius)
		return
	end
	if button == 2 and E.tool == "turret" then
		local i = Canvas.turretAt(E, sx, sy)
		if i then
			E.pushUndo()
			table.remove(E.design.turrets, i)
			if #E.design.turrets == 0 then E.design.turrets = nil end
			E.tsel = nil
			return
		end
	end
	if button == 2 and E.tool == "berth" then
		local i = Canvas.berthAt(E, sx, sy)
		if i then
			E.pushUndo()
			table.remove(E.design.berths, i)
			if #E.design.berths == 0 then E.design.berths = nil end
			E.bsel = nil
			return
		end
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

	if E.tool == "light" then
		local px, py = Canvas.snap(E, wx, wy)
		-- the part under the click; on a mirror twin, place on its source
		-- part at the reflected spot (the twin gets the mirror image)
		local parts, hit, flip = E.design.parts, nil, false
		for i = #parts, 1, -1 do
			local p = parts[i]
			if not p.hidden and not p.locked then
				if inside(p.shape, px, py) then hit = i break end
				if p.mirror and inside(Canvas.reflected(p.shape), px, py) then hit, flip = i, true break end
			end
		end
		if not hit then E.say("Lights go on a part: click on one") return end
		E.drag = { kind = "lights", part = hit, flip = flip, x1 = px, y1 = py, x2 = px, y2 = py }
		return
	end

	if E.tool == "turret" then
		local px, py = Canvas.snap(E, wx, wy)
		E.pushUndo()
		E.design.turrets = E.design.turrets or {}
		local t = { x = px, y = py, module = E.turretModule }
		local m = data.modules[t.module]
		if m and m.family == "auxiliary" then t.heading = berthHeading(px, py, px, py) end
		table.insert(E.design.turrets, t)
		E.tsel, E.bsel = #E.design.turrets, nil
		return
	end

	if E.tool == "berth" then
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "berth", x1 = px, y1 = py, x2 = px, y2 = py }
		return
	end

	if E.tool == "rect" then
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "rect", x1 = px, y1 = py, x2 = px, y2 = py }
		return
	end

	-- select tool: a vertex of the selected part, an edge (double click
	-- inserts a point), a part, or nothing
	local ti = Canvas.turretAt(E, sx, sy)
	if ti then
		E.tsel, E.bsel, E.lsel, E.vsel = ti, nil, nil, nil
		local t = E.design.turrets[ti]
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "turretmove", i = ti, ox = t.x - px, oy = t.y - py, pushed = false }
		return
	end
	E.tsel = nil
	local bi = Canvas.berthAt(E, sx, sy)
	if bi then
		E.bsel, E.lsel, E.vsel = bi, nil, nil
		local b = E.design.berths[bi]
		local px, py = Canvas.snap(E, wx, wy)
		E.drag = { kind = "berthmove", i = bi, ox = b.x - px, oy = b.y - py, pushed = false }
		return
	end
	E.bsel = nil
	local li, lj = Canvas.lightAt(E, sx, sy)
	if li then
		E.sel, E.vsel, E.lsel = li, nil, lj
		E.drag = { kind = "light", i = li, j = lj, pushed = false }
		return
	end
	E.lsel = nil
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

-- Moving drags (a light, point, slot, part, berth or turret) only start
-- once the mouse has gone a few pixels from where it was pressed, so a
-- click that only means to select never nudges anything.
local MOVES = { light = true, vertex = true, slot = true, part = true, berthmove = true, turretmove = true }
local DRAG_PX = 4

function Canvas.mousepressed(E, sx, sy, button)
	pressed(E, sx, sy, button)
	if E.drag then E.drag.sx0, E.drag.sy0 = sx, sy end
end

function Canvas.mousemoved(E, sx, sy)
	local d = E.drag
	if not d then return end
	if MOVES[d.kind] and not d.moving then
		if (sx - d.sx0) ^ 2 + (sy - d.sy0) ^ 2 < DRAG_PX ^ 2 then return end
		d.moving = true
	end
	if d.kind == "erase" then
		Canvas.eraseLights(E, sx, sy, E.eraseRadius)
		return
	end
	if d.kind == "pan" then
		E.view.x = d.vx - (sx - d.sx) / E.view.zoom
		E.view.y = d.vy - (sy - d.sy) / E.view.zoom
		return
	end
	local wx, wy = Canvas.toWorld(E, sx, sy)
	local px, py = Canvas.snap(E, wx, wy)
	if d.kind == "rect" or d.kind == "lights" or d.kind == "berth" then
		d.x2, d.y2 = px, py
	elseif d.kind == "turretmove" then
		local t = E.design.turrets and E.design.turrets[d.i]
		local nx, ny = px + d.ox, py + d.oy
		if t and (t.x ~= nx or t.y ~= ny) then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			t.x, t.y = nx, ny
		end
	elseif d.kind == "berthmove" then
		local b = E.design.berths and E.design.berths[d.i]
		local nx, ny = px + d.ox, py + d.oy
		if b and (b.x ~= nx or b.y ~= ny) then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			b.x, b.y = nx, ny
		end
	elseif d.kind == "light" then
		local l = E.design.parts[d.i].lights[d.j]
		if l and (l.x ~= px or l.y ~= py) then
			if not d.pushed then E.pushUndo(); d.pushed = true end
			l.x, l.y = px, py
		end
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
			for _, l in ipairs(E.design.parts[E.sel].lights or {}) do l.x, l.y = l.x + dx, l.y + dy end
			d.lx, d.ly = px, py
		end
	end
end

function Canvas.mousereleased(E, sx, sy, button)
	local d = E.drag
	E.drag = nil
	if d and d.kind == "lights" then
		-- a click places one light; a drag places a row along it
		local pts = {}
		local dx, dy = d.x2 - d.x1, d.y2 - d.y1
		local len = sqrt(dx * dx + dy * dy)
		if len < E.lightSpacing * 0.5 then
			pts[1] = { d.x1, d.y1 }
		else
			local n = floor(len / E.lightSpacing + 0.5)
			for k = 0, n do pts[#pts + 1] = { d.x1 + dx * k / n, d.y1 + dy * k / n } end
		end
		E.pushUndo()
		local p = E.design.parts[d.part]
		p.lights = p.lights or {}
		for _, q in ipairs(pts) do
			table.insert(p.lights, newLight(E, floor(q[1] + 0.5), floor((d.flip and -q[2] or q[2]) + 0.5)))
		end
		return
	end
	if d and d.kind == "berth" then
		E.pushUndo()
		E.design.berths = E.design.berths or {}
		table.insert(E.design.berths, { x = d.x1, y = d.y1, heading = berthHeading(d.x1, d.y1, d.x2, d.y2), size = E.berthSize })
		E.bsel = #E.design.berths
		return
	end
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
				if p.lights then
					twin.lights = {}
					for _, l in ipairs(p.lights) do
						local m = {}
						for k2, x2 in pairs(l) do m[k2] = x2 end
						m.y = -l.y
						table.insert(twin.lights, m)
					end
				end
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
				if q.lights and E.preview ~= "wreck" and E.preview ~= "break" then
					HullShape.drawLights(nil, love.timer.getTime(), 1 / v.zoom, q, nil, nil,
						{ damage = E.previewDamage, flash = E.previewFlash })
				end
				if moved then lg.pop() end
			end
		end
	end

	lg.pop()

	-- berths: a pad the size of the biggest ship that fits, nose arrow
	-- showing which way it parks
	local function pad(x, y, heading, size, sel, alpha)
		local cx, cy = Canvas.toScreen(E, x, y)
		local a = math.rad(heading)
		local c, sn = math.cos(a), math.sin(a)
		local L, W = size * v.zoom, size * 0.55 * v.zoom
		local function pt(u, w) return cx + u * c - w * sn, cy + u * sn + w * c end
		local x1, y1 = pt(-L, -W); local x2, y2 = pt(L, -W); local x3, y3 = pt(L, W); local x4, y4 = pt(-L, W)
		lg.setColor(0.95, 0.75, 0.25, alpha)
		lg.setLineWidth(sel and 2.5 or 1.5)
		lg.polygon("line", x1, y1, x2, y2, x3, y3, x4, y4)
		local ax, ay = pt(max(L, 8) + 10, 0)
		local bx, by = pt(L * 0.3, 0)
		lg.line(bx, by, ax, ay)
		local hx, hy = pt(max(L, 8) + 2, -5); local kx, ky = pt(max(L, 8) + 2, 5)
		lg.line(hx, hy, ax, ay, kx, ky)
		lg.circle("fill", cx, cy, sel and 4 or 3)
	end
	if E.design.kind == "station" then
		for i, b in ipairs(E.design.berths or {}) do
			pad(b.x, b.y, b.heading or 0, b.size or 80, E.bsel == i, E.bsel == i and 1 or 0.7)
			local cx, cy = Canvas.toScreen(E, b.x, b.y)
			lg.print("B" .. i, cx + 6, cy + 4)
		end
		-- turrets: a ring and a barrel, red for missiles and torpedoes
		for i, t in ipairs(E.design.turrets or {}) do
			local cx, cy = Canvas.toScreen(E, t.x, t.y)
			local m = data.modules[t.module]
			local aux = m and m.family == "auxiliary"
			local c = aux and { 1, 0.5, 0.4 } or { 0.6, 0.85, 1 }
			local sel = E.tsel == i
			local r = max(6, ({ S = 8, M = 12, L = 18 })[m and m.size or "M"] * v.zoom)
			lg.setColor(c[1], c[2], c[3], sel and 1 or 0.8)
			lg.setLineWidth(sel and 2.5 or 1.5)
			if aux then
				-- a fixed bay: a box and an arrow along its heading
				local a = math.rad(t.heading or (t.x == 0 and t.y == 0 and 0 or math.deg(math.atan2(t.y, t.x))))
				local c2, s2 = math.cos(a), math.sin(a)
				lg.rectangle("line", cx - r, cy - r, r * 2, r * 2)
				lg.line(cx, cy, cx + c2 * r * 2.4, cy + s2 * r * 2.4)
				lg.circle("fill", cx + c2 * r * 2.4, cy + s2 * r * 2.4, 3)
			else
				lg.circle("line", cx, cy, r)
				lg.line(cx, cy, cx + r * 1.8, cy)
			end
			lg.print("T" .. i, cx + 6, cy + 4)
		end
		if E.drag and E.drag.kind == "berth" then
			local d = E.drag
			pad(d.x1, d.y1, berthHeading(d.x1, d.y1, d.x2, d.y2), E.berthSize, true, 0.5)
		end
	end

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
	-- (handles only with the select tool; other tools just show a faint outline)
	if p and not p.hidden then
		local editing = E.tool == "select"
		local pts = {}
		for k = 1, #p.shape, 2 do
			local sx, sy = Canvas.toScreen(E, p.shape[k], p.shape[k + 1])
			table.insert(pts, sx); table.insert(pts, sy)
		end
		lg.setLineWidth(editing and 2 or 1)
		local oc = E.errors[E.sel] and { 1, 0.3, 0.3 } or { 1, 0.85, 0.3 }
		lg.setColor(oc[1], oc[2], oc[3], editing and 1 or 0.35)
		if #pts >= 6 then lg.polygon("line", pts) end
		for k = 1, editing and #pts or 0, 2 do
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

	-- the light under the mouse, and the eraser's reach
	if E.tool == "select" then
		local hi, hj = Canvas.lightAt(E, mx, my)
		if hi then
			local l = E.design.parts[hi].lights[hj]
			local lx, ly = Canvas.toScreen(E, l.x, l.y)
			lg.setColor(1, 1, 1, 0.6)
			lg.setLineWidth(1)
			lg.circle("line", lx, ly, 5)
		end
	end
	if E.tool == "light" then
		lg.setColor(1, 0.4, 0.4, (E.drag and E.drag.kind == "erase") and 0.7 or 0.2)
		lg.setLineWidth(1)
		lg.circle("line", mx, my, E.eraseRadius)
	end

	-- the selected light, and the row being placed
	local sp = E.sel and E.design.parts[E.sel]
	local sl = sp and E.lsel and sp.lights and sp.lights[E.lsel]
	if sl then
		local lx, ly = Canvas.toScreen(E, sl.x, sl.y)
		lg.setColor(1, 1, 1)
		lg.setLineWidth(1.5)
		lg.circle("line", lx, ly, 7)
	end
	if E.drag and E.drag.kind == "lights" then
		local d = E.drag
		local ax, ay = Canvas.toScreen(E, d.x1, d.y1)
		local bx, by = Canvas.toScreen(E, d.x2, d.y2)
		lg.setColor(1, 0.86, 0.55, 0.8)
		lg.setLineWidth(1)
		lg.line(ax, ay, bx, by)
	end

	-- the cursor's position in ship space
	local wx, wy = Canvas.snap(E, Canvas.toWorld(E, mx, my))
	lg.setColor(1, 1, 1, 0.6)
	lg.print(("%d, %d   zoom %.1fx"):format(wx, wy, v.zoom), 340, lg.getHeight() - 22)
	lg.pop()
end


return Canvas
