--- Stop all LSP clients with the given name
---@param name string
return function(name)
	for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
		client:stop(true)
	end
end
