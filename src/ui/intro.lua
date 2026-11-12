--[[
	Title intro: THRESHOLD in blocky letters, then the camera dives into the
	middle of the H's crossbar until the screen is solid letter colour. The
	slow part of starting up (data, the universe, the save) runs on that
	solid frame, so the hitch is hidden, and then the colour fades away to
	reveal the game.
]]
local Intro = {}

-- 5x7 glyphs; '#' is a filled cell.
local GLYPHS = {
	T = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." },
	H = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	R = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
	E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
	S = { ".####", "#....", "#....", ".###.", "....#", "....#", "####." },
	O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
	L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
	D = { "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####." },
}
local WORD, ADVANCE = "THRESHOLD", 6          -- 5 cells of letter + 1 gap
local WIDTH = #WORD * ADVANCE - 1
-- Centre of the H's crossbar, in cells: H is the 2nd letter, row 3.
local TARGET_X, TARGET_Y = ADVANCE + 2.5, 3.5

local HOLD, ZOOM, REVEAL = .7, 1.5, .6
local ZOOM_RANGE = 400                        -- final scale vs the title's
local INK = { .86, .9, 1 }
local SKY = { .02, .03, .06 }

local state, t, loader, stars

function Intro.start(load)
	state, t, loader = "hold", 0, load
	stars = {}
	local rng = love.math.newRandomGenerator(7)
	for i = 1, 160 do stars[i] = { rng:random(), rng:random(), rng:random() * .6 + .2 } end
end

-- true while the intro owns the screen and input (the game isn't up yet).
function Intro.blocking() return state == "hold" or state == "zoom" or state == "load" end
function Intro.revealing() return state == "reveal" end

function Intro.update(dt)
	if not state then return end
	t = t + dt
	if state == "hold" and t >= HOLD then state, t = "zoom", 0
	elseif state == "zoom" and t >= ZOOM then state, t = "load", 0
	elseif state == "load" and t > 0 then
		-- the solid frame has been shown at least once: do the slow work now
		loader()
		state, t = "reveal", 0
	elseif state == "reveal" and t >= REVEAL then state = nil end
end

local function drawTitle(progress)
	local w, h = love.graphics.getDimensions()
	local base = math.floor(math.min(w * .7 / WIDTH, h * .25 / 7))
	-- Exponential zoom eases in: slow start, rushing at the end.
	local e = progress * progress
	local scale = base * ZOOM_RANGE ^ e
	-- Slide the focus from the word's centre to the H's crossbar.
	local fx = WIDTH / 2 + (TARGET_X - WIDTH / 2) * math.min(1, progress * 3)
	local fy = 3.5
	love.graphics.push()
	love.graphics.translate(w / 2, h / 2)
	love.graphics.scale(scale)
	love.graphics.translate(-fx, -fy)
	love.graphics.setColor(INK)
	for i = 1, #WORD do
		local g = GLYPHS[WORD:sub(i, i)]
		local ox = (i - 1) * ADVANCE
		for row = 1, 7 do
			local line = g[row]
			for col = 1, 5 do
				if line:sub(col, col) == "#" then
					love.graphics.rectangle("fill", ox + col - 1, row - 1, 1, 1)
				end
			end
		end
	end
	love.graphics.pop()
end

function Intro.draw()
	if not state then return end
	local w, h = love.graphics.getDimensions()
	if state == "reveal" then
		local a = 1 - t / REVEAL
		love.graphics.setColor(INK[1], INK[2], INK[3], a * a)
		love.graphics.rectangle("fill", 0, 0, w, h)
		love.graphics.setColor(1, 1, 1)
		return
	end
	love.graphics.clear(SKY)
	local progress = state == "zoom" and t / ZOOM or state == "load" and 1 or 0
	local starFade = 1 - progress
	for _, s in ipairs(stars) do
		love.graphics.setColor(1, 1, 1, s[3] * starFade)
		love.graphics.rectangle("fill", math.floor(s[1] * w), math.floor(s[2] * h), 1, 1)
	end
	if state == "load" then
		love.graphics.clear(INK)
	else
		drawTitle(progress)
	end
	love.graphics.setColor(1, 1, 1)
end

return Intro
