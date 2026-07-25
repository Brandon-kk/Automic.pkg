--- Dependency cycle detection
local M = {}
local norm = require("automic.deps.norm")

---@param dep any
---@param stack table<string, boolean>
---@param roots? string[]
---@return boolean ok
---@return string? err
function M.check(dep, stack, roots)
	local ok, item = pcall(norm, dep)
	if not ok then
		return false, tostring(item)
	end

	if stack[item.name] then
		local chain = {}
		if roots then
			for _, name in ipairs(roots) do
				chain[#chain + 1] = name
			end
		end
		chain[#chain + 1] = item.name .. " (cycle)"
		return false, "Dependency cycle: " .. table.concat(chain, " -> ")
	end

	stack[item.name] = true
	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			local nested_ok, err = M.check(nested, stack, roots)
			if not nested_ok then
				stack[item.name] = nil
				return false, err
			end
		end
	end
	stack[item.name] = nil
	return true, nil
end

---@param root_name string
---@param dependencies table
---@return boolean ok
---@return string? err
function M.check_tree(root_name, dependencies)
	if not dependencies then
		return true, nil
	end
	for _, dep in ipairs(dependencies) do
		local ok, err = M.check(dep, { [root_name] = true }, { root_name })
		if not ok then
			return false, err
		end
	end
	return true, nil
end

return M
