--- Call config with env injected via setfenv (main plugin: var only, no utils)
---
--- lua_ls: attach pack_utils.lua when boot:lsp activates (do not touch vim.lsp at hooks boot)
---@param config_fn function
---@param plugin any
---@param env? table
---@return boolean ok
---@return any err
return function(config_fn, plugin, env)
	if type(env) == "table" and next(env) then
		if not getmetatable(env) then
			setmetatable(env, { __index = _G })
		end
		setfenv(config_fn, env)
	end
	return pcall(config_fn, plugin)
end
