--[[
	Item shapes for the grid hold. One cell is one cubic metre, so an
	item's footprint (w x h cells) and how many fit in one stack follow
	from its volume.

	An item can set its shape in data/ with w, h and stack. Anything that
	doesn't (a modded item, say) gets one worked out from its volume:
	small things share a single cell, bigger things get a footprint that
	holds one of them.
]]

local data = require("src.data")

local Shapes = {}

local ceil, floor, max, sqrt = math.ceil, math.floor, math.max, math.sqrt
local EPS = 1e-6

-- The shape a volume gets when the data doesn't give one.
local function fromVolume(volume)
	if volume <= 1 + EPS then
		return 1, 1, max(1, floor(1 / volume + EPS))
	end
	local area = ceil(volume - EPS)
	if area <= 3 then return area, 1, 1 end
	local s = ceil(sqrt(area))
	return s, ceil(area / s), 1
end
Shapes.fromVolume = fromVolume

local cache = {}

-- w, h, stack for an item id.
function Shapes.of(id)
	local c = cache[id]
	if c then return c[1], c[2], c[3] end
	local item = assert(data.items[id], "unknown item " .. tostring(id))
	local w, h, stack
	if item.w and item.h then
		w, h, stack = item.w, item.h, item.stack or 1
	elseif item.kind == "crate" then
		-- A crate is a 2 x 2 box of the rounds; ammo too big for that is
		-- crated one at a time in its own shape.
		local ammo = data.items[item.ammo]
		if ammo.volume <= 4 + EPS then
			w, h, stack = 2, 2, max(1, floor(4 / ammo.volume + EPS))
		else
			w, h = Shapes.of(item.ammo)
			stack = 1
		end
	else
		w, h, stack = fromVolume(item.volume)
	end
	cache[id] = { w, h, stack }
	return w, h, stack
end

-- Forget cached shapes (after data is reloaded).
function Shapes.reset()
	cache = {}
end

-- Grid size for a hold of n cubic metres: the narrowest width at or above
-- the square root that divides n exactly (24 -> 6 x 4, 120 -> 12 x 10),
-- or a near-square that rounds up when nothing divides it nicely.
function Shapes.gridFor(n)
	n = max(1, floor(n + 0.5))
	local root = sqrt(n)
	for w = ceil(root - EPS), floor(root * 2) do
		if n % w == 0 then return w, n / w end
	end
	local w = ceil(root - EPS)
	return w, ceil(n / w)
end

return Shapes
