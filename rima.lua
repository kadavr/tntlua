--
-- rima.lua
--

--
-- Task manager for imap collector.
-- Task's key is a user email address.
-- Rima can manage some tasks with the same key.
-- Tasks with identical keys will be groupped and managed as one bunch of tasks.
--
-- Producers can adds tasks by rima_put() calls.
-- Consumer request a bunch of tasks (with common key) by calling rima_get().
-- When Rima gives a task to worker it locks the key until worker calls rima_done(key).
-- Rima does not return task with already locked keys.
--

--
-- Space 0: Remote IMAP Collector Task Queue
--   Tuple: { task_id (NUM64), key (STR), task_description (NUM), add_time (NUM) }
--   Index 0: TREE { task_id }
--   Index 1: TREE { key, task_id }
--
-- Space 2: Task Priority
--   Tuple: { key (STR), priority (NUM), is_locked (NUM), lock_time (NUM) }
--   Index 0: TREE { key }
--   Index 1: TREE { priority, is_locked, lock_time }
--

--
-- Put task to the queue.
--
local function rima_put_impl(key, data, prio)
	-- TODO Remove workaround
	key = key:gsub("@external$", "")

	-- insert task data into the queue
	box.auto_increment(0, key, data, box.time())
	-- increase priority of the key
	local pr = box.select_limit(2, 0, 0, 1, key)
	if pr == nil then
		box.insert(2, key, prio, 0, box.time())
	elseif box.unpack('i', pr[1]) < prio then
		box.update(2, key, "=p", 1, prio)
	end
end

function rima_put(key, data) -- deprecated
	rima_put_impl(key, data, 512)
end

function rima_put_with_prio(key, data, prio)
	prio = box.unpack('i', prio)

	rima_put_impl(key, data, prio)
end

local function get_prio_key(prio)
	local v = box.select_limit(2, 1, 0, 1, prio, 0)
	if v == nil then return nil end

	-- lock the key
	local key = v[0]
	box.update(2, key, "=p=p", 2, 1, 3, box.time())

	return key
end

local function get_key_data(key)
	local result = { key }

	local tuples = { box.select_limit(0, 1, 0, 1000, key) }
	for _, tuple in pairs(tuples) do
		tuple = box.delete(0, box.unpack('l', tuple[0]))
		if tuple ~= nil then
			table.insert(result, { box.unpack('i', tuple[3]), tuple[2] } )
		end
	end

	return result
end

--
-- Request tasks from the queue.
--
function rima_get_ex(prio)
	prio = box.unpack('i', prio)

	local key = get_prio_key(prio)
	if key == nil then return end
	return get_key_data(key)
end

--
-- Notify manager that tasks for that key was completed.
-- Rima unlocks key and next rima_get() may returns tasks with such key.
--
function rima_done(key)
	-- TODO Remove workaround
	key = key:gsub("@external$", "")

	local pr = box.select_limit(2, 0, 0, 1, key)
	if pr == nil then return end

	if box.select_limit(0, 1, 0, 1, key) == nil then
		-- no tasks for this key in the queue
		box.delete(2, key)
	else
		box.update(2, key, "=p=p", 2, 0, 3, box.time())
	end
end

--
-- Explicitly lock tasks for the key.
--
function rima_lock(key)
	local pr = box.select_limit(2, 0, 0, 1, key)
	if pr ~= nil and box.unpack('i', pr[2]) > 0 then return 0 end

	-- lock the key
	if pr ~= nil then
		box.update(2, key, "=p=p", 2, 1, 3, box.time())
	else
		box.insert(2, key, 0, 1, box.time())
	end

	return 1
end

--
-- Run expiration of tuples
--

local function is_expired(args, tuple)
	if tuple == nil or #tuple <= args.fieldno then
		return nil
	end

	-- expire only locked keys
	if box.unpack('i', tuple[2]) == 0 then return false end

	local field = tuple[args.fieldno]
	local current_time = box.time()
	local tuple_expire_time = box.unpack('i', field) + args.expiration_time
	return current_time >= tuple_expire_time
end

local function delete_expired(spaceno, args, tuple)
	rima_done(tuple[0])
end

dofile('expirationd.lua')

expirationd.run_task('expire_locks', 2, is_expired, delete_expired, {fieldno = 3, expiration_time = 30*60})
