-- F8 records a short frame timing trace and Lua sampling profile.
local S = {}

-- Asked for from a key press. For the next two seconds LuaJIT's sampling
-- profiler records where the time goes (the "hot:" line, by source line,
-- percent of samples); the snapshot is then taken at the end of a draw so
-- the draw-call numbers are that frame's, not an empty one's.
local PROFILE_SECONDS = 2
function S.snap(game)
	if S.profiling then return end
	local ok, prof = pcall(require, "jit.profile")
	S.samples, S.total = {}, 0
	S.frames = {}
	S.previous = nil
	game:toast("Sampling frame times for 2 seconds", 2)
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

-- Match each update and draw with the start of the following update so
-- present, frame pacing, and event handling are included in the interval.
function S.updated(start)
	local previous = S.previous
	if previous and previous.draw then
		previous.frame = (start - previous.start) * 1000
		S.frames[#S.frames + 1] = previous
	end
	S.previous = { start = start, update = (love.timer.getTime() - start) * 1000 }
end

function S.presented(start)
	if S.previous then S.previous.present = (love.timer.getTime() - start) * 1000 end
end

function S.afterDraw(game, start)
	local now = love.timer.getTime()
	if S.previous then S.previous.draw = (now - start) * 1000 end
	if now - S.profiling < PROFILE_SECONDS then return end
	S.profiling = nil
	if S.prof then S.prof.stop(); S.prof = nil end
	local st = love.graphics.getStats()
	local w = game.world
	local kinds = {}
	for _, e in ipairs(game.entities) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
	local ks = {}
	for k, v in pairs(kinds) do ks[#ks + 1] = k .. "=" .. v end
	table.sort(ks)
	local renderer, version, vendor, device = love.graphics.getRendererInfo()
	local line = ("[t=%.0f] fps=%d frameMs=%.2f luaKB=%.0f draws=%d bodies=%d contacts=%d %s\n  renderer: %s %s / %s / %s  vsync=%s\n"):format(
		game.time or 0, love.timer.getFPS(), love.timer.getAverageDelta() * 1000, collectgarbage("count"),
		st.drawcalls, w:getBodyCount(), w:getContactCount(), table.concat(ks, " "),
		renderer, version, vendor, device, tostring(love.window.getVSync()))
	line = line .. ("  field=%s sleepers=%d entities=%d canvases=%d images=%d texMB=%.1f f7=%s\n"):format(
		game.fieldId or "?", #(game.sleepers or {}), #game.entities, st.canvases, st.images,
		st.texturememory / 2 ^ 20, tostring(require("src.profiler").on))
	local trace = { line, "frame_ms,update_ms,draw_ms,present_ms,other_ms" }
	local intervals = {}
	for i, f in ipairs(S.frames) do
		intervals[i] = f.frame
		trace[#trace + 1] = ("%.3f,%.3f,%.3f,%.3f,%.3f"):format(
			f.frame, f.update, f.draw, f.present or 0, f.frame - f.update - f.draw - (f.present or 0))
	end
	table.sort(intervals)
	if #intervals > 0 then
		line = line .. ("  frame ms: median=%.2f p95=%.2f p99=%.2f worst=%.2f frames=%d\n"):format(
			intervals[math.ceil(#intervals / 2)], intervals[math.ceil(#intervals * .95)],
			intervals[math.ceil(#intervals * .99)], intervals[#intervals], #intervals)
	end
	line = line .. "  hot: " .. hot() .. "\n"
	local saved, dumpError = love.filesystem.write(("perf_dump_%d.txt"):format(os.time()), table.concat(trace, "\n"))
	local logged, logError = love.filesystem.append("perf_log.txt", line)
	if saved and logged then
		game:toast("Frame trace and perf log saved", 2)
	else
		game:toast("Perf export failed: " .. tostring(dumpError or logError), 5)
	end
	S.previous, S.frames, S.samples = nil, nil, nil
end

return S
