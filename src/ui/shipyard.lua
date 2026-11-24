-- Manufacturing catalogue and stock-fit preview for civilian shipyards.
local data = require("src.data")
local HUD = require("src.hud")
local Paint = require("src.paint")
local Station = require("src.ui.station")
local Sheet = require("src.ui.shipsheet")
local Hangar = require("src.ui.hangar")

local Dealers = require("src.dealers")

local Yard = {sel=nil,scroll=0,paintByHull={}}

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min
local GAP, PAD = 16, 14
local LIST_W, ROW_H, LEFT_W = 300, 64, 360

local function inRect(r, x, y)
	return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function station(game)
	local p = game.player
	return p and p.dockState and p.dockState.station
end

function Yard.layout(game)
	local st = station(game)
	if not st then return nil end
	local state,def=Dealers.state(game.universe,st)
 if not def or not def.assembly or def.service then return end
 local stock={}
 for i,id in ipairs(def.hulls) do
  local hull=data.hulls[id]
  local order=state.playerOrder
  local reserved=order and order.hull==id and order
  local built=reserved and reserved.lot and Dealers.find(game.universe,st,reserved.lot)
  local paint=reserved and (reserved.paint or built and built.paint or Paint.pool(hull)[1])
   or Yard.paintByHull[id]
  stock[i]={id=id,hull=id,loadout=hull.loadout,paint=paint or Paint.pool(hull)[1],trimName='Stock',
   price=Dealers.price(hull,hull.loadout,def.markup)}
 end
 local valid=false
 for _,entry in ipairs(stock) do if entry.id==Yard.sel then valid=true;break end end
 if not valid then Yard.sel=stock[1] and stock[1].id end
	local sw, sh = lg.getDimensions()
	local x, y, tw, ph = require("src.ui.station").body()
	local L = { x = x, y = y, w = tw, h = ph, station = st, stock=stock, order=state.playerOrder }
	L.list = { x = x, y = y, w = LIST_W, h = ph }
	L.detail = { x = x + LIST_W + GAP, y = y, w = tw - LIST_W - GAP, h = ph }
	-- list rows
	local top = y + 44
	local visible = max(1, floor((ph - 44 - PAD) / ROW_H))
	Yard.scroll = max(0, min(Yard.scroll, #L.stock - visible))
	L.visibleRows = visible
	L.rows = {}
	for i, lot in ipairs(L.stock) do
		local k = i - Yard.scroll
		if lot.id == Yard.sel then L.lot = lot end
		if k >= 1 and k <= visible then
			table.insert(L.rows, { id = lot.id, lot = lot, x = x + 4, y = top + (k - 1) * ROW_H, w = LIST_W - 8, h = ROW_H - 2 })
		end
	end
	if not L.lot then return L end
	-- Detail: hull, paint and fit beside the stats and order controls.
	local D = L.detail
	L.lx, L.lw = D.x + PAD, LEFT_W
	L.rx = D.x + PAD + LEFT_W + 24
	L.rw = D.x + D.w - PAD - L.rx
	L.paintY = D.y + 188
	L.buy = { x = L.rx, y = D.y + D.h - PAD - 34, w = L.rw, h = 34 }
 L.paints={}
 local paints=Paint.pool(data.hulls[L.lot.hull])
 local cell=math.min(32,math.floor(L.lw/#paints))
 for i,name in ipairs(paints) do
  L.paints[i]={name=name,x=L.lx+(i-1)*cell,y=L.paintY,w=cell-5,h=26}
 end
	return L
end

local function drawList(game, L, mx, my)
	local P = L.list
	Station.panel(P.x, P.y, P.w, P.h)
	lg.setFont(HUD.font(18))
	lg.setColor(HUD.INK)
	local def = Dealers.def(L.station)
	lg.print(def and def.name or "For sale here", P.x + PAD, P.y + 8)
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
 lg.print('Manufacture a stock-fit ship',P.x+PAD,P.y+27)
	for _, r in ipairs(L.rows) do
		local lot = r.lot
		local hull = data.hulls[lot.hull]
		local on, hot = r.id == Yard.sel, inRect(r, mx, my)
		if on or hot then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.16 or 0.07)
			lg.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
		end
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.08)
		lg.line(r.x + 6, r.y + r.h + 0.5, r.x + r.w - 6, r.y + r.h + 0.5)
		local paint = (lot.color or Paint.preset(lot.paint))
		Hangar.drawHull(hull, r.x + 6, r.y + 8, 70, r.h - 16, false, paint, 1)
		lg.setFont(HUD.font(16))
		lg.setColor(HUD.INK)
		lg.print(hull.name, r.x + 86, r.y + 8)
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		lg.print(("%s \194\183 %s"):format((lot.used and ("Used / "..math.floor(lot.condition*100).."%") or lot.trimName or lot.trim), hull.class), r.x + 86, r.y + 25)
		lg.setFont(HUD.font(15))
		lg.setColor(game:credits() >= lot.price and HUD.INK or HUD.WARN)
		lg.printf(HUD.credits(lot.price), r.x, r.y + 8, r.w - 8, "right")
		local text = L.order and L.order.hull==lot.hull and (L.order.lot and "Ready to collect" or "In assembly queue") or "Stock fit"
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		lg.print(text, r.x + 86, r.y + 42)
	end
	if #L.stock > L.visibleRows then
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		lg.printf("scroll for more", P.x, P.y + P.h - 20, P.w - PAD, "right")
	end
end

local function drawDetail(game, L, mx, my)
	local D = L.detail
	Station.panel(D.x, D.y, D.w, D.h)
	local lot = L.lot
	if not lot then return end
	local hull = data.hulls[lot.hull]
	local paint = (lot.color or Paint.preset(lot.paint))
	local p = game.player

	-- left: identity, hull, paint, stock fit
	local x, w = L.lx, L.lw
	local y = Sheet.label(("%s \194\183 %s"):format(hull.maker, hull.class), x, D.y + 12)
	lg.setFont(HUD.font(24))
	lg.setColor(HUD.INK)
	lg.print(hull.name, x, y)
	y = Sheet.outline(hull, paint, x, y + 30, w, 108)
	Sheet.label("Paint", x, L.paintY - 17)
 local locked=L.order and L.order.hull==lot.hull
 for _,swatch in ipairs(L.paints) do
  local color=Paint.preset(swatch.name)
  lg.setColor(color[1],color[2],color[3],locked and swatch.name~=lot.paint and .35 or 1)
  lg.rectangle('fill',swatch.x,swatch.y,swatch.w,swatch.h,3,3)
  if swatch.name==lot.paint or not locked and inRect(swatch,mx,my) then
   lg.setColor(HUD.INK)
   lg.rectangle('line',swatch.x,swatch.y,swatch.w,swatch.h,3,3)
  end
 end
 lg.setFont(HUD.font(14))
 lg.setColor(HUD.INK)
 lg.print(paint.name or lot.paint,x,L.paintY+30)
 y=Sheet.paragraph(Sheet.description(hull),x,L.paintY+52,w,4)+8
	y = Sheet.label(("%s fit \194\183 %d slots"):format(lot.trimName or lot.trim, #hull.slots), x, y)
	Sheet.slots(hull, lot.loadout, x, y, w, D.y + D.h - PAD)

	-- right: numbers against what you fly
	local rx, rw = L.rx, L.rw
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.12)
	lg.rectangle("fill", rx - 6, D.y + 10, rw + 12, 26, 4, 4)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Compared with your " .. p.hull.name, rx, D.y + 14)
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.printf("both empty, as fitted", rx, D.y + 17, rw, "right")
	y = D.y + 42
	local mine = Sheet.numbers(p.hull, p.loadout)
	y = Sheet.compare(Sheet.numbers(hull, lot.loadout), mine, rx, y, rw) + 14

 local order=L.order
 local own=order and order.hull==lot.hull
 local text=own and (order.lot and 'Paid build ready in Hangar.' or 'Paid build in the assembly queue.')
  or (order and 'Collect or cancel your current order first.' or 'This yard assembles the ship for collection here.')
 lg.setFont(HUD.font(14))
 lg.setColor(HUD.DIM)
 lg.printf(text,rx,y,rw)
 local ready=own and order.lot
 local enabled=own or not order and game.universe.credits>=lot.price
 local label=ready and 'View ship in Hangar' or own and 'Cancel and refund'
  or 'Order · '..HUD.credits(lot.price)
 Sheet.button(L.buy,label,inRect(L.buy,mx,my),Sheet.GREEN,enabled)
end

function Yard.draw(game, mx, my)
	local L = Yard.layout(game)
	if not L then return end
	drawList(game, L, mx, my)
	drawDetail(game, L, mx, my)
end

function Yard.mousepressed(game,mx,my,button)
 local L=Yard.layout(game)
 if not L or button~=1 then return end
 for _,row in ipairs(L.rows) do
  if inRect(row,mx,my) then Yard.sel=row.id;return end
 end
 if not L.lot then return end
 local order=L.order
 if not order or order.hull~=L.lot.hull then
  for _,swatch in ipairs(L.paints) do
   if inRect(swatch,mx,my) then Yard.paintByHull[L.lot.hull]=swatch.name;return end
  end
 end
 if not inRect(L.buy,mx,my) then return end
 if order then
  if order.hull~=L.lot.hull then return end
  if order.lot then return 'collect',order.lot end
  local ok,why=Dealers.cancelShipOrder(game.universe,L.station)
  game:toast(ok and 'BUILD CANCELED. FUNDS RETURNED' or why,1.5)
 elseif game.universe.credits>=L.lot.price then
  local ok,why=Dealers.orderShip(game.universe,L.station,L.lot.hull,L.lot.paint)
  game:toast(ok and 'BUILD ORDER PLACED' or why,1.5)
 end
end

function Yard.wheelmoved(game, y)
	local L = Yard.layout(game)
	if not L then return end
	Yard.scroll = max(0, min(#L.stock - L.visibleRows, Yard.scroll - y))
end

return Yard
