---@return boolean
return function()
	if vim.g.vscode then
		return false
	end
	for _, arg in ipairs(vim.v.argv) do
		if arg == "--headless" or arg == "-es" then
			return false
		end
	end
	return true
end
