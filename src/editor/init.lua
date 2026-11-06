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
	lightKind = "nav",       -- what the light tool places (window, nav or strobe)
	lightSpacing = 6,        -- px between lights in a dragged row
	eraseRadius = 12,        -- screen px the light eraser (right drag) reaches
	previewDamage = 0,       -- pretend damage, to see the windows go out
	previewFlash = 0,        -- pretend hit (seconds left)
	lsel = nil,              -- selected light (index into the selected part's lights)
	bsel = nil,              -- selected berth (index into design.berths; stations)
	berthSize = 80,          -- size for new berths
	tsel = nil,              -- selected turret (index into design.turrets; stations)
	turretModule = "gun_m_base",   -- weapon for new turrets
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
	E.sel, E.vsel, E.lastUndoKey = nil, nil, nil; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
end

function E.redoStep()
	local s = table.remove(E.redo)
	if not s then return end
	table.insert(E.undo, snapshot())
	E.design = s
	E.sel, E.vsel, E.lastUndoKey = nil, nil, nil; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
end

-- Fly with another hull's stats and slots (dropping the design's own).
local function setBase(id, keep)
	E.design.base = id
	local h = data.hulls[id]
	if not keep then
		E.design.stats = {}
		E.design.slots = h and Export.copy(h.slots) or {}
		E.design.loadout = h and Export.copy(h.loadout) or {}
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

-- Materialize legacy inherited defaults before changing slots or equipment.
function E.ensureLoadout()
 if not E.design.loadout then E.design.loadout = Export.hullDef(E.design).loadout or {} end
 return E.design.loadout
end

function E.validateSlotDefault(i)
 local loadout = E.ensureLoadout()
 local module = loadout[i] and data.modules[loadout[i]]
 if not module or not data.fits(E.design.slots[i], module) then loadout[i] = false end
end


function E.newDesign(kind)
	kind = kind or "hull"
	E.design = { id = "new_" .. kind, name = "New " .. kind, base = data.list.hulls[1], parts = {}, kind = kind ~= "hull" and kind or nil,
		loot = kind == "wreck" and {} or nil }
	if kind == "weapon" then
		E.design.name = "New weapon"
		E.design.muzzles = { { 12, 0 } }
		E.design.module = { family = "weapon", size = "S", mass = 4, powerDraw = 1, price = 2000, maker = "",
			weapon = { kind = "cannon", fireRate = 4, spread = 1, gimbal = 10, recoilPct = 15 } }
		E.design.parts = {
			{ name = "base", shape = { -4, -4, 4, -4, 4, 4, -4, 4 } },
			{ name = "barrel", shape = { 0, -1.5, 12, -1.5, 12, 1.5, 0, 1.5 }, barrel = true },
		}
	end
	setBase(E.design.base)
	if kind == "weapon" then E.design.slots, E.design.loadout = {}, {} end
	E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
end

function E.openHull(id)
	if data.modules[id] and data.modules[id].weapon and not data.hulls[id] then
		E.design = Export.fromModule(id)
		E.design.folder = Export.folderOf(id)
		if E.design.folder then E.browseDir = E.design.folder end
		setBase(E.design.base, true)
		E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
		say("Opened " .. data.modules[id].name)
		return
	end
	if data.stations[id] and not data.hulls[id] then
		E.design = Export.fromStation(id)
		E.design.folder = Export.folderOf(id)
		if E.design.folder then E.browseDir = E.design.folder end
		setBase(E.design.base, true)
		E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
		E.view.zoom = math.min(E.view.zoom, 0.3)
		say("Opened " .. data.stations[id].name)
		return
	end
	if data.wrecks[id] and not data.hulls[id] then
		E.design = Export.fromWreck(id)
		E.design.folder = Export.folderOf(id)
		if E.design.folder then E.browseDir = E.design.folder end
		setBase(E.design.base, true)
		E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
		say("Opened " .. data.wrecks[id].name)
		return
	end
	E.design = Export.fromHull(id)
	E.design.folder = Export.folderOf(id)
	if E.design.folder then E.browseDir = E.design.folder end
	setBase(id, true)
	E.sel, E.vsel, E.undo, E.redo = nil, nil, {}, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
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
	-- only the select tool changes the selection
	return part
end

function E.finishDrawing()
	local d = E.drawing
	E.drawing = nil
	if not d or #d < 6 then return end
	E.addPart(d)
end

function E.deleteSelected()
	if E.tsel and E.design.turrets and E.design.turrets[E.tsel] then
		E.pushUndo()
		table.remove(E.design.turrets, E.tsel)
		if #E.design.turrets == 0 then E.design.turrets = nil end
		E.tsel = nil
		return
	end
	if E.bsel and E.design.berths and E.design.berths[E.bsel] then
		E.pushUndo()
		table.remove(E.design.berths, E.bsel)
		if #E.design.berths == 0 then E.design.berths = nil end
		E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
		return
	end
	-- lights: the primary plus every shift/box-picked one, on any part
	local lsets = {}
	if E.sel and E.lsel then lsets[E.sel] = { [E.lsel] = true } end
	for _, v in pairs(E.lmulti or {}) do lsets[v[1]] = lsets[v[1]] or {}; lsets[v[1]][v[2]] = true end
	if next(lsets) then
		E.pushUndo()
		for i, set in pairs(lsets) do
			local q = E.design.parts[i]
			if q and q.lights then
				local idx = {}
				for j in pairs(set) do idx[#idx + 1] = j end
				table.sort(idx, function(a, b) return a > b end)
				for _, j in ipairs(idx) do if q.lights[j] then table.remove(q.lights, j) end end
				if #q.lights == 0 then q.lights = nil end
			end
		end
		E.lsel, E.lmulti = nil, {}
		return
	end
	if not E.sel then return end
	local p = E.design.parts[E.sel]
	local verts = Canvas.vertexSelection(E)
	if #verts > 0 then
		local removable = #p.shape / 2 - 3
		if removable > 0 then
			E.pushUndo()
			table.sort(verts, function(a, b) return a > b end)
			for n, k in ipairs(verts) do
				if n > removable then break end
				table.remove(p.shape, k); table.remove(p.shape, k)
			end
		end
		E.vsel, E.vmulti = nil, {}
	else
		E.pushUndo()
		local list = Canvas.selection(E)
		table.sort(list, function(a, b) return a > b end)
		for _, idx in ipairs(list) do table.remove(E.design.parts, idx) end
		E.sel, E.vsel, E.multi = nil, nil, {}; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
	end
end

function E.duplicateSelected()
	if not E.sel then return end
	E.pushUndo()
	local list = Canvas.selection(E)
	table.sort(list)
	local copies = {}
	for _, idx in ipairs(list) do
		local p = Export.copy(E.design.parts[idx])
		for k = 1, #p.shape, 2 do p.shape[k], p.shape[k + 1] = p.shape[k] + E.grid * 2, p.shape[k + 1] + E.grid * 2 end
		for _, l in ipairs(p.lights or {}) do l.x, l.y = l.x + E.grid * 2, l.y + E.grid * 2 end
		if p.dockX~=nil then p.dockX,p.dockY=p.dockX+E.grid*2,p.dockY+E.grid*2 end
		p.name = (p.name or "part") .. " copy"
		table.insert(E.design.parts, p)
		copies[#copies + 1] = #E.design.parts
	end
	-- the copies (added at the end) become the selection
	E.sel, E.multi = copies[1], {}
	for k = 2, #copies do E.multi[copies[k]] = true end
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

-- The editor's tabs: each category keeps its own design and undo history.
local function categoryOf(kind)
	if kind == "wreck" or kind == "prop" then return "wreck" end
	if kind == "station" then return "station" end
	if kind == "weapon" then return "weapon" end
	return "hull"
end
E.byCategory = {}

function E.category()
	return categoryOf(E.design and E.design.kind)
end

function E.switchCategory(cat)
	E.byCategory[E.category()] = { design = E.design, undo = E.undo, redo = E.redo, view = { x = E.view.x, y = E.view.y, zoom = E.view.zoom } }
	local saved = E.byCategory[cat]
	E.sel, E.vsel, E.lsel, E.slotSel, E.drawing = nil, nil, nil, nil, nil; E.bsel, E.tsel, E.multi = nil, nil, {}; E.lmulti, E.vmulti = {}, {}
	if saved then
		E.design, E.undo, E.redo = saved.design, saved.undo, saved.redo
		E.view.x, E.view.y, E.view.zoom = saved.view.x, saved.view.y, saved.view.zoom
	else
		E.newDesign(cat)
		E.view.x, E.view.y = 0, 0
		E.view.zoom = cat == "station" and 0.25 or (cat == "weapon" and 12 or 3)
	end
	if (E.tool == "berth" or E.tool == "turret" or E.tool == "pivot") and cat ~= "station" then E.tool = "select" end
	if E.tool == "muzzle" and cat ~= "weapon" then E.tool = "select" end
end

-- Is the design a wreck or prop (placed in the world) rather than a hull?
function E.isPlaced()
	return E.design.kind == "wreck" or E.design.kind == "prop" or E.design.kind == "station"
end

-- Register the design with the game now: nil, error if it doesn't load.
function E.define()
	local def = Export.def(E.design)
	if E.design.kind == "weapon" then return data.defineModule(def) end
	if E.design.kind == "station" then return data.defineStation(def) end
	if E.isPlaced() then return data.defineWreck(def) end
	return data.defineHull(def)
end

function E.export()
	local ok, err = pcall(function()
		local good, msg = E.define()
		if not good then error(msg, 0) end
	end)
	if not ok then say("Not exported: " .. tostring(err)) return end
	local path, werr = Export.write(E.design)
	if path then say("Exported to " .. path .. " (loads on restart; Test fly uses it now)") else say("Export failed: " .. tostring(werr)) end
end

-- Saved designs: folders under the export folder, and deleting entries.
function E.makeFolder(name)
	local rel, err = Export.makeFolder(name)
	if not rel then say("No folder: " .. tostring(err)) return end
	say("Made folder " .. rel)
	return rel
end

-- The panel asks for confirmation before calling this.
function E.deleteSaved(rel)
	E.confirmDelete = nil
	local ok, err = Export.remove(rel)
	if not ok then say("Not deleted: " .. tostring(err)) return end
	if E.design.folder and (E.design.folder == rel or E.design.folder:sub(1, #rel + 1) == rel .. "/") then E.design.folder = nil end
	say("Deleted " .. rel .. (rel:match("%.lua$") and " (it stays in the game until restart)" or ""))
end

function E.copySource()
	love.system.setClipboardText(Export.source(E.design))
	say(("Copied the %s { } source to the clipboard"):format(E.design.kind == "weapon" and "module" or E.isPlaced() and E.design.kind or "hull"))
end

-- Register the design right now and try it: fly a hull, or drop a wreck
-- or prop just ahead of you.
function E.testFly()
	local def, err = E.define()
	if not def then say("Can't use it: " .. tostring(err)) return end
	local game = Editor.game
	if not game then return end
	if E.design.kind == "weapon" then return E.testWeapon(def) end
	if E.isPlaced() then
		local p = game.player
		if not p or p.dead then say("Need a live ship to spawn it next to") return end
		Editor.close()
		local x, y = p.body:getPosition()
		local a = p.body:getAngle()
		local d = (p.halfLength or 40) + def.radius * 2 + 120
		local vx, vy = p.body:getLinearVelocity()
		if E.design.kind == "station" then
			d = (p.halfLength or 40) + def.radius + 300
			game:spawnStation(def.id, x + math.cos(a) * d, y + math.sin(a) * d, 0)
		else
			game:spawnWreck(def.id, x + math.cos(a) * d, y + math.sin(a) * d, nil, vx, vy)
		end
		say(("Spawned %s ahead of you (F2 to go back)"):format(def.name))
		return
	end
	Editor.close()
	if game.state == "dead" then game:respawn() end
	game:spawnPlayer(def.id)
	say("Flying " .. def.name .. " (F2 to go back)")
end

-- Fit the weapon to every slot of your ship it fits and fly it, with a
-- wreck ahead to shoot at.
function E.testWeapon(def)
	local game = Editor.game
	local p = game.player
	local hullId = game.playerHull
	local hull = data.hulls[hullId]
	if not hull then say("No ship to fit it to") return end
	local loadout = {}
	local base = (p and p.loadout) or hull.loadout or {}
	local fitted = 0
	for i, slot in ipairs(hull.slots) do
		loadout[i] = base[i] or false
		if data.fits(slot, def) then loadout[i] = def.id; fitted = fitted + 1 end
	end
	if fitted == 0 then say(("%s has no %s %s slot for it"):format(hull.name, def.size, def.family == "bay" and "bay" or "hardpoint")) return end
	local cargo
	if p and p.cargo then cargo = {}; for k, v in pairs(p.cargo) do cargo[k] = v end end
	cargo = cargo or {}
	local ammo = data.ammoFor(def)
	if ammo then cargo[ammo] = math.max(cargo[ammo] or 0, 200) end
	Editor.close()
	if game.state == "dead" then game:respawn() end
	local ship = game:spawnPlayer(hullId, loadout, cargo)
	local x, y = ship.body:getPosition()
	local a = ship.body:getAngle()
	if data.list.wrecks[1] and game.spawnWreck then
		local d = (ship.halfLength or 40) + 400
		game:spawnWreck(data.list.wrecks[1], x + math.cos(a) * d, y + math.sin(a) * d)
	end
	say(("Fitted %s to %d slot%s on the %s (F2 to go back)"):format(def.name, fitted, fitted == 1 and "" or "s", hull.name))
end

-- Open / close --------------------------------------------------------------

function Editor.isOpen() return E.isOpenFlag end

function Editor.open(game)
	Editor.game = game
	Export.refresh()
	-- the generated wheel layouts, so they can be opened and redrawn
	local Stations = require("src.stations")
	for _, rt in ipairs({ { 900, 120 }, { 1400, 160 }, { 3000, 300 } }) do
		if not data.stations[Stations.ringId(rt[1], rt[2])] then data.defineStation(Stations.ring(rt[1], rt[2])) end
	end
	for k = 1, 2 do
		if not data.stations[Stations.cityId(k)] then data.defineStation(Stations.city(k)) end
	end
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
	require("src.editor.comparison").clear()
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
	-- text boxes need SDL text input on; other screens may have switched it off
	if not love.keyboard.hasTextInput() then love.keyboard.setTextInput(true) end
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
		if E.drawing then E.drawing = nil else E.sel, E.vsel, E.bsel, E.tsel, E.multi = nil, nil, nil, nil, {}; E.lmulti, E.vmulti = {}, {} end
	elseif key == "delete" or key == "backspace" then E.deleteSelected()
	end
	return true
end

-- What the canvas paints the design with: a hull wears its factory preset,
-- anything else the preview colour picked in the Preview section.
function E.previewPaint()
	if (E.design.kind or "hull") == "hull" then local Paint = require("src.paint"); return Paint.preset(Paint.pool({ paints = E.stat("paints") })[1]) end
	return E.paint
end

-- Paints to preview against (shade and tint are relative to the paint).
Editor.PAINTS = Render.PAINTS

return Editor
