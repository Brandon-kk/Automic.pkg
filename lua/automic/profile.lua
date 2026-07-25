--- Profile Pack startup and plugin loading. The UI loads on demand only via :PackLoadProfile.
local uv = vim.uv

local M = {
	plugins = {},
	deferred_cpu_ms = 0,
	deferred_depth = 0,
}
local SELF_NAME = "Automic.pkg"

local function cpu_ms()
	local usage = uv.getrusage()
	local function ms(time)
		return (time.sec * 1000) + (time.usec / 1000)
	end
	return ms(usage.utime) + ms(usage.stime)
end

local function source_path(source)
	if type(source) ~= "string" then
		return nil
	end
	return source:sub(1, 1) == "@" and source:sub(2) or source
end

---@param plugin table
---@param opts? Pack.LoadOpts
---@param source? string
---@param kind? "plugin"|"dependency"
---@return table
function M.track(plugin, opts, source, kind)
	local entry = M.plugins[plugin.name]
	if not entry then
		entry = { name = plugin.name }
		M.plugins[plugin.name] = entry
	end
	entry.module = plugin.module or entry.module
	entry.source = source_path(source) or entry.source
	entry.kind = kind or entry.kind or "plugin"
	entry.disabled = plugin.disabled == true
	if opts then
		entry.event = opts.event
		entry.pattern = opts.pattern
		entry.defer = opts.defer == true and opts.event == "UIEnter"
		local ft, cmd, keys, colorscheme = require("automic.load.triggers").summary(opts)
		entry.ft = ft
		entry.cmd = cmd
		entry.keys = keys
		entry.colorscheme = colorscheme
	end
	return entry
end

---@param dep table
---@param parent string
---@param source? string
function M.track_dependency(dep, parent, source)
	local entry = M.track(dep, nil, source, "dependency")
	entry.parents = entry.parents or {}
	if not vim.tbl_contains(entry.parents, parent) then
		entry.parents[#entry.parents + 1] = parent
	end
end

---@param plugin table
---@param allow_startup? boolean
---@return { entry: table, started_at: integer, cpu_started_at: number, startup: boolean, deferred: boolean } token
function M.begin(plugin, allow_startup)
	local startup = allow_startup ~= false and not M.startup_closed
	local deferred = not startup and not M.startup_finalized and M.deferred_depth == 0
	if not startup then
		M.deferred_depth = M.deferred_depth + 1
	end
	return {
		entry = M.track(plugin),
		started_at = uv.hrtime(),
		cpu_started_at = cpu_ms(),
		startup = startup,
		deferred = deferred,
	}
end

---@param plugin table
---@param token { entry: table, started_at: integer, cpu_started_at: number, startup: boolean, deferred: boolean }
---@param ok boolean
---@param reason? string
function M.finish(plugin, token, ok, reason)
	local entry = token.entry
	local elapsed = (uv.hrtime() - token.started_at) / 1e6
	local cpu_elapsed = cpu_ms() - token.cpu_started_at
	entry.load_ms = (entry.load_ms or 0) + elapsed
	entry.attempts = (entry.attempts or 0) + 1
	entry.loaded = _G.Pack.loaded[plugin.name] == true
	entry.inited = _G.Pack.inited[plugin.name] == true
	entry.ok = ok
	entry.reason = reason
	entry.finished_at = uv.hrtime()
	if token.startup then
		entry.startup_load_ms = (entry.startup_load_ms or 0) + elapsed
		entry.startup_attempts = (entry.startup_attempts or 0) + 1
		entry.startup_loaded = entry.loaded
		entry.startup_inited = entry.inited
		entry.startup_ok = ok
		entry.startup_reason = reason
	else
		M.deferred_depth = math.max(0, M.deferred_depth - 1)
		if token.deferred and not M.startup_finalized then
			M.deferred_cpu_ms = M.deferred_cpu_ms + cpu_elapsed
		end
	end
end

--- Record Automic.pkg bootstrap wall time (plugin/automic.lua → end of init).
function M.finish_self()
	if M._self_finished then
		return
	end
	M._self_finished = true
	local t0 = vim.g._automic_profile_t0
	if type(t0) ~= "number" then
		return
	end
	vim.g._automic_profile_t0 = nil
	local elapsed = (uv.hrtime() - t0) / 1e6
	M.self_ms = elapsed
	local entry = M.track({ name = SELF_NAME, module = "automic" }, nil, nil, "manager")
	entry.load_ms = elapsed
	entry.startup_load_ms = elapsed
	entry.attempts = 1
	entry.startup_attempts = 1
	entry.loaded = true
	entry.inited = true
	entry.startup_loaded = true
	entry.startup_inited = true
	entry.ok = true
	entry.startup_ok = true
	entry.finished_at = uv.hrtime()
	if _G.Pack then
		_G.Pack.loaded[SELF_NAME] = true
		_G.Pack.inited[SELF_NAME] = true
	end
end

local function snapshot_entries()
	local entries = {}
	for name, entry in pairs(M.plugins) do
		local snapshot = vim.deepcopy(entry)
		snapshot.load_ms = entry.startup_load_ms or 0
		snapshot.attempts = entry.startup_attempts or 0
		snapshot.loaded = entry.startup_loaded == true
		snapshot.inited = entry.startup_inited == true
		snapshot.ok = entry.startup_ok
		snapshot.reason = entry.startup_reason
		entries[name] = snapshot
	end
	return entries
end

local function close_startup()
	if M.startup_finalized then
		return
	end
	-- Cut off at first UI ready (same window as --startuptime "NVIM STARTED").
	-- Do not vim.schedule: that runs after STARTED and includes User Lazy loads.
	M.startup_ms = math.max(0, cpu_ms() - M.deferred_cpu_ms)
	M.startup_finished_at = uv.hrtime()
	M.startup_plugins = snapshot_entries()
	M.startup_closed = true
	M.startup_finalized = true
end

--- Arm / re-arm startup closer. Call again at the end of Pack.boot():run() so
--- the UIEnter handler runs after package handlers registered during boot.
function M.arm()
	local group = vim.api.nvim_create_augroup("PackLoadProfile", { clear = true })
	vim.api.nvim_create_autocmd("UIEnter", {
		group = group,
		once = true,
		desc = "Close Pack startup profile at UI ready (STARTED)",
		callback = close_startup,
	})
	-- Pure headless: UIEnter may never fire; close after VimEnter instead.
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		once = true,
		desc = "Close Pack startup profile when no UI (headless)",
		callback = function()
			if #vim.api.nvim_list_uis() == 0 then
				close_startup()
			end
		end,
	})
end

function M.setup()
	if M._setup then
		return
	end
	M._setup = true
	M.arm()
end

---@return table[]
function M.entries()
	local entries = {}
	local source = M.startup_plugins or M.plugins
	for _, entry in pairs(source) do
		if not M.startup_plugins then
			entry.loaded = _G.Pack.loaded[entry.name] == true
			entry.inited = _G.Pack.inited[entry.name] == true
		end
		entries[#entries + 1] = entry
	end
	table.sort(entries, function(a, b)
		if (a.load_ms or 0) == (b.load_ms or 0) then
			return a.name < b.name
		end
		return (a.load_ms or 0) > (b.load_ms or 0)
	end)
	return entries
end

function M.summary()
	local entries = M.entries()
	local loaded = 0
	for _, entry in ipairs(entries) do
		if entry.loaded then
			loaded = loaded + 1
		end
	end
	return {
		startup_ms = M.startup_ms or cpu_ms(),
		self_ms = M.self_ms,
		total = #entries,
		loaded = loaded,
	}
end

function M.open()
	require("automic.profile.ui").open(M)
end

return M
