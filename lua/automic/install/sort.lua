local cycle = require("automic.deps.cycle")
local walk = require("automic.deps.walk")

--- Topo-sort specs so vim.pack.add installs dependencies before consumers
---@param active_specs table
---@return table? sorted nil if a cycle is detected or validation fails
--- nil if cycle detected or validation failed
return function(active_specs)
	local Pack = _G.Pack
	local name_to_spec = {}
	for _, spec in ipairs(active_specs) do
		name_to_spec[Pack.parse(spec)] = spec
	end

	for _, spec in ipairs(active_specs) do
		local name = Pack.parse(spec)
		local P = Pack.registry[name]
		if P and P.dependencies then
			local ok, err = cycle.check_tree(name, P.dependencies)
			if not ok then
				vim.notify("install sort: " .. tostring(err), vim.log.levels.ERROR)
				return nil
			end
		end
	end

	local sorted_names = {}
	local visited = {}
	local visiting = {}

	local function visit(name)
		if visited[name] then
			return true
		end
		if visiting[name] then
			vim.notify("install sort detected a dependency cycle: " .. name, vim.log.levels.ERROR)
			return false
		end
		if not name_to_spec[name] then
			return true
		end

		visiting[name] = true

		local P = Pack.registry[name]
		if P and P.dependencies then
			for _, dep in ipairs(P.dependencies) do
				if walk(dep, visit) == false then
					visiting[name] = nil
					vim.notify("install sort: dependency traversal failed (" .. name .. ")", vim.log.levels.ERROR)
					return false
				end
			end
		end

		visiting[name] = nil
		visited[name] = true
		sorted_names[#sorted_names + 1] = name
		return true
	end

	for _, spec in ipairs(active_specs) do
		if visit(Pack.parse(spec)) == false then
			return nil
		end
	end

	local sorted = {}
	for _, name in ipairs(sorted_names) do
		sorted[#sorted + 1] = name_to_spec[name]
	end
	return sorted
end
