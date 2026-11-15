--[[
	One background thread for work the game can wait a moment for.

	The rule: a job is a function in src/worker_jobs.lua that takes plain
	data (numbers, strings, booleans, tables of them) and returns plain
	data. It can't see the game: a thread is a separate Lua with its own
	copy of every module, so nothing it changes comes back except its
	answer. Adding a job is adding a function there.

	  Worker.ask(name, args, done)   run job `name` with the list `args`;
	                                 done(result) is called on the main
	                                 thread, from Worker.update, when the
	                                 answer is in.
	  Worker.update()                once a frame (love.update).
	  Worker.active()                is there a thread to ask?

	With no thread (tests, Worker.start never called, a thread that died)
	Worker.ask runs the same function right here and calls done before it
	returns, so everything works the same without one, only slower. A job
	that fails in the thread is run again here, where its error shows.
]]
local W = { pending = {}, nextId = 0, waiting = 0 }

local function jobs() return require("src.worker_jobs") end
local function here(name, args)
	return jobs()[name](unpack(args, 1, args.n or #args))
end

function W.start()
	if W.thread or W.failed or not love.thread then return end
	W.inbox, W.outbox = love.thread.newChannel(), love.thread.newChannel()
	W.thread = love.thread.newThread("src/worker_thread.lua")
	W.thread:start(W.inbox, W.outbox)
end

function W.active() return W.thread ~= nil end

-- Stop asking the thread: what it still owes is done here instead.
function W.stop(reason)
	if not W.thread then return end
	W.inbox:push("quit")
	W.thread = nil
	W.failed = reason or true
	local owed = W.pending
	W.pending, W.waiting = {}, 0
	for _, p in pairs(owed) do p.done(here(p.name, p.args)) end
end

function W.ask(name, args, done)
	assert(jobs()[name], "unknown worker job " .. tostring(name))
	if not W.thread then done(here(name, args)) return end
	W.nextId = W.nextId + 1
	W.pending[W.nextId] = { name = name, args = args, done = done }
	W.waiting = W.waiting + 1
	W.inbox:push({ id = W.nextId, name = name, args = args, n = args.n or #args })
end

function W.update()
	if not W.thread then return end
	local err = W.thread:getError()
	if err then
		print("worker thread stopped: " .. tostring(err))
		W.stop(err)
		return
	end
	while true do
		local answer = W.outbox:pop()
		if not answer then break end
		local p = W.pending[answer.id]
		if p then
			W.pending[answer.id] = nil
			W.waiting = W.waiting - 1
			if answer.ok then p.done(answer.result)
			else
				print(("worker job %s failed, run on the main thread: %s"):format(p.name, tostring(answer.error)))
				p.done(here(p.name, p.args))
			end
		end
	end
end

return W
