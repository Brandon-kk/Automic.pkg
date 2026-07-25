--- Shared state for the LSP module
local M = {
	enabled = {},
	disabled = {},
	filetypes = {},
	listened = false,
	--- enable() registered; activate on first FileType
	lazy_pending = false,
	--- listen/sync have run (vim.lsp already touched)
	activated = false,
	--- Per-buffer wanted server sets, maintained incrementally after activation.
	buffer_servers = {},
	--- Last filetype synced per buffer (BufEnter fast path).
	buffer_ft = {},
	--- Number of loaded buffers currently requiring each server.
	server_refs = {},
}

---@param name string
---@return string
function M.norm(name)
	return (name:gsub("%.lua$", ""))
end

return M
