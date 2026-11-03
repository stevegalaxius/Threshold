--[[
	Hull paint. Works like a car's: every hull leaves the yard in a factory
	preset, and anything else on it (a faction livery, a repaint) is a
	choice somebody made.

	A paint is { r, g, b, secondary = { r, g, b }, name = ... }: its first
	three entries are the primary, so anything that wants one colour for a
	ship (HUD, hangar, weapons) can keep reading [1], [2], [3].

	Parts pick what they wear with part.paint:
	  nil          bare metal (the default)
	  "primary"    the paint's primary
	  "secondary"  the paint's secondary
	part.color still fixes a colour that ignores the paint, and shade and
	tint still apply on top of whatever the part wears.
]]
local Paint = {}

Paint.METAL = { 0.56, 0.58, 0.62 }

-- Factory presets: one base colour each; the secondary is a shade of it.
Paint.PRESETS = {
	-- neutrals
	{ name = "Bone",       color = { 0.9, 0.88, 0.8 } },
	{ name = "Khaki",      color = { 0.76, 0.7, 0.55 } },
	{ name = "Ash",        color = { 0.62, 0.6, 0.57 } },
	{ name = "Taupe",      color = { 0.5, 0.43, 0.38 } },
	{ name = "Gunmetal",   color = { 0.27, 0.31, 0.38 } },
	{ name = "Charcoal",   color = { 0.17, 0.17, 0.18 } },
	-- earth
	{ name = "Umber",      color = { 0.38, 0.26, 0.16 } },
	{ name = "Primer",     color = { 0.55, 0.2, 0.16 } },
	{ name = "Terracotta", color = { 0.72, 0.4, 0.28 } },
	{ name = "Plum",       color = { 0.5, 0.22, 0.35 } },
	-- greens
	{ name = "Sage",       color = { 0.6, 0.68, 0.55 } },
	{ name = "Olive Drab", color = { 0.48, 0.5, 0.3 } },
	{ name = "Moss",       color = { 0.36, 0.5, 0.24 } },
	{ name = "Forest",     color = { 0.17, 0.34, 0.2 } },
	{ name = "Pine",       color = { 0.12, 0.3, 0.28 } },
	-- golds
	{ name = "Brass",      color = { 0.66, 0.54, 0.24 } },
	{ name = "Mustard",    color = { 0.85, 0.66, 0.18 } },
	{ name = "Signal",     color = { 1.0, 0.85, 0.35 } },
	-- blues and brights
	{ name = "Tanker",     color = { 0.18, 0.5, 0.52 } },
	{ name = "Cargo Blue", color = { 0.28, 0.36, 0.55 } },
	{ name = "Cobalt",     color = { 0.25, 0.45, 0.95 } },
	{ name = "Hazard",     color = { 1.0, 0.55, 0.1 } },
	{ name = "Orchid",     color = { 0.85, 0.55, 0.95 } },
}
Paint.DEFAULT = "Gunmetal"

local byName = {}
for _, p in ipairs(Paint.PRESETS) do byName[p.name] = p end
function Paint.find(name) return byName[name] end

-- A factory secondary: darker for a light base, lighter for a dark one.
function Paint.shadeOf(c)
	local lum = 0.3 * c[1] + 0.59 * c[2] + 0.11 * c[3]
	local k = lum > 0.45 and 0.62 or 1.45
	return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) }
end

-- A paint from a primary and (optionally) a free secondary.
function Paint.make(primary, secondary, name)
	local s = secondary or Paint.shadeOf(primary)
	return { primary[1], primary[2], primary[3], secondary = { s[1], s[2], s[3] }, name = name }
end

-- A factory preset by name (unknown or nil: the default).
function Paint.preset(name)
	local p = byName[name] or byName[Paint.DEFAULT]
	return Paint.make(p.color, nil, p.name)
end

-- A livery { primary = {r,g,b}, secondary = {r,g,b}? }.
function Paint.livery(l)
	return Paint.make(l.primary, l.secondary, l.name)
end

function Paint.isPaint(c) return type(c) == "table" and c.secondary ~= nil end

-- A hull's pool of factory paint jobs (hull.paints, a list of preset
-- names); the first is the one the editor and the hangar show.
function Paint.pool(hull)
	local pool = hull and hull.paints
	if type(pool) == "table" and #pool > 0 then return pool end
	return { Paint.DEFAULT }
end

-- What a ship spawns wearing: an explicit paint, else its faction livery,
-- else one of its hull's factory paint jobs, picked at random. Plain { r, g, b } colours from before
-- paint existed are ignored.
function Paint.resolve(explicit, enemy, hull)
	if Paint.isPaint(explicit) then return explicit end
	if enemy and enemy.livery then return Paint.livery(enemy.livery) end
	local pool = Paint.pool(hull)
	return Paint.preset(pool[love.math.random(#pool)])
end

return Paint
