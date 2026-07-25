--- Walk up for project root by markers; fall back to cwd so LSP can start for single files.
---@param markers string|(string|string[])[]
---@return fun(bufnr: integer, on_dir: fun(dir: string))
local function root(markers)
	return function(bufnr, on_dir)
		local root_markers = markers
		root_markers = vim.fn.has("nvim-0.11.3") == 1 and { root_markers, { ".git" } }
			or vim.list_extend(vim.tbl_copy(root_markers), { ".git" })
		on_dir(vim.fs.root(bufnr, root_markers) or vim.fn.getcwd())
	end
end

return root
