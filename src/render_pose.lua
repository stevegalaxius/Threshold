-- Draw between the last two physics poses without changing Box2D bodies.
local Pose = {}
local tick, frame = 0, 0

function Pose.beginFrame()
	frame = frame + 1
end

function Pose.remember(game)
	tick = tick + 1
	for _, e in ipairs(game.entities) do
		local body = e.body
		if body and not body:isDestroyed() and body:getType() ~= "static" then
			e.previousX, e.previousY = body:getPosition()
			e.previousAngle = body:getAngle()
			e.previousBody, e.previousTick = body, tick
		end
	end
end

function Pose.interpolate(game, alpha)
	for _, e in ipairs(game.entities) do
		local body = e.body
		if e.previousTick == tick and body == e.previousBody and not body:isDestroyed() then
			local x, y = body:getPosition()
			local angle = body:getAngle()
			local delta = (angle - e.previousAngle + math.pi) % (2 * math.pi) - math.pi
			e.drawX = e.previousX + (x - e.previousX) * alpha
			e.drawY = e.previousY + (y - e.previousY) * alpha
			e.drawAngle = angle - delta * (1 - alpha)
			e.drawFrame = frame
		end
	end
end

local function interpolated(e)
	return e.drawFrame == frame and e.body == e.previousBody
end

function Pose.position(e)
	if interpolated(e) then return e.drawX, e.drawY end
	return e.body:getPosition()
end

function Pose.angle(e)
	if interpolated(e) then return e.drawAngle end
	return e.body:getAngle()
end

function Pose.point(e, x, y)
	if not interpolated(e) then return e.body:getWorldPoint(x, y) end
	local c, s = math.cos(e.drawAngle), math.sin(e.drawAngle)
	return e.drawX + c * x - s * y, e.drawY + s * x + c * y
end

return Pose
