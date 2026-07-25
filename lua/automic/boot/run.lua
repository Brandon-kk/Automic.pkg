--- Boot orchestration: return a chainable handle.
local Handle = require("automic.boot.handle")

---@param config? string Plugin config-module prefix; omit for core-only configuration.
---@return Pack.BootHandle
return function(config)
	return Handle.new(config)
end
