-- Loads the game data the way the game does (src/data.lua, data.load) with a
-- stand-in love.filesystem, so generated ships can be checked without the game:
--   luajit tools/shipgen/loadcheck.lua <save folder>      (run from the repo root)
local SAVE=arg[1] or "."
package.path='./?.lua;./?/init.lua;'..package.path
local function real(p) local f=io.open(SAVE..'/'..p) if f then f:close() return SAVE..'/'..p end f=io.open(p) if f then f:close() return p end end
local function isdir(p) local ok=os.execute('test -d "'..p..'"'); return ok==0 or ok==true end
love={filesystem={},math={},timer={getTime=os.clock}}
function love.filesystem.read(p) local r=real(p); local f=io.open(r); local s=f:read('*a'); f:close(); return s end
function love.filesystem.getInfo(p,kind)
 for _,base in ipairs({SAVE..'/'..p,p}) do
  if isdir(base) then if not kind or kind=='directory' then return {type='directory'} end
  elseif io.open(base) and (not kind or kind=='file') then return {type='file'} end end
end
function love.filesystem.getDirectoryItems(p)
 local out,seen={},{}
 for _,base in ipairs({SAVE..'/'..p,p}) do if isdir(base) then for n in io.popen('ls "'..base..'"'):lines() do if not seen[n] then seen[n]=1 out[#out+1]=n end end end end
 return out
end
function love.math.triangulate(s) local t={} for k=3,#s/2-1 do t[#t+1]={s[1],s[2],s[2*k-1],s[2*k],s[2*k+1],s[2*k+2]} end return t end
local data=require('src.data')
local ok,err=pcall(data.load)
print(ok and "ok  data loads" or ("FAIL " .. tostring(err)))
if not ok then os.exit(1) end
local n=0 for id,h in pairs(data.hulls) do if h.workspace then n=n+1 end end
print('workspace hulls', n, 'game hulls', #data.list.hulls-n)

