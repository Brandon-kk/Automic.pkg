--- Whether a dep is still used by a non-disabled plugin
---@param name string
---@return boolean
return function(name)
	local Pack = _G.Pack
	local refs = Pack.refs[name]
	if not refs then
		return false
	end
	for _, consumer in ipairs(refs) do
		local P = Pack.registry[consumer]
		if P and not P.disabled then
			return true
		end
	end
	return false
end
