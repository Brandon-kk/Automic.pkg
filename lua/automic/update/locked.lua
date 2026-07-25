local notify_once = require("automic.util.notify_once")
local norm = require("automic.deps.norm")

local mark_tree

---@param dep any
---@param locked table<string, boolean>
mark_tree = function(dep, locked)
	local ok, item = pcall(norm, dep)
	if not ok then
		notify_once(
			"update:dep:" .. tostring(dep),
			"update dependency resolution failed: " .. tostring(item),
			vim.log.levels.ERROR
		)
		return
	end
	locked[item.name] = true
	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			mark_tree(nested, locked)
		end
	end
end

--- Collect lock=true plugins, local/path packs, and their entire dependency trees
---@return table<string, boolean>
local function collect_locked()
	local Pack = _G.Pack
	local locked = {}
	for _, P in pairs(Pack.registry) do
		local freeze = P.lock == true or (type(P.path) == "string" and P.path ~= "")
		if freeze then
			locked[P.name] = true
			if P.dependencies then
				for _, dep in ipairs(P.dependencies) do
					mark_tree(dep, locked)
				end
			end
		end
	end
	return locked
end

return {
	mark_tree = mark_tree,
	collect_locked = collect_locked,
}
