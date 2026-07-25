--- Seal Pack table fields that must not be wholesale replaced
local SEALED = {
	registry = true,
	active = true,
	idle = true,
	refs = true,
}

---@param pack table
---@return table sealed_pack
return function(pack)
	local store = pack
	return setmetatable({}, {
		__index = store,
		__newindex = function(_, key, value)
			if SEALED[key] then
				error(
					("Pack.%s cannot be replaced wholesale (prevents accidental deletion during sync). Use Pack.register() to add or remove entries, or modify individual keys."):format(
						key
					),
					2
				)
			end
			store[key] = value
		end,
		__pairs = function()
			return pairs(store)
		end,
	})
end
