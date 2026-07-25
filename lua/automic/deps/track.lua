local depname = require("automic.deps.depname")

--- Track consumer→dep refs (shared dependencies allowed)
---@param dep any
---@param consumer_name string
---@return string?
return function(dep, consumer_name)
	local Pack = _G.Pack
	local ok, name = pcall(depname, dep)
	if not ok or not name then
		return nil
	end
	local refs = Pack.refs[name]
	if not refs then
		refs = {}
		Pack.refs[name] = refs
	end
	for _, ref in ipairs(refs) do
		if ref == consumer_name then
			return name
		end
	end
	refs[#refs + 1] = consumer_name
	return name
end
