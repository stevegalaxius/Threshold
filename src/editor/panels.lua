--[[
	The Shipyard's Slab windows: the design panel on the left (file,
	tools, view, parts list) and the part inspector on the right.
]]

local Slab = require("lib.Slab")
local data = require("src.data")
local Canvas = require("src.editor.canvas")
local HullShape = require("src.hullshape")

local Panels = {}

local ROLES = { "", "engine", "cockpit", "weapon", "dock", "light", "antenna", "rack", "armor", "sensor" }
local LAYERS = { "hull", "detail", "glow" }
local GRIDS = { 1, 2, 4, 8, 16 }
local PREVIEWS = { normal = "Normal", wreck = "Wreck", collision = "Collision", ["break"] = "Break apart" }

-- Hull stats the design can set over its base hull (see data/hulls.lua).
local STATS = {
	{ "mass", "mass (t)", "Dry weight in tonnes. Heavier = slower to accelerate and turn.", 1, 5000, 5, 0 },
	{ "armor", "armor", "Hit points of the hull itself.", 10, 5000, 10, 0 },
	{ "hold", "hold (m3)", "Cargo space in cubic metres.", 0, 1000, 1, 0 },
	{ "drag", "drag", "Quadratic drag. Top speed = sqrt(thrust x 100 / drag), so lower drag = faster.", 0.01, 5, 0.01, 2 },
	{ "turn", "turn torque", "How hard it rotates. Bigger = snappier.", 0, 20000, 50, 0 },
	{ "turnSpeed", "turn cap (deg/s)", "Optional top spin speed, so a heavy hull comes about slowly even with lots of torque.", 10, 720, 5, 0 },
	{ "retroThrust", "retro (kN)", "Built-in reverse thrusters (the main engine only pushes forward).", 0, 3000, 10, 0 },
	{ "spoolTime", "spool (s)", "Seconds for the main engine to reach full thrust. A slight ramp makes heavy hulls feel heavy. 0 = instant.", 0, 3, 0.05, 2 },
	{ "ramSpeed", "ram speed", "Impact speed (px/s) below which a bump does no harm. Low = fragile.", 20, 500, 5, 0 },
	{ "turretTurn", "turret (deg/s)", "How fast turret-mounted guns swing round. Only matters when mount is turret.", 10, 720, 5, 0 },
	{ "price", "price", "Credits to buy it.", 0, 1000000, 500, 0 },
}
local FAMILIES = { "primary", "secondary", "auxiliary", "engine", "reactor", "utility", "thruster", "computer" }
local SIZES = { "S", "M", "L" }
-- Families with no sizes: their slots are always "any" (data/hulls.lua).
local SIZELESS = { utility = true, computer = true, thruster = true }

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

	local opts = {}
	for _, id in ipairs(data.list.hulls) do
		table.insert(opts, { label = data.hulls[id].name .. "  (" .. id .. ")", value = id })
	end
	Slab.Text("Start from")
	combo("yard_open", "Edit an existing hull...", opts, function(id) E.openHull(id) end, 220)
	Slab.SameLine()
	if Slab.Button("Blank", { Tooltip = "A new empty design" }) then E.newDesign() end
	Slab.Text("Opening a hull loads its shape, stats and slots.", { Color = { 0.6, 0.6, 0.6 } })
	Slab.Text("Export with the same id to replace it.", { Color = { 0.6, 0.6, 0.6 } })

	Slab.Separator()
	Slab.Text("This design")
	Slab.Text("id"); Slab.SameLine()
	textField(E, "yard_id", d.id, function(t) d.id = t:gsub("[^%w_]", "_") end, 220)
	Slab.Text("name"); Slab.SameLine()
	textField(E, "yard_name", d.name, function(t) d.name = t end, 220)
	if Slab.Button("Test fly") then E.testFly() end
	Slab.SameLine()
	if Slab.Button("Export") then E.export() end
	Slab.SameLine()
	if Slab.Button("Copy source") then E.copySource() end
	if Slab.Button("Undo") then E.undoStep() end
	Slab.SameLine()
	if Slab.Button("Redo") then E.redoStep() end

	Slab.Separator()
	Slab.Text("Tool")
	local tools = { { "select", "Select (V)" }, { "draw", "Polygon (P)" }, { "rect", "Rect (B)" }, { "light", "Lights (L)" } }
	local current = 1
	for i, t in ipairs(tools) do if E.tool == t[1] then current = i end end
	for i, t in ipairs(tools) do
		if Slab.RadioButton(t[2], { Index = i, SelectedIndex = current }) then
			E.tool = t[1]
			if t[1] ~= "draw" then E.drawing = nil end
		end
	end
	if E.tool == "light" then
		Slab.Text("Click a part for one light, drag for a row", { Color = { 0.6, 0.6, 0.6 } })
		local kopts = { { label = "window (steady)", value = "window" }, { label = "nav (blinking)", value = "nav" } }
		combo("yard_lightkind", E.lightKind == "nav" and "nav (blinking)" or "window (steady)", kopts, function(k) E.lightKind = k end, 160)
		Slab.Text("row spacing (px)")
		if Slab.InputNumberDrag("yard_lightspacing", E.lightSpacing, 2, 64, 1, { W = 90 }) then E.lightSpacing = Slab.GetInputNumber() end
	end
	if Slab.CheckBox(E.mirrorNew, "New parts get a mirror twin") then E.mirrorNew = not E.mirrorNew end
	if Slab.CheckBox(E.snap, "Snap to grid (G, Alt places freely)") then E.snap = not E.snap end
	local gopts = {}
	for _, g in ipairs(GRIDS) do table.insert(gopts, { label = g .. " px", value = g }) end
	combo("yard_grid", E.grid .. " px", gopts, function(g) E.grid = g end, 120)

	Slab.Separator()
	Slab.Text("Preview")
	local popts = {}
	for _, k in ipairs({ "normal", "wreck", "collision", "break" }) do table.insert(popts, { label = PREVIEWS[k], value = k }) end
	combo("yard_preview", PREVIEWS[E.preview], popts, function(k) E.preview = k end, 140)
	local paints, current = {}, "(custom)"
	for _, pt in ipairs(Editor.PAINTS) do
		table.insert(paints, { label = pt.name, value = pt.color })
		if pt.color == E.paint then current = pt.name end
	end
	combo("yard_paint", current, paints, function(c) E.paint = c end, 140)
	if Slab.Button("Centre view") then E.view.x, E.view.y = 0, 0 end

	Slab.Separator()
	if Slab.BeginTree("yard_stats", { Label = "Hull stats" }) then
		local base = data.hulls[d.base]
		Slab.Text("Unchanged stats come from")
		combo("yard_base", base and base.name or "?", opts, function(id) E.pushUndo(); E.setBase(id) end, 200)
		Slab.Text("Picking one resets stats and slots, keeps the shape.", { Color = { 0.6, 0.6, 0.6 } })
		for _, st in ipairs(STATS) do
			local key, label, help = st[1], st[2], st[3]
			Slab.Button("?", { W = 18, H = 18, Tooltip = help })
			Slab.SameLine()
			local own = d.stats[key]
			local v = E.stat(key)
			Slab.Text(label .. (own ~= nil and " *" or ""))
			Slab.SameLine({ Pad = 4 })
			-- drag sideways or type; each stat has a sensible range and step
			local lo, hi, step, prec = st[4], st[5], st[6], st[7]
			if Slab.InputNumberDrag("yard_stat_" .. key, v or lo, lo, hi, step, { W = 90, Precision = prec }) then
				E.pushUndo()
				d.stats[key] = Slab.GetInputNumber()
			end
			if own ~= nil then
				Slab.SameLine()
				if Slab.Button("x", { W = 18, H = 18, Tooltip = "Back to the base hull's value" }) then E.pushUndo(); d.stats[key] = nil end
			end
		end
		local mopts = {}
		for _, m in ipairs({ "fixed", "gimbal", "turret" }) do table.insert(mopts, { label = m, value = m }) end
		Slab.Button("?", { W = 18, H = 18, Tooltip = "fixed: guns point down the nose, you aim with the ship.\ngimbal: guns swing a few degrees toward the cursor.\nturret: guns rotate all the way round at the turret speed.\nThis is the default; each weapon slot can set its own in the Slots list." })
		Slab.SameLine()
		Slab.Text("default mount"); Slab.SameLine()
		combo("yard_mount", E.stat("mount") or "gimbal", mopts, function(m) E.pushUndo(); d.stats.mount = m end, 120)
		local hopts = { { label = "strafe", value = "strafe" }, { label = "turn", value = "turn" } }
		Slab.Button("?", { W = 18, H = 18, Tooltip = "strafe: A/D slide sideways on the side thrusters.\nturn: A/D rotate the hull and the mouse only aims the guns (battleships)." })
		Slab.SameLine()
		Slab.Text("helm"); Slab.SameLine()
		combo("yard_helm", E.stat("helm") or "strafe", hopts, function(m) E.pushUndo(); d.stats.helm = m end, 120)
		Slab.Text("class"); Slab.SameLine()
		textField(E, "yard_class", E.stat("class"), function(t) d.stats.class = t end, 150)
		Slab.Text("maker"); Slab.SameLine()
		textField(E, "yard_maker", E.stat("maker"), function(t) d.stats.maker = t end, 150)
		Slab.EndTree()
	end
	if Slab.BeginTree("yard_slots", { Label = ("Slots (%d), drag markers on the canvas"):format(#d.slots) }) then
		local remove
		for i, slot in ipairs(d.slots) do
			Slab.PushID("yard_slot" .. i)
			local selected = E.slotSel == i
			local c = Canvas.SLOT_COLORS[slot.family]
			if Slab.TextSelectable(("%s%d."):format(selected and ">" or " ", i), { IsSelectableTextOnly = true, Color = c }) then E.slotSel = i end
			Slab.SameLine()
			local fopts = {}
			for _, f in ipairs(FAMILIES) do table.insert(fopts, { label = f, value = f }) end
			combo("yard_slotfam" .. i, slot.family, fopts, function(f)
				E.pushUndo()
				slot.family = f
				if SIZELESS[f] then slot.size = "any" elseif slot.size == "any" then slot.size = "S" end
				if f ~= "primary" and f ~= "secondary" and f ~= "auxiliary" then slot.mount = nil end
			end, 95)
			if not SIZELESS[slot.family] then
				Slab.SameLine()
				local sopts = {}
				for _, s in ipairs(SIZES) do table.insert(sopts, { label = s, value = s }) end
				combo("yard_slotsize" .. i, slot.size, sopts, function(s) E.pushUndo(); slot.size = s end, 50)
			end
			if slot.family == "primary" or slot.family == "secondary" or slot.family == "auxiliary" then
				-- weapon slots can mount differently from the hull's default
				Slab.SameLine()
				local mo = { { label = "(hull)", value = false } }
				for _, m in ipairs({ "fixed", "gimbal", "turret" }) do table.insert(mo, { label = m, value = m }) end
				combo("yard_slotmount" .. i, slot.mount or "(hull)", mo, function(m) E.pushUndo(); slot.mount = m or nil end, 70)
			end
			Slab.SameLine()
			if Slab.Button(slot.x and "on hull" or "place", { W = 58, H = 18, Tooltip = slot.x and "Click to take it off the hull (not drawn, fires from the centre)" or "Put a hardpoint on the hull at the origin" }) then
				E.pushUndo()
				if slot.x then slot.x, slot.y = nil, nil else slot.x, slot.y = 0, 0 end
			end
			Slab.SameLine()
			if Slab.Button("x", { W = 18, H = 18, Tooltip = "Remove this slot" }) then remove = i end
			Slab.PopID()
		end
		if remove then E.pushUndo(); table.remove(d.slots, remove); E.slotSel = nil end
		if Slab.Button("Add slot") then
			E.pushUndo()
			table.insert(d.slots, { family = "primary", size = "S", x = 0, y = 0 })
			E.slotSel = #d.slots
		end
		Slab.Text("Modules that no longer fit a slot are", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("left empty when you test fly.", { Color = { 0.6, 0.6, 0.6 } })
		Slab.EndTree()
	end

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
	Slab.Text(("Parts (%d), drawn top to bottom"):format(#d.parts))
	Slab.Text("click a name to select it", { Color = { 0.6, 0.6, 0.6 } })
	for i, p in ipairs(d.parts) do
		Slab.PushID("yard_part" .. i)
		local selected = E.sel == i
		-- one row per part: order, visibility and lock as small toggles,
		-- then the name, highlighted when selected
		if Slab.Button("^", { W = 18, H = 18 }) then E.movePart(i, -1) end
		Slab.SameLine()
		if Slab.Button("v", { W = 18, H = 18 }) then E.movePart(i, 1) end
		Slab.SameLine()
		if Slab.Button(p.hidden and "-" or "o", { W = 18, H = 18, Tooltip = p.hidden and "Hidden: click to show" or "Visible: click to hide" }) then
			p.hidden = not p.hidden or nil
		end
		Slab.SameLine()
		if Slab.Button(p.locked and "L" or " ", { W = 18, H = 18, Tooltip = p.locked and "Locked: click to unlock" or "Click to lock (can't be picked on the canvas)" }) then
			p.locked = not p.locked or nil
		end
		Slab.SameLine()
		local tags = (p.mirror and " [mirror]" or "") .. (i == E.coreIndex and " [core]" or "") .. (E.errors[i] and " [!]" or "")
		local label = (selected and "> " or "  ") .. (p.name or ("part " .. i)) .. tags
		local color = E.errors[i] and { 1, 0.45, 0.45 } or selected and { 1, 0.85, 0.3 } or (p.hidden and { 0.5, 0.5, 0.5 } or nil)
		if Slab.TextSelectable(label, { IsSelectableTextOnly = true, IsSelected = selected, Color = color }) then E.sel, E.vsel, E.lsel = i, nil, nil end
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
	local light = E.lsel and p.lights and p.lights[E.lsel]
	if light then
		Slab.Text(("Light %d of %d on this part"):format(E.lsel, #p.lights))
		local kopts = { { label = "window", value = "window" }, { label = "nav", value = "nav" } }
		combo("yard_lkind" .. i, light.kind or "window", kopts, function(k)
			E.pushUndo()
			light.kind = k
			if k == "nav" then light.rate, light.phase = light.rate or 1, light.phase or 0 end
		end, 120)
		local def = light.kind == "nav" and HullShape.NAV or HullShape.WINDOW
		local c = light.color or def
		for ci, name in ipairs({ "r", "g", "b" }) do
			Slab.Text(name); Slab.SameLine()
			slider(E, "yard_lc" .. name .. i, c[ci], 0, 1, function(v)
				light.color = light.color or { def[1], def[2], def[3] }
				light.color[ci] = v
			end)
		end
		Slab.Text("size (px)")
		slider(E, "yard_lsize" .. i, light.size or (light.kind == "nav" and 2.5 or 1.5), 0.5, 8, function(v) light.size = v end, 1)
		if light.kind == "nav" then
			Slab.Text("blinks per second")
			slider(E, "yard_lrate" .. i, light.rate or 1, 0.1, 4, function(v) light.rate = v end)
			Slab.Text("phase (offset between lights)")
			slider(E, "yard_lphase" .. i, light.phase or 0, 0, 1, function(v) light.phase = v end)
		end
		if Slab.Button("Delete light") then E.deleteSelected() end
		Slab.SameLine()
		if Slab.Button("Back to the part") then E.lsel = nil end
		Slab.Separator()
	end
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
	check(E, p.explode == true, "Bursts into loot when shot off", function(on) p.explode = on or nil end)
	Slab.Text("Mass multiplier (when it breaks away)")
	slider(E, "yard_mass" .. i, p.mass or 1, 0.1, 5, function(v) p.mass = v end)
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
