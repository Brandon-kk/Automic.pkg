--- Load a single Lua module (custom or config file)
---@param mod string
---@return boolean ok
return function(mod)
	local ok, err = pcall(require, mod)
	if not ok then
		vim.notify("Pack.boot: failed to load module: " .. mod .. "\n" .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end
