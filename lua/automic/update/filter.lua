local locked = require("automic.update.locked")
local SELF_NAME = "Automic.pkg"

---@param values string[]
---@param value string
local function append_unique(values, value)
	if not vim.tbl_contains(values, value) then
		values[#values + 1] = value
	end
end

---@param targets? string[]
---@return string[] filtered
---@return string[] skipped
return function(targets)
	local Pack = _G.Pack
	local locked_set = locked.collect_locked()

	if targets then
		local filtered, skipped = {}, {}
		for _, name in ipairs(targets) do
			local parsed = Pack.parse(name)
			if locked_set[parsed] then
				skipped[#skipped + 1] = parsed
			else
				filtered[#filtered + 1] = parsed
			end
		end
		return filtered, skipped
	end

	local filtered, skipped = {}, {}
	for _, p in ipairs(vim.pack.get(nil, { info = false })) do
		local name = p.spec.name
		if locked_set[name] then
			skipped[#skipped + 1] = name
		else
			filtered[#filtered + 1] = name
		end
	end
	if Pack.registry[SELF_NAME] and not locked_set[SELF_NAME] then
		append_unique(filtered, SELF_NAME)
	end
	return filtered, skipped
end
