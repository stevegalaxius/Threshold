--[[
	A hold: a set of grids that act as one. A ship's hold is its main grid
	plus one small grid per fitted Cargo Pod; a husk's is a single grid.

	Layouts are lists of { key, name, w, h }. The key ties a grid to where
	it comes from ("hull", "slot7"), so a refit keeps the grids that didn't
	change exactly as they were.

	Items go in as stacks with the shapes from shapes.lua. Adding tops up
	partial stacks of the same item first, then places new stacks in the
	first space that fits, trying each grid unrotated before rotated.
	Taking empties the smallest stacks first, so firing frees whole cells
	instead of thinning every stack.

	A stack can carry wear (0..1): the share of armour a docked drone had
	lost. Taking prefers unworn stacks.

	A stack can carry a hold of its own (stack.inner): a loaded cargo
	container. Those are never split up or rebuilt from counts; sorting and
	relayouts move the stack itself (placeStack), so what's inside stays.
]]

local Grid = require("src.inventory.grid")
local Shapes = require("src.inventory.shapes")

local Hold = {}

local min = math.min

function Hold.new(layout)
	local h = { grids = {} }
	for _, l in ipairs(layout) do
		local g = Grid.new(l.w, l.h, l.name)
		g.key = l.key
		table.insert(h.grids, g)
	end
	return h
end

function Hold.count(h, id)
	local n = 0
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do
			if s.id == id then n = n + s.n end
		end
	end
	return n
end

-- { itemId = count } for everything aboard.
function Hold.totals(h, out)
	out = out or {}
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do out[s.id] = (out[s.id] or 0) + s.n end
	end
	return out
end

-- Cells used and cells in all, which is cubic metres.
function Hold.cells(h)
	local used, total = 0, 0
	for _, g in ipairs(h.grids) do
		used = used + Grid.cellsUsed(g)
		total = total + g.w * g.h
	end
	return used, total
end

-- Where a new w x h stack can go: the first grid with room, unrotated
-- first. With rand (a random(a, b) function) it tries a few random spots
-- before that, for loosely packed holds.
local function findSpot(h, w, ht, rand)
	if rand then
		for _ = 1, 12 do
			local g = h.grids[rand(1, #h.grids)]
			local rot = w ~= ht and rand(0, 1) == 1
			local fw, fh = w, ht
			if rot then fw, fh = ht, w end
			if fw <= g.w and fh <= g.h then
				local x, y = rand(0, g.w - fw), rand(0, g.h - fh)
				if Grid.isFree(g, x, y, fw, fh) then return g, x, y, fw, fh, rot end
			end
		end
	end
	for _, g in ipairs(h.grids) do
		local x, y = Grid.firstFit(g, w, ht)
		if x then return g, x, y, w, ht, false end
	end
	if w ~= ht then
		for _, g in ipairs(h.grids) do
			local x, y = Grid.firstFit(g, ht, w)
			if x then return g, x, y, ht, w, true end
		end
	end
	return nil
end

-- Put an existing stack (one that carries something, like a loaded
-- container) in the first space that fits, keeping the stack table.
-- Returns true if it went in.
function Hold.placeStack(h, s, rand)
	local w, ht = Shapes.of(s.id)
	local g, x, y, fw, fh, rot = findSpot(h, w, ht, rand)
	if not g then return false end
	s.x, s.y, s.w, s.h, s.rot = x, y, fw, fh, rot
	Grid.place(g, s)
	return true
end

-- Mass of whatever loaded containers in the hold carry.
function Hold.innerMass(h, items)
	local m = 0
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do
			if s.inner then
				for id, n in pairs(Hold.totals(s.inner)) do m = m + items[id].mass * n end
			end
		end
	end
	return m
end

-- Stacks that carry something, and the counts of everything else.
local function split(h)
	local carried, counts = {}, {}
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do
			if s.inner then table.insert(carried, s) else counts[s.id] = (counts[s.id] or 0) + s.n end
		end
	end
	return carried, counts
end

-- Add up to n of an item; returns how many went in.
-- opts.random: a random(a, b) function, to scatter stacks loosely.
function Hold.add(h, id, n, opts)
	if n <= 0 then return 0 end
	local w, ht, cap = Shapes.of(id)
	local left = n
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do
			if s.id == id and s.n < cap then
				local k = min(cap - s.n, left)
				s.n, left = s.n + k, left - k
				if left == 0 then return n end
			end
		end
	end
	local rand = opts and opts.random
	while left > 0 do
		local g, x, y, fw, fh, rot = findSpot(h, w, ht, rand)
		if not g then break end
		local k = min(cap, left)
		Grid.place(g, { id = id, n = k, x = x, y = y, w = fw, h = fh, rot = rot })
		left = left - k
	end
	return n - left
end

-- Take up to n of an item, smallest stacks first; returns how many.
function Hold.take(h, id, n)
	local list = {}
	for _, g in ipairs(h.grids) do
		for _, s in ipairs(g.stacks) do
			if s.id == id then table.insert(list, { g = g, s = s }) end
		end
	end
	-- smallest first, and loaded containers last of all
	table.sort(list, function(a, b)
		if (a.s.inner ~= nil) ~= (b.s.inner ~= nil) then return b.s.inner ~= nil end
		if (a.s.wear or 0) ~= (b.s.wear or 0) then return (a.s.wear or 0) < (b.s.wear or 0) end
		return a.s.n < b.s.n
	end)
	local left = n
	for _, e in ipairs(list) do
		if left <= 0 then break end
		local k = min(e.s.n, left)
		e.s.n, left = e.s.n - k, left - k
		if e.s.n <= 0 then Grid.remove(e.g, e.s) end
	end
	return n - left
end

-- Packing order for filling a hold from counts: biggest footprints first
-- (they're the hardest to fit), then by id so it's the same every time.
local function packingOrder(counts)
	local ids = {}
	for id, n in pairs(counts) do
		if n > 0 then table.insert(ids, id) end
	end
	table.sort(ids, function(a, b)
		local aw, ah = Shapes.of(a)
		local bw, bh = Shapes.of(b)
		if aw * ah ~= bw * bh then return aw * ah > bw * bh end
		return a < b
	end)
	return ids
end

-- Add a whole { id = count } table; returns what didn't fit.
function Hold.fill(h, counts, opts)
	local left = {}
	for _, id in ipairs(packingOrder(counts)) do
		local got = Hold.add(h, id, counts[id], opts)
		if got < counts[id] then left[id] = counts[id] - got end
	end
	return left
end

-- Make the hold hold exactly `counts`, as near as it can: take what's gone,
-- add what's new. Then rewrite counts to what the hold really has. This is
-- how the rest of the game talks to a grid hold: weapons and the debug
-- panel change ship.cargo, and the grid catches up here.
function Hold.sync(h, counts)
	local have = Hold.totals(h)
	local add = {}
	for id, n in pairs(have) do
		local want = counts[id] or 0
		if want < n then Hold.take(h, id, n - want) end
	end
	for id, want in pairs(counts) do
		local n = have[id] or 0
		if want > n then add[id] = want - n end
	end
	Hold.fill(h, add)
	for id in pairs(counts) do counts[id] = nil end
	Hold.totals(h, counts)
	return counts
end

-- A copy to try things on without touching the real one.
function Hold.clone(h)
	local c = { grids = {} }
	for _, g in ipairs(h.grids) do
		local cg = Grid.new(g.w, g.h, g.name)
		cg.key = g.key
		for _, s in ipairs(g.stacks) do
			Grid.place(cg, { id = s.id, n = s.n, x = s.x, y = s.y, w = s.w, h = s.h, rot = s.rot, inner = s.inner, resale = s.resale, wear = s.wear })
		end
		table.insert(c.grids, cg)
	end
	return c
end

-- How many of an item would go in right now.
function Hold.room(h, id, n)
	return Hold.add(Hold.clone(h), id, n)
end

-- Repack the hold neatly (biggest items first, grouped by type). If the
-- tidy version wouldn't fit everything it leaves the hold as it was and
-- returns false.
function Hold.sort(h)
	local layout = {}
	for _, g in ipairs(h.grids) do table.insert(layout, { key = g.key, name = g.name, w = g.w, h = g.h }) end
	local n = Hold.new(layout)
	local carried, counts = split(h)
	local saved = {}
	for _, s in ipairs(carried) do saved[s] = { s.x, s.y, s.w, s.h, s.rot } end
	local ok = true
	for _, s in ipairs(carried) do
		if not Hold.placeStack(n, s) then ok = false end
	end
	if ok and next(Hold.fill(n, counts)) then ok = false end
	if not ok then
		for s, v in pairs(saved) do s.x, s.y, s.w, s.h, s.rot = v[1], v[2], v[3], v[4], v[5] end
		return false
	end
	h.grids = n.grids
	return true
end

-- A new hold for a changed layout. Grids whose key and size didn't change
-- come across untouched; the stacks from the rest are packed back in.
-- Returns the new hold and a { id = count } of whatever didn't fit.
function Hold.relayout(h, layout)
	local nh = Hold.new(layout)
	local old = {}
	for _, g in ipairs(h.grids) do old[g.key] = g end
	local moved = {}
	for i, g in ipairs(nh.grids) do
		local o = old[g.key]
		if o and o.w == g.w and o.h == g.h then
			nh.grids[i] = o
			old[g.key] = nil
		end
	end
	for _, o in pairs(old) do
		for _, s in ipairs(o.stacks) do
			-- (a loaded container that no longer fits anywhere is counted as
			-- an empty one in the overflow)
			if not (s.inner and Hold.placeStack(nh, s)) then moved[s.id] = (moved[s.id] or 0) + s.n end
		end
	end
	return nh, Hold.fill(nh, moved)
end

-- A single loosely packed grid for counts (a husk's wreckage). It starts
-- w x h and grows downward until everything is in, so nothing is lost.
-- stacks: ready-made stacks (loaded containers) to put in first.
function Hold.pack(counts, w, h, name, random, stacks)
	local ids = packingOrder(counts)
	for _, id in ipairs(ids) do
		local sw, sh = Shapes.of(id)
		w = math.max(w, min(sw, sh))         -- wide enough for everything, rotated if need be
	end
	for _, s in ipairs(stacks or {}) do
		local sw, sh = Shapes.of(s.id)
		w = math.max(w, min(sw, sh))
	end
	local hold = Hold.new({ { key = "main", name = name, w = w, h = h } })
	local g = hold.grids[1]
	for _, s in ipairs(stacks or {}) do
		local sw, sh = Shapes.of(s.id)
		while not Hold.placeStack(hold, s, random) do Grid.addRows(g, math.max(sw, sh)) end
	end
	for _, id in ipairs(ids) do
		local sw, sh = Shapes.of(id)
		local left = counts[id] - Hold.add(hold, id, counts[id], { random = random })
		while left > 0 do
			Grid.addRows(g, math.max(sw, sh))
			left = left - Hold.add(hold, id, left)
		end
	end
	return hold
end

-- Plain tables for a save file, and back. Stacks keep their places, and a
-- loaded container's own hold comes along, and so does a market shelf's
-- resale time (src/market.lua). On loading, stacks of items
-- that no longer exist (a mod was removed) are dropped; known tells
-- whether an id exists.
function Hold.serialize(h)
	local out = { grids = {} }
	for _, g in ipairs(h.grids) do
		local sg = { key = g.key, name = g.name, w = g.w, h = g.h, stacks = {} }
		for _, s in ipairs(g.stacks) do
			table.insert(sg.stacks, { id = s.id, n = s.n, x = s.x, y = s.y, w = s.w, h = s.h, rot = s.rot or nil,
				inner = s.inner and Hold.serialize(s.inner) or nil, resale = s.resale, wear = s.wear })
		end
		table.insert(out.grids, sg)
	end
	return out
end

function Hold.deserialize(t, known)
	local h = { grids = {} }
	for _, sg in ipairs(t.grids or {}) do
		local g = Grid.new(sg.w, sg.h, sg.name)
		g.key = sg.key
		for _, s in ipairs(sg.stacks or {}) do
			if (not known or known(s.id)) and Grid.isFree(g, s.x, s.y, s.w, s.h) then
				Grid.place(g, { id = s.id, n = s.n, x = s.x, y = s.y, w = s.w, h = s.h, rot = s.rot or false,
					inner = s.inner and Hold.deserialize(s.inner, known) or nil, resale = s.resale, wear = s.wear })
			end
		end
		table.insert(h.grids, g)
	end
	return h
end

return Hold
