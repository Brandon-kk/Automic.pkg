local norm = require("automic.deps.norm")

local function shield(dep, protected, stack)
	stack = stack or {}
	local ok, item = pcall(norm, dep)
	if not ok then
		return
	end
	if stack[item.name] then
		return
	end
	stack[item.name] = true
	protected[item.name] = true
	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			shield(nested, protected, stack)
		end
	end
	stack[item.name] = nil
end

--- Collect pack dirs to keep (registered plugins + their dependency trees)
---@return table<string, boolean>
local function protect()
	local Pack = _G.Pack
	local protected = {}

	for name, P in pairs(Pack.registry) do
		protected[name] = true
		if P.dependencies then
			for _, dep in ipairs(P.dependencies) do
				shield(dep, protected, {})
			end
		end
	end

	return protected
end

--- List plugin names that still depend on name
---@param name string
---@return string[]
local function users(name)
	local Pack = _G.Pack
	local refs = Pack.refs[name] or {}
	local active = {}
	for _, consumer in ipairs(refs) do
		local P = Pack.registry[consumer]
		if P and not P.disabled then
			active[#active + 1] = consumer
		end
	end
	return active
end

return {
	protect = protect,
	users = users,
}
