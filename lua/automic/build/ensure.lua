--- If build exists and not yet built, trigger build
local stamp = require("automic.build.stamp")
local retry = require("automic.build.retry")

--- :Vim build commands must run after plugin init
---@param build string|string[]|function
---@return boolean
local function is_vim_cmd(build)
	if type(build) == "string" and build:sub(1, 1) == ":" then
		return true
	end
	if type(build) == "table" and type(build[1]) == "string" and build[1]:sub(1, 1) == ":" then
		return true
	end
	return false
end

---@param name string
---@param build string|string[]|function
return function(name, build)
	local Pack = _G.Pack
	name = Pack.parse(name)
	if Pack.disabled[name] or not build then
		return
	end
	if is_vim_cmd(build) and not Pack.inited[name] then
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
