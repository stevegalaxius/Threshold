--[[
	The Shipyard (F2): a debug editor for drawing hulls out of parts,
	tagging each part, test-flying the result and exporting it as a data
	file the game loads (src/editor/export.lua).

	While it's open the game is paused and the editor has the mouse and
	keyboard; its panels are Slab windows (src/editor/panels.lua) and the
	rest of the screen is the canvas (src/editor/canvas.lua).

	Keys (when no text box has focus):
	  V select   P draw polygon   B rectangle
	  L lights: click a part for one, drag for a row, click a light to pick
	    it, right drag to erase
	  Enter      finish the outline being drawn   Esc  drop it
	  Delete     remove the selected point, or the selected part
	  Ctrl+D     duplicate the part     M  toggle its mirror twin
	  Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z)  undo / redo
	  G          snap to grid on/off (hold Alt to place freely)
	  Mouse: left draws and selects (double click an edge to add a point),
	  right or middle drag pans, the wheel zooms.
]]

local data = require("src.data")
local Render = require("src.render")
local Canvas = require("src.editor.canvas")
local Export = require("src.editor.export")

local E = {
	isOpenFlag = false,
	design = nil,
	sel = nil, vsel = nil,
	tool = "select",
	drawing = nil,
	mirrorNew = false,       -- new parts get a mirror twin
	lightKind = "window",    -- what the light tool places
	lightSpacing = 6,        -- px between lights in a dragged row
	eraseRadius = 12,        -- screen px the light eraser (right drag) reaches
	previewDamage = 0,       -- pretend damage, to see the windows go out
	previewFlash = 0,        -- pretend hit (seconds left)
	lsel = nil,              -- selected light (index into the selected part's lights)
	view = { x = 0, y = 0, zoom = 3 },
	snap = true, grid = 4,
	preview = "normal",
	paint = { 0.55, 0.9, 0.95 },
	undo = {}, redo = {},
	errors = {},
	autosaveT = 0,
	message = nil, messageT = 0,
}

local Editor = { state = E }

local function say(msg)
	E.message, E.messageT = msg, 6
	print("[shipyard] " .. msg)
end
E.say = say

local function snapshot()
	return Export.copy(E.design)
end

function E.pushUndo()
	table.insert(E.undo, snapshot())
	if #E.undo > 200 then table.remove(E.undo, 1) end
	E.redo = {}
	E.dirty = true
end

-- Slider drags and typing push one undo step, not one per frame.
function E.pushUndoCoalesced(key)
	local now = love.timer.getTime()
	if E.lastUndoKey ~= key or now - (E.lastUndoT or 0) > 1 then E.pushUndo() end
	E.lastUndoKey, E.lastUndoT = key, now
	E.dirty = true
end

function E.undoStep()
	local s = table.remove(E.undo)
	if not s then return end
	table.insert(E.redo, snapshot())
	E.design = s
	E.sel, E.vsel, E.lastUndoKey = nil, nil, nil
end

function E.redoStep()
	local s = table.remove(E.redo)
	if not s then return end
	table.insert(E.undo, snapshot())
	E.design = s
	E.sel, E.vsel, E.lastUndoKey = nil, nil, nil
end

-- Fly with another hull's stats and slots (dropping the design's own).
local function setBase(id, keep)
	E.design.base = id
	local h = data.hulls[id]
	if not keep then
		E.design.stats = {}
		E.design.slots = h and Export.copy(h.slots) or {}
	end
	E.design.stats = E.design.stats or {}
	E.design.slots = E.design.slots or (h and Export.copy(h.slots)) or {}
	E.slotSel = nil
end

-- A stat as the design flies it: its own value, else the base hull's.
function E.stat(key)
	local v = E.design.stats[key]
	if v ~= nil then return v end
	local h = data.hulls[E.design.base]
	return h and h[key]
end

function E.radius()
	return E.stat("radius")
end
E.setBase = setBase

function E.newDesign()
	E.design = { id = "new_hull", name = "New hull", base = data.list.hulls[1], parts = {} }
	setBase(E.design.base)
	E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}
end

function E.openHull(id)
	E.design = Export.fromHull(id)
	setBase(id, true)
	E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}
	say("Opened " .. data.hulls[id].name)
end

function E.addPart(shape)
	E.pushUndo()
	-- a name no other part has
	local used = {}
	for _, q in ipairs(E.design.parts) do if q.name then used[q.name] = true end end
	local n = #E.design.parts + 1
	while used["part " .. n] do n = n + 1 end
	local part = { name = "part " .. n, shape = shape, mirror = E.mirrorNew or nil }
	table.insert(E.design.parts, part)
	E.sel, E.vsel = #E.design.parts, nil
	return part
end

function E.finishDrawing()
	local d = E.drawing
	E.drawing = nil
	if not d or #d < 6 then return end
	E.addPart(d)
end

function E.deleteSelected()
	if not E.sel then return end
	local p = E.design.parts[E.sel]
	if E.lsel and p.lights and p.lights[E.lsel] then
		E.pushUndo()
		table.remove(p.lights, E.lsel)
		if #p.lights == 0 then p.lights = nil end
		E.lsel = nil
		return
	end
	if E.vsel and #p.shape > 6 then
		E.pushUndo()
		table.remove(p.shape, E.vsel); table.remove(p.shape, E.vsel)
		E.vsel = nil
	else
		E.pushUndo()
		table.remove(E.design.parts, E.sel)
		E.sel, E.vsel = nil, nil
	end
end

function E.duplicateSelected()
	if not E.sel then return end
	E.pushUndo()
	local p = Export.copy(E.design.parts[E.sel])
	for k = 1, #p.shape, 2 do p.shape[k], p.shape[k + 1] = p.shape[k] + E.grid * 2, p.shape[k + 1] + E.grid * 2 end
	for _, l in ipairs(p.lights or {}) do l.x, l.y = l.x + E.grid * 2, l.y + E.grid * 2 end
	p.name = (p.name or "part") .. " copy"
	table.insert(E.design.parts, E.sel + 1, p)
	E.sel = E.sel + 1
end

function E.movePart(i, delta)
	local j = i + delta
	local parts = E.design.parts
	if j < 1 or j > #parts then return end
	E.pushUndo()
	parts[i], parts[j] = parts[j], parts[i]
	if E.sel == i then E.sel = j elseif E.sel == j then E.sel = i end
end

-- Apply fn(x, y) -> x, y to every point of the selected part.
function E.transformSelected(fn, reverse)
	local p = E.sel and E.design.parts[E.sel]
	if not p then return end
	E.pushUndo()
	local s, out = p.shape, {}
	for k = 1, #s, 2 do
		local x, y = fn(s[k], s[k + 1])
		table.insert(out, math.floor(x + 0.5)); table.insert(out, math.floor(y + 0.5))
	end
	if reverse then
		-- a flip turns the winding over; put it back
		local r = {}
		for k = #out - 1, 1, -2 do table.insert(r, out[k]); table.insert(r, out[k + 1]) end
		out = r
	end
	p.shape = out
	for _, l in ipairs(p.lights or {}) do
		local x, y = fn(l.x, l.y)
		l.x, l.y = math.floor(x + 0.5), math.floor(y + 0.5)
	end
	E.vsel = nil
end

-- Make the selected part symmetric about the spine: keep its points on
-- the port side (y <= 0) and add their reflection, giving one outline that
-- straddles the axis.
function E.symmetrizeSelected()
	local p = E.sel and E.design.parts[E.sel]
	if not p then return end
	local s = p.shape
	-- start the walk at a point on the port side next to a starboard one
	local n = #s / 2
	local function pt(i) i = (i - 1) % n; return s[i * 2 + 1], s[i * 2 + 2] end
	local start
	for i = 1, n do
		local _, y = pt(i)
		local _, py = pt(i - 1)
		if y <= 0 and py > 0 then start = i break end
	end
	if not start then say("Symmetrize needs points on both sides of the spine") return end
	local half = {}
	for i = start, start + n - 1 do
		local x, y = pt(i)
		if y > 0 then break end
		table.insert(half, x); table.insert(half, y)
	end
	if #half < 4 then say("Symmetrize needs at least two points on the port side") return end
	E.pushUndo()
	local out = {}
	for k = 1, #half do out[k] = half[k] end
	for k = #half - 1, 1, -2 do
		if half[k + 1] ~= 0 then table.insert(out, half[k]); table.insert(out, -half[k + 1]) end
	end
	p.shape = out
	E.vsel = nil
end

function E.export()
	local ok, err = pcall(function()
		local def = Export.hullDef(E.design)
		local good, msg = data.defineHull(def)
		if not good then error(msg, 0) end
	end)
	if not ok then say("Not exported: " .. tostring(err)) return end
	local path, werr = Export.write(E.design)
	if path then say("Exported to " .. path .. " (loads on restart; Test fly uses it now)") else say("Export failed: " .. tostring(werr)) end
end

function E.copySource()
	love.system.setClipboardText(Export.source(E.design))
	say("Copied the hull { } source to the clipboard")
end

-- Register the design as a hull right now and launch it.
function E.testFly()
	local def = Export.hullDef(E.design)
	local good, err = data.defineHull(def)
	if not good then say("Can't fly it: " .. tostring(err)) return end
	local game = Editor.game
	if not game then return end
	Editor.close()
	if game.state == "dead" then game:respawn() end
	game:spawnPlayer(def.id)
	say("Flying " .. def.name .. " (F2 to go back)")
end

-- Open / close --------------------------------------------------------------

function Editor.isOpen() return E.isOpenFlag end

function Editor.open(game)
	Editor.game = game
	if not E.design then
		local saved = Export.loadAutosave()
		if saved then
			E.design = saved
			setBase(saved.base, true)
			say("Restored the last design from the autosave")
		elseif game and game.playerHull and data.hulls[game.playerHull] then
			E.openHull(game.playerHull)
		else
			E.newDesign()
		end
	end
	E.isOpenFlag = true
	love.mouse.setVisible(true)
end

function Editor.close()
	if E.design then Export.autosave(E.design) end
	E.isOpenFlag = false
	E.drag, E.drawing = nil, nil
end

function Editor.toggle(game)
	if E.isOpenFlag then Editor.close() else Editor.open(game) end
end

-- Hooks from main.lua -------------------------------------------------------

local Slab = require("lib.Slab")
local Panels = require("src.editor.panels")

local function canvasHasMouse()
	return Slab.IsVoidHovered()
end

local function typing()
	return Slab.IsAnyInputFocused()
end

function Editor.update(dt)
	if not E.isOpenFlag then return end
	Panels.update(E, Editor)
	local mx, my = love.mouse.getPosition()
	Canvas.mousemoved(E, mx, my)
	E.messageT = math.max(0, E.messageT - dt)
	E.previewFlash = math.max(0, E.previewFlash - dt)
	E.autosaveT = E.autosaveT + dt
	if E.dirty and E.autosaveT > 5 then
		E.autosaveT, E.dirty = 0, false
		Export.autosave(E.design)
	end
end

function Editor.draw()
	if not E.isOpenFlag then return end
	Canvas.draw(E)
	if E.message and E.messageT > 0 then
		love.graphics.setColor(1, 0.9, 0.5, math.min(1, E.messageT))
		love.graphics.print(E.message, 340, 12)
	end
end

function Editor.mousepressed(x, y, button)
	if not E.isOpenFlag then return false end
	if canvasHasMouse() then Canvas.mousepressed(E, x, y, button) end
	return true
end

function Editor.mousereleased(x, y, button)
	if not E.isOpenFlag then return false end
	Canvas.mousereleased(E, x, y, button)
	return true
end

function Editor.wheelmoved(_, y)
	if not E.isOpenFlag then return false end
	if canvasHasMouse() then
		local mx, my = love.mouse.getPosition()
		Canvas.zoomAt(E, mx, my, y > 0 and 1.15 or 1 / 1.15)
	end
	return true
end

function Editor.keypressed(key)
	if not E.isOpenFlag then return false end
	if key == "f2" then Editor.close() return true end
	if typing() then return true end
	local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
	local shift = love.keyboard.isDown("lshift", "rshift")
	if ctrl and key == "z" then if shift then E.redoStep() else E.undoStep() end
	elseif ctrl and key == "y" then E.redoStep()
	elseif ctrl and key == "d" then E.duplicateSelected()
	elseif key == "v" then E.tool = "select"; E.drawing = nil
	elseif key == "p" then E.tool = "draw"
	elseif key == "b" then E.tool = "rect"; E.drawing = nil
	elseif key == "l" then E.tool = "light"; E.drawing = nil
	elseif key == "g" then E.snap = not E.snap
	elseif key == "m" and E.sel then
		E.pushUndo()
		local p = E.design.parts[E.sel]
		p.mirror = not p.mirror or nil
	elseif key == "return" or key == "kpenter" then E.finishDrawing()
	elseif key == "escape" then
		if E.drawing then E.drawing = nil else E.sel, E.vsel = nil, nil end
	elseif key == "delete" or key == "backspace" then E.deleteSelected()
	end
	return true
end

-- Paints to preview against (shade and tint are relative to the paint).
Editor.PAINTS = Render.PAINTS

return Editor
