--- Packs that must drop cached Lua modules before the next build.
--- Set on PackChanged install/update (and force rebuild); consumed by run.lua
--- for every build kind (function, :Vim command, shell).
local marked = {}

local M = {}

---@param name string
function M.mark(name)
	marked[name] = true
end

---@param name string
---@return boolean
function M.consume(name)
	if not marked[name] then
		return false
	end
	marked[name] = nil
	return true
end

---@param name string
---@return boolean
function M.pending(name)
	return marked[name] == true
end

return M
