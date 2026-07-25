local norm = require("automic.deps.norm")

---@param dep any
---@return string
return function(dep)
	return norm(dep).name
end
