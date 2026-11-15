--[[
	F8: append one line of live counters to perf_log.txt in the save folder
	(FPS, Lua memory, draw calls, textures, Box2D bodies/contacts, entities
	by kind, and the biggest tables hanging off the game). Press it once
	when the game runs well and once when it's slow, then compare.
]]
local S = {}

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function sizes(root, prefix, out, depth, seen)
	if depth > 2 or seen[root] then return end
	seen[root] = true
	for k, v in pairs(root) do
		if type(v) == "table" and type(k) == "string" then
			local n = count(v)
			out[#out + 1] = { prefix .. k, n }
			if n < 5000 then sizes(v, prefix .. k .. ".", out, depth + 1, seen) end
		end
	end
end

-- Asked for from a key press; taken at the end of the next draw so the
-- draw-call numbers are that frame's, not an empty one's.
function S.snap() S.pending = true end

function S.afterDraw(game)
	if not S.pending or not game then return end
	S.pending = nil
	local st = love.graphics.getStats()
	local w = game.world
	local kinds = {}
	for _, e in ipairs(game.entities or {}) do kinds[e.kind or "?"] = (kinds[e.kind or "?"] or 0) + 1 end
	local ks = {}
	for k, v in pairs(kinds) do ks[#ks + 1] = k .. "=" .. v end
	table.sort(ks)
	local big = {}
	sizes(game, "", big, 0, {})
	table.sort(big, function(a, b) return a[2] > b[2] end)
	local top = {}
	for i = 1, math.min(15, #big) do top[i] = big[i][1] .. "=" .. big[i][2] end
	local line = ("[t=%.0f] fps=%d frameMs=%.2f luaKB=%.0f draws=%d canvases=%d images=%d texMB=%.1f bodies=%d contacts=%d entities=%d %s\n  big: %s\n"):format(
		game.time or 0, love.timer.getFPS(), love.timer.getAverageDelta() * 1000, collectgarbage("count"),
		st.drawcalls, st.canvases, st.images, st.texturememory / 2 ^ 20,
		w and w:getBodyCount() or -1, w and w:getContactCount() or -1, #(game.entities or {}),
		table.concat(ks, " "), table.concat(top, " "))
	print(line)
	love.filesystem.append("perf_log.txt", line)
	pcall(game.toast, game, "perf snapshot saved to perf_log.txt", 2)
end

return S
