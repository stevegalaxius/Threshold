-- Follow camera with zoom, a lead toward where you're aiming, and screenshake.

local T = require("src.tuning")

local Camera = {}
Camera.__index = Camera

function Camera.new()
	return setmetatable({ x = 0, y = 0, zoom = 0.7, trauma = 0, ox = 0, oy = 0 }, Camera)
end

function Camera:follow(tx, ty, aimX, aimY, dt)
	local gx = tx + (aimX - tx) * T.camLead
	local gy = ty + (aimY - ty) * T.camLead
	local k = 1 - math.exp(-dt * 8)
	self.x = self.x + (gx - self.x) * k
	self.y = self.y + (gy - self.y) * k

	self.trauma = math.max(0, self.trauma - dt * 1.6)
	local s = self.trauma * self.trauma * 14 * T.shake
	self.ox = (love.math.random() * 2 - 1) * s
	self.oy = (love.math.random() * 2 - 1) * s
end

function Camera:shake(amount)
	self.trauma = math.min(1, self.trauma + amount)
end

function Camera:apply()
	local w, h = love.graphics.getDimensions()
	love.graphics.push()
	love.graphics.translate(math.floor(w / 2 + self.ox), math.floor(h / 2 + self.oy))
	love.graphics.scale(self.zoom)
	love.graphics.translate(-self.x, -self.y)
end

function Camera:release()
	love.graphics.pop()
end

function Camera:toWorld(sx, sy)
	local w, h = love.graphics.getDimensions()
	return (sx - w / 2) / self.zoom + self.x, (sy - h / 2) / self.zoom + self.y
end

function Camera:toScreen(wx, wy)
	local w, h = love.graphics.getDimensions()
	return (wx - self.x) * self.zoom + w / 2, (wy - self.y) * self.zoom + h / 2
end

function Camera:zoomBy(f)
	self.zoom = math.max(0.3, math.min(1.6, self.zoom * f))
end

return Camera
