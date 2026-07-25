local notify_once = require("automic.util.notify_once")
local identity = require("automic.register.identity")

---@param P table
---@return boolean
return function(P)
	local Pack = _G.Pack
	identity(P)
	if not P.name then
		notify_once("load:noname", "load: unable to resolve plugin name", vim.log.levels.ERROR)
		return false
	end

	if not P._registered and not Pack.registry[P.name] then
		notify_once(
			"load:unregistered:" .. P.name,
			"load(" .. P.name .. "): Pack.register was not called; request rejected",
			vim.log.levels.ERROR
		)
		return false
	end

	return true
end
