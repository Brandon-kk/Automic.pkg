--- After plugin setup, run var use=true callbacks with the plugin module (once per plugin)
local notify_once = require("automic.util.notify_once")

---@param plugin_name string
---@param plugin any
---@param use_list { name: string, callback: function }[]
---@return boolean ok
return function(plugin_name, plugin, use_list)
	if type(use_list) ~= "table" or #use_list == 0 then
		return true
	end

	local Pack = _G.Pack
	Pack.var_used = Pack.var_used or {}
	if Pack.var_used[plugin_name] then
		return true
	end

	for _, item in ipairs(use_list) do
		local ok, err = pcall(item.callback, plugin)
		if not ok then
			notify_once(
				"handle:var_use:" .. plugin_name .. ":" .. item.name,
				"Pack.handle:load(" .. plugin_name .. "): var." .. item.name .. " callback failed\n" .. tostring(err),
				vim.log.levels.ERROR
			)
			-- Do not mark var_used on failure so next load can retry
			return false
		end
	end

	Pack.var_used[plugin_name] = true
	return true
end
