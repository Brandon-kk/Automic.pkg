local notify_once = require("automic.util.notify_once")

--- Deduplicate and append specs by pack directory name
---@param spec_list table
---@param spec any
---@return boolean added
return function(spec_list, spec)
	local Pack = _G.Pack
	local parse_ok, name = pcall(Pack.parse, spec)
	if not parse_ok then
		notify_once("register:spec", "Pack.register: invalid spec\n" .. tostring(name), vim.log.levels.ERROR)
		return false
	end
	for _, existing in ipairs(spec_list) do
		local existing_ok, existing_name = pcall(Pack.parse, existing)
		if existing_ok and existing_name == name then
			return false
		end
	end
	spec_list[#spec_list + 1] = spec
	return true
end
