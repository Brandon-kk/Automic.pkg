--- Build var env: utils only for var internals; collect use=true one-shot callbacks
local RESERVED = { vim = true, Pack = true, _G = true, require = true }

---@param key string
---@return boolean
local function valid_key(key)
	return type(key) == "string" and key:match("^[%a_][%w_]*$") ~= nil and not RESERVED[key]
end

---@class Pack.VarUse
---@field name string
---@field callback function

---@param utils? table<string, any> already-required modules
---@param var? table
---@return table|nil var_env full env for var (includes utils)
---@return table|nil config_env var-only env for config (no utils)
---@return Pack.VarUse[]|nil use_list
---@return string|nil err
local function build(utils, var)
	utils = utils or {}
	if type(utils) ~= "table" then
		return nil, nil, nil, "utils must be a table"
	end
	if var ~= nil and type(var) ~= "table" then
		return nil, nil, nil, "var must be a table"
	end

	local var_env = {}
	local config_env = {}
	local use_list = {}

	for k, v in pairs(utils) do
		if not valid_key(k) then
			return nil, nil, nil, "utils key invalid or reserved: " .. tostring(k)
		end
		var_env[k] = v
	end

	if type(var) == "table" then
		for k, v in pairs(var) do
			if not valid_key(k) then
				return nil, nil, nil, "var key invalid or reserved: " .. tostring(k)
			end
			if var_env[k] ~= nil and utils[k] ~= nil then
				return nil, nil, nil, "var key conflicts with utils: " .. k
			end

			if type(v) == "function" then
				var_env[k] = v
				config_env[k] = v
			elseif type(v) == "table" and v.use == true then
				if type(v.callback) ~= "function" then
					return nil, nil, nil, "var." .. k .. " with use=true requires callback function"
				end
				var_env[k] = v
				config_env[k] = v
				use_list[#use_list + 1] = { name = k, callback = v.callback }
			else
				var_env[k] = v
				config_env[k] = v
			end
		end
	end

	setmetatable(var_env, { __index = _G })
	setmetatable(config_env, { __index = _G })

	-- var functions / use.callback can call each other and use utils
	if type(var) == "table" then
		for _, v in pairs(var) do
			if type(v) == "function" then
				setfenv(v, var_env)
			elseif type(v) == "table" and v.use == true and type(v.callback) == "function" then
				setfenv(v.callback, var_env)
			end
		end
	end

	table.sort(use_list, function(a, b)
		return a.name < b.name
	end)

	return var_env, config_env, use_list
end

return {
	build = build,
	valid_key = valid_key,
}
