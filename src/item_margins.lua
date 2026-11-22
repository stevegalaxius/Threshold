-- The price rule for one item (src/economy_model.lua, T.priceMargin): every
-- recipe should sell at no less than its inputs at list price x margin.
-- Margins.check(item, price) looks at the recipes that make the item and the
-- recipes that use it, with the item priced at price (the Shipyard's edit),
-- and returns a list of { recipe, output, price, need, ok }.
local M = {}

local function perUnit(c)
	local C = require("src.commodities")
	local t = c.time or 1
	local outs, ins = {}, {}
	for _, o in ipairs(C.outputs(c)) do if o.item then outs[o.item] = (outs[o.item] or 0) + (o.n or 1) / t end end
	for _, i in ipairs(C.inputs(c)) do ins[i.item] = (ins[i.item] or 0) + i.n / t end
	return outs, ins
end

function M.check(item, price)
	local data = require("src.data")
	local C = require("src.commodities")
	local margin = require("src.tuning").priceMargin or 1.35
	local function priceOf(id)
		if id == item then return price end
		return (data.items[id] or {}).price or 0
	end
	local rows = {}
	for _, c in ipairs(C.list) do
		if not c.stockless then
			local outs, ins = perUnit(c)
			if next(ins) and (outs[item] or ins[item]) then
				for out, n in pairs(outs) do
					if out == item or ins[item] then
						local cost = 0
						for input, k in pairs(ins) do cost = cost + k / n * priceOf(input) end
						local p = priceOf(out)
						table.insert(rows, { recipe = c.id, output = out, makes = out == item, price = p, need = cost * margin, ok = p <= 0 or cost * margin <= p * 1.001 })
					end
				end
			end
		end
	end
	table.sort(rows, function(a, b) if a.makes ~= b.makes then return a.makes end return a.recipe < b.recipe end)
	return rows, margin
end

return M
