-- The background thread (src/worker.lua): takes a job, runs it, sends the
-- answer back. Everything it knows it loaded itself from the game's files.
local inbox, outbox = ...
require("love.filesystem")
require("love.data")
require("love.math")
require("love.timer")
local jobs = require("src.worker_jobs")
while true do
	local ask = inbox:demand()
	if ask == "quit" then break end
	local ok, result = xpcall(function()
		return jobs[ask.name](unpack(ask.args, 1, ask.n))
	end, debug.traceback)
	if ok then outbox:push({ id = ask.id, ok = true, result = result })
	else outbox:push({ id = ask.id, ok = false, error = tostring(result) }) end
end
