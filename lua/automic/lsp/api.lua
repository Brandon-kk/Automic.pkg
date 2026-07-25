--- Sync enable/disable LSP by current buffer filetype
local state = require("automic.lsp.state")
local control = require("automic.lsp.control")
local sync = require("automic.lsp.sync")
local listen = require("automic.lsp.listen")
local ensure_lua_ls_plugin = require("automic.util.ensure_lua_ls_plugin")

local M = {}

local function activate()
	if state.activated then
		return
	end
	state.activated = true
	state.lazy_pending = false
	ensure_lua_ls_plugin()
	listen()
	sync()
end

---@param map table<string, string|string[]>
function M.enable(map)
	if type(map) ~= "table" then
		vim.notify("Pack.boot:lsp: enable must be a filetype-to-server mapping table", vim.log.levels.ERROR)
		return
	end

	for ft, servers in pairs(map) do
		if type(servers) == "string" then
			servers = { servers }
		end
		state.filetypes[ft] = servers
		for _, name in ipairs(servers) do
			state.disabled[state.norm(name)] = nil
		end
	end

	-- Already activated: merge map and sync only
	if state.activated then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) and map[vim.bo[buf].filetype] then
				sync(buf)
			end
		end
		return
	end

	-- Internal register: touch vim.lsp only on first FileType
	if not state.lazy_pending then
		state.lazy_pending = true
		vim.api.nvim_create_autocmd("FileType", {
			once = true,
			desc = "Pack.boot:lsp: load vim.lsp on first FileType",
			callback = function()
				vim.schedule(activate)
			end,
		})
	end

	-- Activate now if any loaded buffer already has a filetype
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
			vim.schedule(activate)
			break
		end
	end
end

---@param name string
function M.disable(name)
	name = state.norm(name)
	state.disabled[name] = true
	state.enabled[name] = nil
	if state.activated then
		vim.lsp.enable(name, false)
		control.stop(name)
	end
end

---@return boolean
function M.is_enabled(name)
	name = state.norm(name)
	return state.enabled[name] == true
end

---@return boolean
function M.is_disabled(name)
	name = state.norm(name)
	return state.disabled[name] == true
end

return M
