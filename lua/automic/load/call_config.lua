--- Call config: setup-only contract (main plugin: var only, no utils)
---
--- Forms:
---   config = { ... }                 → plugin.setup({ ... })
---   config = function(plugin) ... end → plugin is a proxy that only exposes setup()
---
--- lua_ls: attach pack_utils.lua when boot:lsp activates (do not touch vim.lsp at hooks boot)

---@param plugin any
---@return any proxy
local function setup_only_proxy(plugin)
	return setmetatable({}, {
		__index = function(_, key)
			if key == "setup" then
				local setup_fn = plugin and plugin.setup
				if type(setup_fn) ~= "function" then
					error("Pack.config: module has no setup(); config may only call plugin.setup(...)")
				end
				-- Dot-call: plugin.setup(opts) → setup_fn(opts)
				return setup_fn
			end
			error("Pack.config: only plugin.setup(...) is allowed (got ." .. tostring(key) .. ")")
		end,
		__newindex = function(_, key)
			error("Pack.config: cannot assign plugin." .. tostring(key) .. "; only setup(...)")
		end,
	})
end

---@param config function|table
---@param plugin any
---@param env? table
---@return boolean ok
---@return any err
return function(config, plugin, env)
	if type(config) == "table" then
		local setup_fn = plugin and plugin.setup
		if type(setup_fn) ~= "function" then
			return false, "Pack.config: module has no setup(); cannot apply table config"
		end
		return pcall(setup_fn, config)
	end

	if type(config) ~= "function" then
		return false, "Pack.config: config must be a function or setup options table"
	end

	if type(env) == "table" and next(env) then
		if not getmetatable(env) then
			setmetatable(env, { __index = _G })
		end
		setfenv(config, env)
	end

	return pcall(config, setup_only_proxy(plugin))
end
