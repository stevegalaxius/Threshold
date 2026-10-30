--[[
	One grid of hold cells. Cells are numbered from 0,0 at the top left;
	each holds a link to the stack covering it, or nothing.

	A stack is { id = item id, n = count, x, y, w, h, rot }: w and h are
	the footprint as placed, so a rotated stack has them swapped.

	Plain Lua with no LÖVE calls, so it can be tested on its own.
]]

local Grid = {}

function Grid.new(w, h, name)
	return { w = w, h = h, name = name, cells = {}, stacks = {} }
end

local function index(g, x, y)
	return y * g.w + x + 1
end

-- Is the w x h area at x, y inside the grid and clear (except for the
-- stack `ignore`, so a stack can be moved onto part of where it was)?
function Grid.isFree(g, x, y, w, h, ignore)
	if x < 0 or y < 0 or x + w > g.w or y + h > g.h then return false end
	for cy = y, y + h - 1 do
		for cx = x, x + w - 1 do
			local s = g.cells[index(g, cx, cy)]
			if s and s ~= ignore then return false end
		end
	end
	return true
end

local function mark(g, s, value)
	for cy = s.y, s.y + s.h - 1 do
		for cx = s.x, s.x + s.w - 1 do
			g.cells[index(g, cx, cy)] = value
		end
	end
end

-- Put a stack in at its x, y (the caller checked it's free).
function Grid.place(g, s)
	table.insert(g.stacks, s)
	mark(g, s, s)
	return s
end

function Grid.remove(g, s)
	for i, o in ipairs(g.stacks) do
		if o == s then
			table.remove(g.stacks, i)
			mark(g, s, nil)
			return true
		end
	end
	return false
end

-- The stack covering a cell, if any.
function Grid.at(g, x, y)
	if x < 0 or y < 0 or x >= g.w or y >= g.h then return nil end
	return g.cells[index(g, x, y)]
end

-- First free spot for a w x h footprint, scanning rows top to bottom and
-- each row left to right. Returns x, y or nil.
function Grid.firstFit(g, w, h)
	for y = 0, g.h - h do
		for x = 0, g.w - w do
			if Grid.isFree(g, x, y, w, h) then return x, y end
		end
	end
	return nil
end

function Grid.cellsUsed(g)
	local n = 0
	for _, s in ipairs(g.stacks) do n = n + s.w * s.h end
	return n
end

-- Grow the grid by some rows at the bottom (husks do this so nothing they
-- carried is ever lost).
function Grid.addRows(g, rows)
	g.h = g.h + rows       -- cells are indexed by row, so nothing moves
end

return Grid
