--- Boot orchestration: return a chainable handle.
local Handle = require("automic.boot.handle")

---@param config? string Plugin config-module prefix; omit for core-only configuration.
---@param opts? Pack.BootOpts
---@return Pack.BootHandle
return function(config, opts)
	return Handle.new(config, opts)
end
