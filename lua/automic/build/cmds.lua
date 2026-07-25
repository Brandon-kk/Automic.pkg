--- Registered build commands (written by listen, read by batch)
local builds = {}

local M = {}

---@param name string
---@param build? string|string[]|function
function M.set(name, build)
	if not build then
		builds[name] = nil
	else
		builds[name] = build
	end
end

---@param name string
---@return string|string[]|function?
function M.get(name)
	return builds[name]
end

---@return table<string, string|string[]|function>
function M.all()
	return builds
end

return M
