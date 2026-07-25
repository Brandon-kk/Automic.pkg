--- Chainable handle returned by Pack.boot()
local resolve_config = require("automic.boot.resolve")
local load_configs = require("automic.boot.load_configs")
local notify_once = require("automic.util.notify_once")
-- Boot registers the PackChanged listener for automatic restart after changes.
local restart = require("automic.restart.listen")

--- Schedule installation after boot; late calls must not wait for past events.
---@param install_fn fun()
local function schedule_install(install_fn)
	local Pack = _G.Pack
	if Pack._install_scheduled then
		return
	end
	Pack._install_scheduled = true
	if vim.v.vim_did_enter == 1 or #vim.api.nvim_list_uis() == 0 then
		vim.schedule(install_fn)
	else
		vim.api.nvim_create_autocmd({ "UIEnter", "VimEnter" }, {
			group = vim.api.nvim_create_augroup("PackBootInstall", { clear = true }),
			once = true,
			desc = "Pack.boot: deferred package install",
			callback = function()
				vim.schedule(install_fn)
			end,
		})
	end
end

local M = {}

--- Unknown chain methods warn and return self so later :run() still executes.
---@param self Pack.BootHandle
---@param key any
---@return any
function M.__index(self, key)
	local val = rawget(M, key)
	if val ~= nil then
		return val
	end
	if type(key) ~= "string" or key == "" then
		return nil
	end
	return function(handle)
		vim.notify(
			"Pack.boot: unknown method :" .. key .. "(); ignored, continuing chain",
			vim.log.levels.WARN
		)
		return handle
	end
end

---@param config? string
---@return Pack.BootHandle
function M.new(config)
	return setmetatable({
		_config = config,
		_ran = false,
	}, M)
end

---@param entries table|string
---@return Pack.BootHandle self
function M:keys(entries)
	require("automic.boot.core").keys(entries)
	return self
end

---@param groups table|string
---@return Pack.BootHandle self
function M:commands(groups)
	require("automic.boot.core").commands(groups)
	return self
end

---@param values table|string
---@return Pack.BootHandle self
function M:options(values)
	require("automic.boot.core").options(values)
	return self
end

---@param enable? table|string
---@param disable? string[]|string
---@return Pack.BootHandle self
function M:lsp(enable, disable)
	require("automic.boot.core").lsp(enable, disable)
	return self
end

---@param opts? boolean|Pack.AutosaveOpts
---@return Pack.BootHandle self
function M:autosave(opts)
	require("automic.autosave").setup(opts)
	return self
end

--- Run the package declaration boot flow.
---@return Pack
function M:run()
	local Pack = _G.Pack
	if Pack._booted then
		vim.notify("Pack.boot: already started; skipping duplicate boot", vim.log.levels.WARN)
		return Pack
	end
	if self._ran then
		return Pack
	end
	self._ran = true

	if type(self._config) ~= "string" or self._config == "" then
		return Pack
	end
	local dir, prefix = resolve_config(self._config)
	if not dir or not prefix then
		self._ran = false
		return Pack
	end

	-- hooks boot orchestration
	notify_once.clear()
	restart()
	local configs_ok = load_configs(dir, prefix)
	if not configs_ok then
		vim.notify("Plugin configuration loading failed; skipping package sync to protect installed plugins.", vim.log.levels.WARN)
		self._ran = false
		return Pack
	end
	Pack._booted = true
	schedule_install(function()
		require("automic.install")()
	end)
	-- Re-arm after declarations so startup closes after package UIEnter handlers.
	require("automic.profile").arm()

	return Pack
end

return M
