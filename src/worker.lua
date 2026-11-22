--[[
	Two dedicated background threads for work the game can wait a moment for.

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
local W = { waiting = 0 }
local navigation = { pending = {}, nextId = 0 }
local routes = { pending = {}, nextId = 0 }
local workers = { navigation, routes }

local function workerFor(name)
 return name == "route" and routes or navigation
end

local function jobs() return require("src.worker_jobs") end
local function here(name, args)
	return jobs()[name](unpack(args, 1, args.n or #args))
end

function W.start()
 if not love.thread then return end
 for _, worker in ipairs(workers) do
  if not worker.thread and not worker.failed then
   worker.inbox, worker.outbox = love.thread.newChannel(), love.thread.newChannel()
   worker.thread = love.thread.newThread("src/worker_thread.lua")
   worker.thread:start(worker.inbox, worker.outbox)
  end
 end
end

function W.active(name) return workerFor(name).thread ~= nil end

local function stop(worker, reason)
 if not worker.thread then return end
 worker.inbox:push("quit")
 worker.thread = nil
 worker.failed = reason or true
 local pending = worker.pending
 worker.pending = {}
 for _, job in pairs(pending) do
  W.waiting = W.waiting - 1
  job.done(here(job.name, job.args))
 end
end

function W.stop(reason)
 for _, worker in ipairs(workers) do stop(worker, reason) end
end

function W.ask(name, args, done)
 assert(jobs()[name], "unknown worker job " .. tostring(name))
 local worker = workerFor(name)
 if not worker.thread then done(here(name, args)) return end
 worker.nextId = worker.nextId + 1
 local id = worker.nextId
 worker.pending[id] = { name = name, args = args, done = done }
 W.waiting = W.waiting + 1
 worker.inbox:push({ id = id, name = name, args = args, n = args.n or #args })
end

local function update(worker)
 if not worker.thread then return end
 local err = worker.thread:getError()
 if err then
  print("worker thread stopped: " .. tostring(err))
  stop(worker, err)
  return
 end
 while worker.thread do
  local answer = worker.outbox:pop()
  if not answer then break end
  local job = worker.pending[answer.id]
  if job then
   worker.pending[answer.id] = nil
   W.waiting = W.waiting - 1
   if answer.ok then job.done(answer.result)
   else
    print(("worker job %s failed, run on the main thread: %s"):format(job.name, tostring(answer.error)))
    job.done(here(job.name, job.args))
   end
  end
 end
end

function W.update()
 for _, worker in ipairs(workers) do update(worker) end
end

return W
