--- Require extra modules from utils map; passed into config by parameter name
---@param utils? table<string, string>
---@return table|nil loaded
---@return string|nil err
return function(utils)
	if utils == nil then
		return {}
	end
	if type(utils) ~= "table" then
		return nil, "utils must be a table of name → require path"
	end

	local loaded = {}
	for key, path in pairs(utils) do
		if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") then
			return nil, "utils key must be a Lua identifier: " .. tostring(key)
		end
		if type(path) ~= "string" or path == "" then
			return nil, "utils entries must be identifier → non-empty require path"
		end
		local ok, mod = pcall(require, path)
		if not ok then
			return nil, "require(" .. path .. ") failed: " .. tostring(mod)
		end
		loaded[key] = mod
	end
	return loaded
end
