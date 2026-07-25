--- Whether plugin is fully installed (healthy git repo; no layout assumptions)
local healthy = require("automic.deps.healthy")

local function available(name)
	local Pack = _G.Pack
	name = Pack.parse(name)
	local dir = Pack.path(name)
	if not dir then
		return false
	end
	return healthy.healthy(dir)
end

return available
