-- F8 records a short frame timing trace and Lua sampling profile.
local S = {}
local sections = { "ships_and_station_guns", "sleepers", "alife", "navigation_and_world",
	"box2d", "exhaust", "contacts_and_cleanup", "side_scenes", "flight", "remainder" }

local header = table.concat({
	"alife_stage: 0=none 1=mining 2=population 3=board 4=economy/quests/news 5=NPC synchronization 6=encounters/squads/wildcats 7=history",
	"frame_ms,update_ms,draw_ms,present_ms,other_ms,raw_dt_ms,loop_accumulator_ms,step_count,step_total_ms,update_outside_steps_ms,step_times_ms,"
		.. table.concat(sections, "_ms,") .. "_ms,npc_sweep_ms,economy_pump_ms,station_maintenance_ms,alife_stage"
}, "\n") .. "\n"

local function sceneSummary(game)
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
	return line
end

function S.snap(game, extended)
	if S.profiling then return end
	S.filename = ("perf_dump_%d.txt"):format(os.time())
	local saved, err = love.filesystem.write(S.filename, sceneSummary(game) .. header)
	if not saved then game:toast("Perf export failed: " .. tostring(err), 5); return end
	S.samples, S.total = {}, 0
	S.rows, S.intervals = {}, {}
	S.flushAt = love.timer.getTime() + 0.25
	S.previous = nil
	S.seconds = extended and 15 or 2
	game:toast(("Sampling frame times for %d seconds"):format(S.seconds), 2)
	local ok, prof
	if not extended then ok, prof = pcall(require, "jit.profile") end
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

local function frameRow(f)
	local durations, total = {}, 0
	for j, sample in ipairs(f.steps) do
		local elapsed = sample.total
		durations[j] = ("%.3f"):format(elapsed)
		total = total + elapsed
	end
	local columns = {}
	for _, section in ipairs(sections) do
		local values = {}
		for j, sample in ipairs(f.steps) do
			local elapsed = sample[section] or 0
			if section == "remainder" then
				elapsed = sample.total - ((sample.last or sample.start) - sample.start) * 1000
			end
			values[j] = ("%.3f"):format(elapsed)
		end
		columns[#columns + 1] = table.concat(values, " ")
	end
	-- These are nested within alife_ms. The stage identifies the work
	-- remaining after the sweep, economy and station maintenance.
	for _, field in ipairs({"npc_sweep","economy_pump","station_maintenance","alife_stage"}) do
		local values = {}
		for j, sample in ipairs(f.steps) do
			values[j] = (field == "alife_stage" and "%d" or "%.3f"):format(sample[field] or 0)
		end
		columns[#columns + 1] = table.concat(values, " ")
	end
	return ("%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%d,%.3f,%.3f,%s"):format(
		f.frame, f.update, f.draw, f.present or 0, f.frame - f.update - f.draw - (f.present or 0),
		f.rawDelta, f.accumulator and ("%.3f"):format(f.accumulator) or "", #durations, total,
		f.update - total, table.concat(durations, " ")) .. "," .. table.concat(columns, ",")
end

local function flush()
	if #S.rows == 0 then return true end
	local ok, err = love.filesystem.append(S.filename, table.concat(S.rows, "\n") .. "\n")
	if ok then S.rows = {} end
	return ok, err
end

-- Match each update and draw with the start of the following update so
-- present, frame pacing, and event handling are included in the interval.
function S.beginUpdate(dt)
	local start = love.timer.getTime()
	local previous = S.previous
	if previous and previous.draw then
		previous.frame = (start - previous.start) * 1000
		S.intervals[#S.intervals + 1] = previous.frame
		S.rows[#S.rows + 1] = frameRow(previous)
		if #S.rows >= 64 or start >= S.flushAt then
			local ok, err = flush()
			if not ok then S.writeError = err or "trace write failed" end
			S.flushAt = start + 0.25
		end
	end
	S.previous = { start = start, rawDelta = dt * 1000, steps = {} }
	return S.previous
end

function S.presented(start)
	if S.previous then S.previous.present = (love.timer.getTime() - start) * 1000 end
end

function S.afterDraw(game, start)
	local now = love.timer.getTime()
	if S.previous then S.previous.draw = (now - start) * 1000 end
	if not S.writeError and now - S.profiling < S.seconds then return end
	S.profiling = nil
	if S.prof then S.prof.stop(); S.prof = nil end
	local line = sceneSummary(game)
	local intervals = S.intervals
	table.sort(intervals)
	if #intervals > 0 then
		line = line .. ("  frame ms: median=%.2f p95=%.2f p99=%.2f worst=%.2f frames=%d\n"):format(
			intervals[math.ceil(#intervals / 2)], intervals[math.ceil(#intervals * .95)],
			intervals[math.ceil(#intervals * .99)], intervals[#intervals], #intervals)
	end
	line = line .. "  trace: " .. S.filename .. "\n"
	if S.total > 0 then line = line .. "  hot: " .. hot() .. "\n" end
	local saved, dumpError
	if S.writeError then dumpError = S.writeError else saved, dumpError = flush() end
	local logged, logError = love.filesystem.append("perf_log.txt", line)
	if saved and logged then
		game:toast("Frame trace and perf log saved", 2)
	else
		game:toast("Perf export failed: " .. tostring(dumpError or logError), 5)
	end
	S.previous, S.rows, S.intervals, S.samples, S.writeError = nil, nil, nil, nil, nil
end

return S
