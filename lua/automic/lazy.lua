--- Emit one `User Lazy` event after UI initialization settles for non-critical plugins.
local M = {}

--- Fire `User Lazy` once per Neovim session (internal; used by setup).
local function emit()
	local Pack = _G.Pack
	if Pack._lazy_fired then
		return
	end
	Pack._lazy_fired = true
	vim.api.nvim_exec_autocmds("User", {
		pattern = "Lazy",
		modeline = false,
	})
end

--- Trigger across two successive schedule ticks after UIEnter completes.
--- The second tick lets other UIEnter callbacks and their first scheduled work finish first.
function M.setup()
	local Pack = _G.Pack
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.lazy then
		return
	end
	Pack._listeners.lazy = true

	vim.api.nvim_create_autocmd("UIEnter", {
		group = vim.api.nvim_create_augroup("PackLazy", { clear = true }),
		once = true,
		desc = "Emit User Lazy after UI initialization settles",
		callback = function()
			vim.schedule(function()
				vim.schedule(emit)
			end)
		end,
	})
end

return M
