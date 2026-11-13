-- Frame-time profiler: F7 toggles. While on, every Game method and the
-- main draw/update modules are timed (inclusive: a method's time counts
-- what it calls too), and the slowest are listed on screen as ms per frame,
-- averaged over the last second. Off, nothing is wrapped and it costs nothing.
local P = { on = false, acc = {}, calls = {}, shown = {}, frames = 0, since = 0 }
local wrapped = {}
local clock = love.timer.getTime

local function done(label, t, ...)
	P.acc[label] = (P.acc[label] or 0) + clock() - t
	P.calls[label] = (P.calls[label] or 0) + 1
	return ...
end

local function wrap(tbl, name, label)
	local f = tbl[name]
	if type(f) ~= "function" or wrapped[tostring(tbl)] and wrapped[tostring(tbl)][name] then return end
	wrapped[tostring(tbl)] = wrapped[tostring(tbl)] or {}
	wrapped[tostring(tbl)][name] = { tbl = tbl, f = f }
	tbl[name] = function(...)
		local t = clock()
		return done(label, t, f(...))
	end
end

local MODULES = { "src.render", "src.hud", "src.ui.cargo", "src.ai", "src.alife", "src.encounters",
	"src.security", "src.population", "src.economy", "src.arbiter", "src.jobs", "src.tasks",
	"src.travelgraph", "src.weapons", "src.ship", "src.mining", "src.piracy", "src.reputation",
	"src.local_navigation", "src.queue", "src.npc_scheduler", "src.locations", "src.security", "src.fields" }

function P.toggle(Game)
	P.on = not P.on
	if P.on then
		for k in pairs(P.acc) do P.acc[k] = nil end
		for k in pairs(P.calls) do P.calls[k] = nil end
		P.frames, P.since, P.shown = 0, clock(), {}
		wrap(love.graphics, "present", "present (vsync wait)")
		for name in pairs(Game) do wrap(Game, name, "Game:" .. name) end
		for _, m in ipairs(MODULES) do
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" then
				local short = m:gsub("^src%.", "")
				for name in pairs(mod) do wrap(mod, name, short .. "." .. name) end
			end
		end
	else
		for _, names in pairs(wrapped) do
			for name, w in pairs(names) do w.tbl[name] = w.f end
		end
		wrapped = {}
	end
end

-- Call once per frame (from love.draw).
function P.frame()
	if not P.on then return end
	P.frames = P.frames + 1
	local now = clock()
	if now - P.since >= 1 then
		local list = {}
		for k, v in pairs(P.acc) do
			list[#list + 1] = { name = k, ms = v * 1000 / P.frames, n = P.calls[k] / P.frames }
			P.acc[k], P.calls[k] = nil, nil
		end
		table.sort(list, function(a, b) return a.ms > b.ms end)
		P.shown, P.fps = list, P.frames / (now - P.since)
		P.frames, P.since = 0, now
	end
end

function P.draw()
	if not P.on then return end
	local lg = love.graphics
	lg.setFont(require("src.hud").font(12))
	local n = math.min(24, #P.shown)
	lg.setColor(0, 0, 0, 0.75)
	lg.rectangle("fill", 8, 8, 560, 30 + n * 15)
	lg.setColor(1, 1, 1)
	-- With vsync on, the frame rate can't pass the display's refresh rate, and
	-- the wait for it lands in whatever touches the GPU first next frame
	-- (usually render.world), not only in present: so show what we're synced to.
	local _, _, mode = love.window.getMode()
	local sync = (mode.vsync or 0) ~= 0 and ("vsync on, display %dHz"):format(mode.refreshrate or 0) or "vsync off"
	lg.print(("PROFILER  %.0f fps  %s  (ms/frame, inclusive, calls/frame)"):format(P.fps or 0, sync), 14, 12)
	for i = 1, n do
		local r = P.shown[i]
		lg.print(("%6.2f  %6.1f  %s"):format(r.ms, r.n, r.name), 14, 14 + i * 15)
	end
end

return P
