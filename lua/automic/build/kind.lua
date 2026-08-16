--- Build kind helpers shared by ensure / ready / run.
local M = {}

---@param build any
---@return boolean
function M.is_vim_cmd(build)
	if type(build) == "string" and build:sub(1, 1) == ":" then
		return true
	end
	if type(build) == "table" and type(build[1]) == "string" and build[1]:sub(1, 1) == ":" then
		return true
	end
	return false
end

--- Function and shell builds produce artifacts that config/require may need immediately.
--- :Vim builds need plugin commands and run only after Pack.inited.
---@param build any
---@return boolean
function M.is_preconfig(build)
	return build ~= nil and not M.is_vim_cmd(build)
end

return M
