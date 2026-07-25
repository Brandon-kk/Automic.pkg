local norm = require("automic.deps.norm")
local depname = require("automic.deps.depname")

local walk

---@param dep any
---@param fn fun(name: string): boolean?
---@param stack? table<string, boolean>
---@return boolean
walk = function(dep, fn, stack)
	stack = stack or {}
	local ok, name = pcall(depname, dep)
	if not ok then
		return false
	end
	if stack[name] then
		return false
	end
	stack[name] = true
	if fn(name) == false then
		stack[name] = nil
		return false
	end
	local ok_norm, item = pcall(norm, dep)
	if not ok_norm then
		stack[name] = nil
		return false
	end
	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			if walk(nested, fn, stack) == false then
				stack[name] = nil
				return false
			end
		end
	end
	stack[name] = nil
	return true
end

return walk
