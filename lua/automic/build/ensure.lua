--- If build exists and not yet built, trigger build (async).
---
--- Pre-config builds (function / shell): prefer automic.build.ready before config.
--- This module is for:
---   - :Vim builds after Pack.inited
---   - install/update batch (via cmds + batch)
---   - opportunistic background rebuild when stamp is stale
local stamp = require("automic.build.stamp")
local retry = require("automic.build.retry")
local kind = require("automic.build.kind")

---@param name string
---@param build string|string[]|function
return function(name, build)
	local Pack = _G.Pack
	name = Pack.parse(name)
	if Pack.disabled[name] or not build then
		return
	end
	-- :Vim builds need plugin commands registered during config/init.
	if kind.is_vim_cmd(build) and not Pack.inited[name] then
		return
	end
	local dir = Pack.path(name)
	if not dir or stamp.current(dir, build) then
		return
	end
	if Pack.building[name] or retry.pending(name) then
		return
	end
	retry.reset(name)
	require("automic.build.run")(name, build)
end
