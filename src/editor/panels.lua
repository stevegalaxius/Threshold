--[[
	The Shipyard's Slab windows: the design panel on the left (file,
	tools, view, parts list) and the part inspector on the right.
]]

local Slab = require("lib.Slab")
local data = require("src.data")
local Canvas = require("src.editor.canvas")

local Panels = {}

local ROLES = { "", "engine", "cockpit", "weapon", "dock", "light", "antenna", "rack", "armor", "sensor" }
local LAYERS = { "hull", "detail", "glow" }
local GRIDS = { 1, 2, 4, 8, 16 }
local PREVIEWS = { normal = "Normal", wreck = "Wreck", collision = "Collision" }

local function combo(id, selected, options, onPick, w)
	if Slab.BeginComboBox(id, { Selected = selected, W = w or 200 }) then
		for _, opt in ipairs(options) do
			if Slab.TextSelectable(opt.label) then onPick(opt.value) end
		end
		Slab.EndComboBox()
	end
end

local function textField(E, id, value, onChange, w)
	if Slab.Input(id, { Text = value or "", W = w or 200, ReturnOnText = true }) then
		E.pushUndoCoalesced(id)
		onChange(Slab.GetInputText())
	end
end

local function slider(E, id, value, lo, hi, onChange, precision)
	if Slab.InputNumberSlider(id, value, lo, hi, { W = 200, Precision = precision or 2 }) then
		E.pushUndoCoalesced(id)
		onChange(Slab.GetInputNumber())
	end
end

local function check(E, value, label, onChange)
	if Slab.CheckBox(value, label) then
		E.pushUndo()
		onChange(not value)
	end
end

-- Left: the design ------------------------------------------------------

local function designWindow(E, Editor)
	local h = love.graphics.getHeight()
	Slab.BeginWindow("yard_design", {
		Title = "Shipyard  (F2 closes)", X = 10, Y = 10, W = 310, H = h - 20,
		AutoSizeWindow = false, AllowResize = true,
	})
	local d = E.design

	Slab.Text("Design")
	Slab.Text("id"); Slab.SameLine()
	textField(E, "yard_id", d.id, function(t) d.id = t:gsub("[^%w_]", "_") end, 220)
	Slab.Text("name"); Slab.SameLine()
	textField(E, "yard_name", d.name, function(t) d.name = t end, 220)
	local opts = {}
	for _, id in ipairs(data.list.hulls) do
		table.insert(opts, { label = data.hulls[id].name .. "  (" .. id .. ")", value = id })
	end
	Slab.Text("Flies with the stats and slots of")
	local base = data.hulls[d.base]
	combo("yard_base", base and base.name or "?", opts, function(id) E.pushUndo(); E.setBase(id) end, 280)

	if Slab.Button("New") then E.newDesign() end
	Slab.SameLine()
	if Slab.Button("Test fly") then E.testFly() end
	Slab.SameLine()
	if Slab.Button("Export") then E.export() end
	Slab.SameLine()
	if Slab.Button("Copy") then E.copySource() end
	Slab.Text("Open a hull")
	combo("yard_open", "(pick one)", opts, function(id) E.openHull(id) end, 280)
	if Slab.Button("Undo") then E.undoStep() end
	Slab.SameLine()
	if Slab.Button("Redo") then E.redoStep() end
	Slab.SameLine()
	Slab.Text(("%d / %d"):format(#E.undo, #E.redo))

	Slab.Separator()
	Slab.Text("Tool")
	local tools = { { "select", "Select (V)" }, { "draw", "Polygon (P)" }, { "rect", "Rect (B)" } }
	for i, t in ipairs(tools) do
		if Slab.RadioButton(t[2], { Index = i, SelectedIndex = (E.tool == "select" and 1 or E.tool == "draw" and 2 or 3) }) then
			E.tool = t[1]
			if t[1] ~= "draw" then E.drawing = nil end
		end
	end
	if Slab.CheckBox(E.mirrorNew, "New parts get a mirror twin") then E.mirrorNew = not E.mirrorNew end
	if Slab.CheckBox(E.snap, "Snap to grid (G, Alt places freely)") then E.snap = not E.snap end
	local gopts = {}
	for _, g in ipairs(GRIDS) do table.insert(gopts, { label = g .. " px", value = g }) end
	combo("yard_grid", E.grid .. " px", gopts, function(g) E.grid = g end, 120)

	Slab.Separator()
	Slab.Text("Preview")
	local popts = {}
	for _, k in ipairs({ "normal", "wreck", "collision" }) do table.insert(popts, { label = PREVIEWS[k], value = k }) end
	combo("yard_preview", PREVIEWS[E.preview], popts, function(k) E.preview = k end, 140)
	local paints, current = {}, "(custom)"
	for _, pt in ipairs(Editor.PAINTS) do
		table.insert(paints, { label = pt.name, value = pt.color })
		if pt.color == E.paint then current = pt.name end
	end
	combo("yard_paint", current, paints, function(c) E.paint = c end, 140)
	if Slab.Button("Centre view") then E.view.x, E.view.y = 0, 0 end

	Slab.Separator()
	-- the wreck's numbers: share of the area, and which part is the core
	local total, biggest, tagged = 0, nil, nil
	local function areaOf(p) return Canvas.area(p.shape) * (p.mirror and 2 or 1) end
	for i, p in ipairs(d.parts) do
		if not p.hidden then
			total = total + areaOf(p)
			if p.core then tagged = tagged or i end
			if p.collide ~= false and (not biggest or Canvas.area(p.shape) > Canvas.area(d.parts[biggest].shape)) then biggest = i end
		end
	end
	E.coreIndex = tagged or biggest
	E.totalArea = total
	Slab.Text(("Parts (%d)   top of the list draws first"):format(#d.parts))
	for i, p in ipairs(d.parts) do
		Slab.PushID("yard_part" .. i)
		local label = ("%s%s%s%s"):format(p.name or ("part " .. i), p.mirror and "  [mirror]" or "",
			i == E.coreIndex and "  [core]" or "", E.errors[i] and "  [!]" or "")
		if Slab.TextSelectable(label, { IsSelected = E.sel == i }) then E.sel, E.vsel = i, nil end
		if Slab.Button("^", { W = 22 }) then E.movePart(i, -1) end
		Slab.SameLine()
		if Slab.Button("v", { W = 22 }) then E.movePart(i, 1) end
		Slab.SameLine()
		if Slab.CheckBox(p.hidden, "hide") then p.hidden = not p.hidden or nil end
		Slab.SameLine()
		if Slab.CheckBox(p.locked, "lock") then p.locked = not p.locked or nil end
		Slab.PopID()
	end
	Slab.EndWindow()
end

-- Right: the selected part -------------------------------------------------

local function partWindow(E)
	local p = E.sel and E.design.parts[E.sel]
	if not p then return end
	local w, h = love.graphics.getWidth(), love.graphics.getHeight()
	Slab.BeginWindow("yard_part", {
		Title = "Part", X = w - 300, Y = 10, W = 290, H = h - 20,
		AutoSizeWindow = false, AllowResize = true,
	})
	local i = E.sel
	if E.errors[i] then Slab.Text("! " .. E.errors[i], { Color = { 1, 0.4, 0.4 } }) end
	local a = Canvas.area(p.shape) * (p.mirror and 2 or 1)
	Slab.Text(("%d points   area %d px2"):format(#p.shape / 2, a))
	if E.totalArea and E.totalArea > 0 then
		Slab.Text(("%.0f%% of the wreck%s"):format(a / E.totalArea * 100, i == E.coreIndex and ", the core" or ""))
	end

	Slab.Text("name"); Slab.SameLine()
	textField(E, "yard_pname" .. i, p.name, function(t) p.name = t end, 200)

	Slab.Separator()
	Slab.Text("Look")
	slider(E, "yard_shade" .. i, p.shade or 1, 0, 1.5, function(v) p.shade = v end)
	Slab.Text("Tint (added to the paint)")
	local tint = p.tint or { 0, 0, 0 }
	for c, name in ipairs({ "r", "g", "b" }) do
		Slab.Text(name); Slab.SameLine()
		slider(E, "yard_tint" .. name .. i, tint[c], -1, 1, function(v)
			local t = p.tint or { 0, 0, 0 }
			t[c] = v
			p.tint = (t[1] == 0 and t[2] == 0 and t[3] == 0) and nil or t
		end)
	end
	check(E, p.color ~= nil, "Fixed colour (ignores the paint)", function(on)
		p.color = on and { E.paint[1], E.paint[2], E.paint[3] } or nil
	end)
	if p.color then
		for c, name in ipairs({ "r", "g", "b" }) do
			Slab.Text(name); Slab.SameLine()
			slider(E, "yard_col" .. name .. i, p.color[c], 0, 1, function(v) p.color[c] = v end)
		end
	end
	Slab.Text("Layer")
	local lopts = {}
	for _, l in ipairs(LAYERS) do table.insert(lopts, { label = l, value = l }) end
	combo("yard_layer" .. i, p.layer or "hull", lopts, function(l) E.pushUndo(); p.layer = l ~= "hull" and l or nil end, 140)

	Slab.Separator()
	Slab.Text("Wreck")
	check(E, p.mirror == true, "Mirror twin across the spine (M)", function(on) p.mirror = on or nil end)
	check(E, p.cargo == true, "Carries cargo", function(on) p.cargo = on or nil end)
	Slab.Text("  (no part tagged: every part carries)", { Color = { 0.6, 0.6, 0.6 } })
	check(E, p.core == true, "Core (stays when the rest is shot off)", function(on) p.core = on or nil end)
	check(E, p.breakable ~= false, "Can be shot off", function(on) p.breakable = (not on) and false or nil end)
	check(E, p.collide ~= false, "Collides (off: drawn only)", function(on) p.collide = (not on) and false or nil end)
	Slab.Text("Armour multiplier")
	slider(E, "yard_armor" .. i, p.armor or 1, 0.1, 5, function(v) p.armor = v end)
	Slab.Text("Role")
	local ropts = {}
	for _, r in ipairs(ROLES) do table.insert(ropts, { label = r == "" and "(none)" or r, value = r }) end
	combo("yard_role" .. i, (p.role and p.role ~= "") and p.role or "(none)", ropts, function(r) E.pushUndo(); p.role = r ~= "" and r or nil end, 140)

	Slab.Separator()
	Slab.Text("Shape")
	if Slab.Button("Flip nose-tail") then E.transformSelected(function(x, y) return -x, y end, true) end
	Slab.SameLine()
	if Slab.Button("Flip sides") then E.transformSelected(function(x, y) return x, -y end, true) end
	if Slab.Button("Rotate 90") then E.transformSelected(function(x, y) return -y, x end) end
	Slab.SameLine()
	if Slab.Button("Rotate 15") then
		local c, s = math.cos(math.pi / 12), math.sin(math.pi / 12)
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c end)
	end
	if Slab.Button("Scale -10%") then
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * 0.9, cy + (y - cy) * 0.9 end)
	end
	Slab.SameLine()
	if Slab.Button("Scale +10%") then
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * 1.1, cy + (y - cy) * 1.1 end)
	end
	if Slab.Button("Symmetrize about the spine") then E.symmetrizeSelected() end
	if Slab.Button("Duplicate (Ctrl+D)") then E.duplicateSelected() end
	Slab.SameLine()
	if Slab.Button("Delete") then E.vsel = nil; E.deleteSelected() end
	Slab.EndWindow()
end

function Panels.update(E, Editor)
	designWindow(E, Editor)
	partWindow(E)
end

return Panels
