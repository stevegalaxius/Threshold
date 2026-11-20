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

-- Asked for from a key press. For the next two seconds LuaJIT's sampling
-- profiler records where the time goes (the "hot:" line, by source line,
-- percent of samples); the snapshot is then taken at the end of a draw so
-- the draw-call numbers are that frame's, not an empty one's.
local PROFILE_SECONDS = 2
function S.snap()
	if S.profiling then return end
	local ok, prof = pcall(require, "jit.profile")
	S.samples, S.total = {}, 0
	if ok then
		prof.start("li1", function(thread, n)
			local key = prof.dumpstack(thread, "pl", 1)
			S.samples[key] = (S.samples[key] or 0) + n
			S.total = S.total + n
		end)
		S.prof = prof
	end
	S.profiling = love.timer.getTime()
end

local function hot()
	local list = {}
	for k, n in pairs(S.samples or {}) do list[#list + 1] = { k, n } end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(20, #list) do
		out[i] = ("%s %.0f%%"):format(list[i][1], list[i][2] * 100 / math.max(1, S.total))
	end
	return table.concat(out, "  ")
end

function S.afterDraw(game)
	if not S.profiling or not game then return end
	if love.timer.getTime() - S.profiling < PROFILE_SECONDS then return end
	S.profiling = nil
	if S.prof then S.prof.stop(); S.prof = nil end
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
	local line = ("[t=%.0f] fps=%d frameMs=%.2f luaKB=%.0f draws=%d canvases=%d images=%d texMB=%.1f bodies=%d contacts=%d entities=%d %s\n  big: %s\n  hot: %s\n"):format(
		game.time or 0, love.timer.getFPS(), love.timer.getAverageDelta() * 1000, collectgarbage("count"),
		st.drawcalls, st.canvases, st.images, st.texturememory / 2 ^ 20,
		w and w:getBodyCount() or -1, w and w:getContactCount() or -1, #(game.entities or {}),
		table.concat(ks, " "), table.concat(top, " "), hot())
	print(line)
	S.dump(game)
	love.filesystem.append("perf_log.txt", line)
	pcall(game.toast, game, "perf snapshot + state dump saved", 2)
end

-- A flat dump of the live game state (path = value or table size), so a
-- dump taken while something is broken can be diffed against one taken
-- right after F9 reloads the same save: whatever differs is runtime-only
-- state that the save drops.
function S.dump(game)
	local out, seen = {}, {}
	local function walk(t, path, depth)
		if seen[t] then return end
		seen[t] = true
		local keys = {}
		for k in pairs(t) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for i, k in ipairs(keys) do
			if i > 100 or #out > 200000 then out[#out + 1] = path .. ".… " .. (#keys - i + 1) .. " more"; break end
			local v, p = t[k], path .. "." .. tostring(k)
			local tv = type(v)
			if tv == "table" then
				out[#out + 1] = ("%s = {%d}"):format(p, count(v))
				if depth < 3 then walk(v, p, depth + 1) end
			elseif tv == "number" or tv == "boolean" then out[#out + 1] = p .. " = " .. tostring(v)
			elseif tv == "string" then out[#out + 1] = p .. " = " .. v:sub(1, 60)
			elseif tv == "userdata" then
				local ok, ty = pcall(function() return v:type() end)
				out[#out + 1] = p .. " = <" .. (ok and tostring(ty) or "userdata") .. ">"
			end
		end
	end
	walk(game, "game", 0)
	local name = ("perf_dump_%d.txt"):format(os.time())
	love.filesystem.write(name, table.concat(out, "\n"))
	print("[perfsnap] wrote " .. name)
end

return S
