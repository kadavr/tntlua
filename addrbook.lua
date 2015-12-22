--
-- addrbook.lua
--

-- Space 1: User recipients info
--   Tuple: { user_id (NUM), rcp_email (STR), rcp_name (NUM), timestamp (NUM), weight (NUM) }
--   Index 0: TREE { user_id, rcp_email }

function addrbook_add_recipient(user_id, rcp_email, rcp_name, timestamp)
	user_id = box.unpack('i', user_id)
	timestamp = box.unpack('i', timestamp)

	local t = box.select_limit(1, 0, 0, 1, user_id, rcp_email)
	if t == nil then
		box.insert(1, user_id, rcp_email, rcp_name, timestamp, 1)
		return 1 -- new contact inserted
	end
	if box.unpack('i', t[3]) < timestamp then
		box.update(1, { user_id, rcp_email }, "=p=p+p", 2, rcp_name, 3, timestamp, 4, 1)
		return 2 -- contact updated
	end

	box.update(1, { user_id, rcp_email }, "+p", 4, 1)
	return 0 -- contact weight updated only
end

function addrbook_load(user_id)
	user_id = box.unpack('i', user_id)
	if(uid == nil) then
		return false
	end
	local tuple = box.select(0, 0, user_id) -- space 0 index 0
	if( tuple == nil) then
		return false
	end
	return tuple
end

function addrbook_save(user_id, book)
	user_id = box.unpack('i', user_id)
	if(user_id == nil or book == nil) then
		return false
	end
	local tuple = box.update(0, user_id, "=p", 1, book)

	if( tuple == nil) then
		return false
	end
	return tuple
end

function addrbook_delete(user_id)
	user_id = box.unpack('i', user_id)
	if(user_id == nil) then
		return false
	end
	local tuple = box.delete(0, user_id)

	if( tuple == nil) then
		return false
	end
	return tuple
end
