--[[
	Title intro: THRESHOLD in plain sans, then a quick dive into the second
	H while the view turns a quarter so its crossbar stands upright and
	fills the screen. The slow start-up (data, universe, save) runs while the
	screen is that solid crossbar, then the crossbar splits down the middle
	and slides apart like airlock doors onto the game.
]]
local Intro = {}

local WORD, SIZE = "THRESHOLD", 160
local ZOOM, DOORS = .45, .35
local INK = { .86, .9, 1 }
local SKY = { .02, .03, .06 }

local state, t, loader
local canvas, cx, cy, bar   -- the word, the crossbar's centre and thickness in it

-- Finds the second H's crossbar by reading the rendered word back.
local function prepare()
	local font = love.graphics.newFont(SIZE)
	local w, h = font:getWidth(WORD) + 8, font:getHeight() + 8
	canvas = love.graphics.newCanvas(w, h)
	canvas:setFilter("linear", "linear")
	love.graphics.push("all")
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setFont(font)
	love.graphics.setColor(1, 1, 1)
	love.graphics.print(WORD, 4, 4)
	love.graphics.pop()
	local i = WORD:find("H", WORD:find("H") + 1)
	local x0 = 4 + font:getWidth(WORD:sub(1, i - 1))
	cx = math.floor(x0 + font:getWidth("H") / 2)
	local img = canvas:newImageData()
	-- longest filled run in that column near the middle is the crossbar
	local best, run, start, mid = nil, 0, 0, h / 2
	for y = 0, h - 1 do
		local _, _, _, a = img:getPixel(cx, y)
		if a > .5 then
			if run == 0 then start = y end
			run = run + 1
		elseif run > 0 then
			local c = start + run / 2
			if not best or math.abs(c - mid) < math.abs(best[1] - mid) then best = { c, run } end
			run = 0
		end
	end
	cy, bar = best and best[1] or mid, best and best[2] or SIZE * .08
	img:release()
end

function Intro.start(load)
	state, t, loader = "zoom", 0, load
	prepare()
end

-- true while the intro owns the screen and input (the game isn't up yet).
function Intro.blocking() return state == "zoom" or state == "load" end

function Intro.update(dt)
	if not state then return end
	t = t + dt
	if state == "zoom" and t >= ZOOM then state, t = "load", 0
	elseif state == "load" and t > 0 then
		-- the solid frame has been shown: do the slow work behind it
		loader()
		state, t = "doors", 0
	elseif state == "doors" and t >= DOORS then
		state = nil
		canvas:release(); canvas = nil
	end
end

function Intro.draw()
	if not state then return end
	local w, h = love.graphics.getDimensions()
	if state == "doors" then
		local p = math.min(1, t / DOORS)
		local o = (p * p * (3 - 2 * p)) * w / 2   -- smoothstep slide
		love.graphics.setColor(INK)
		love.graphics.rectangle("fill", -o, 0, w / 2, h)
		love.graphics.rectangle("fill", w / 2 + o, 0, w / 2, h)
		love.graphics.setColor(SKY[1], SKY[2], SKY[3], .6)
		love.graphics.rectangle("fill", w / 2 - o - 1, 0, 1, h)
		love.graphics.rectangle("fill", w / 2 + o, 0, 1, h)
		love.graphics.setColor(1, 1, 1)
		return
	end
	love.graphics.clear(SKY)
	if state == "load" then
		love.graphics.clear(INK)
		return
	end
	local p = math.min(1, t / ZOOM)
	local e = p * p * (3 - 2 * p)
	local fit = w * .8 / canvas:getWidth()
	local final = w * 1.15 / bar                 -- crossbar wider than the screen
	local scale = fit * (final / fit) ^ (p ^ 1.6)
	local fx = canvas:getWidth() / 2 + (cx - canvas:getWidth() / 2) * math.min(1, e * 1.6)
	local fy = canvas:getHeight() / 2 + (cy - canvas:getHeight() / 2) * math.min(1, e * 1.6)
	love.graphics.push()
	love.graphics.translate(w / 2, h / 2)
	love.graphics.rotate(-math.pi / 2 * e)
	love.graphics.scale(scale)
	love.graphics.setColor(INK)
	love.graphics.draw(canvas, -fx, -fy)
	love.graphics.pop()
	love.graphics.setColor(1, 1, 1)
end

return Intro
