--- Chainable handle from Pack.register(): :load({ event | keys/cmd/ft, ... }) / :lazy({ config, ... })
local M = {}
M.__index = M

-- `Pack.register()` only records events; the full load/build chain is unnecessary until a plugin actually loads.
-- Keep these modules off the startup path until a plugin load is actually run.
local runtime
local function modules()
	if runtime then
		return runtime
	end
	runtime = {
		pack_load = require("automic.load.load"),
		config_deps = require("automic.load.config_deps"),
		ensure = require("automic.build.ensure"),
		require_utils = require("automic.load.require_utils"),
		build_env = require("automic.load.build_env"),
		call_config = require("automic.load.call_config"),
		run_var_use = require("automic.load.run_var_use"),
		notify_once = require("automic.util.notify_once"),
	}
	return runtime
end

--- Autocmd-only fields that are meaningless without a custom `event`.
--- (`nested` is not user-configurable: Pack always creates nested event autocmds.)
local AU_ONLY = { "pattern", "once", "buffer", "group" }

---@param event any
---@return string|string[]|nil normalized
---@return string|nil err
local function normalize_event(event)
	if event == nil then
		return nil, nil
	end
	if type(event) == "string" then
		if event == "" then
			return nil, 'event must be a non-empty string'
		end
		if event == "Lazy" then
			return nil, 'event = "Lazy" was removed; use :lazy() instead'
		end
		return event, nil
	end
	if type(event) == "table" then
		local out = {}
		for i, item in ipairs(event) do
			if type(item) ~= "string" or item == "" then
				return nil, "event[" .. i .. "] must be a non-empty string"
			end
			if item == "Lazy" then
				return nil, 'event = "Lazy" was removed; use :lazy() instead'
			end
			out[#out + 1] = item
		end
		if #out == 0 then
			return nil, "event list must not be empty"
		end
		return #out == 1 and out[1] or out, nil
	end
	return nil, "event must be a string or list of strings"
end

---@param opts table
---@param name string
---@return boolean ok
local function validate_setup_fields(opts, name)
	if opts.config ~= nil and type(opts.config) ~= "function" and type(opts.config) ~= "table" then
		vim.notify(
			"Pack.handle(" .. name .. "): config must be a function or setup options table",
			vim.log.levels.ERROR
		)
		return false
	end
	if opts.utils ~= nil and type(opts.utils) ~= "table" then
		vim.notify("Pack.handle(" .. name .. "): utils must be a table", vim.log.levels.ERROR)
		return false
	end
	if opts.var ~= nil and type(opts.var) ~= "table" then
		vim.notify("Pack.handle(" .. name .. "): var must be a table", vim.log.levels.ERROR)
		return false
	end
	if opts.defer ~= nil and type(opts.defer) ~= "boolean" then
		vim.notify("Pack.handle(" .. name .. "): defer must be a boolean", vim.log.levels.ERROR)
		return false
	end
	return true
end

--- :lazy() accepts only config / utils / var.
local LAZY_ALLOWED = { config = true, utils = true, var = true }

---@param opts table
---@param name string
---@return boolean ok
local function validate_lazy_opts(opts, name)
	local bad = {}
	for key in pairs(opts) do
		if not LAZY_ALLOWED[key] then
			bad[#bad + 1] = tostring(key)
		end
	end
	if #bad > 0 then
		table.sort(bad)
		vim.notify(
			"Pack.handle:lazy("
				.. name
				.. "): only config/utils/var are allowed; got "
				.. table.concat(bad, ", ")
				.. " (use :load() for event/keys/cmd/ft/colorscheme/defer)",
			vim.log.levels.ERROR
		)
		return false
	end
	return validate_setup_fields(opts, name)
end

---@param opts table
---@param has_event boolean
local function warn_stray_autocmd_fields(opts, has_event, name)
	if has_event then
		return
	end
	local stray = {}
	for _, key in ipairs(AU_ONLY) do
		if opts[key] ~= nil then
			stray[#stray + 1] = key
		end
	end
	if #stray > 0 then
		vim.notify(
			"Pack.handle:load("
				.. name
				.. "): "
				.. table.concat(stray, "/")
				.. " only apply with event; ignored",
			vim.log.levels.WARN
		)
	end
end

--- Claim the single allowed :load/:lazy for this plugin. Refuses a second schedule
--- even if the caller got a fresh handle from re-registering the same name.
---@param self Pack.Handle
---@param method "load"|"lazy"
---@return boolean
local function claim_schedule(self, method)
	local P = self.P
	local prior = P._load_claimed or self._scheduled
	if prior then
		vim.notify(
			"Pack.handle:"
				.. method
				.. "("
				.. P.name
				.. "): already scheduled via :"
				.. prior
				.. "; rejected (will not load)",
			vim.log.levels.ERROR
		)
		return false
	end
	P._load_claimed = method
	self._scheduled = method
	return true
end

--- Release claim when scheduling itself failed (no trigger was actually installed).
---@param self Pack.Handle
local function release_schedule(self)
	local P = self.P
	if P then
		P._load_claimed = nil
	end
	self._scheduled = nil
end

---@param P Pack.Plugin
---@return Pack.Handle handle
function M.new(P)
	return setmetatable({ P = P }, M)
end

--- No-op handle so `Pack.register({}):load(...)` / `:lazy(...)` stays chainable after a blank skip.
---@return Pack.Handle handle
function M.noop()
	return setmetatable({ _noop = true }, M)
end

---@param opts Pack.LoadOpts
---@param mode "load"|"lazy"
---@return Pack.Handle self
function M:_apply(opts, mode)
	local P = self.P
	local Pack = _G.Pack
	local track_opts = opts
	if mode == "lazy" then
		track_opts = vim.tbl_extend("force", {}, opts, { event = "Lazy" })
	end
	Pack.profile.track(P, track_opts)
	local allow_startup = not (opts.event == "UIEnter" and opts.defer == true)

	---@param force_sync? boolean keys/cmd must finish before replaying the trigger
	---@param after? fun(ok: boolean) called after load settles (including deferred UIEnter)
	local function run(force_sync, after)
		local go = function()
			Pack.loading = Pack.loading or {}
			Pack._load_waiters = Pack._load_waiters or {}
			if Pack.loading[P.name] then
				-- Concurrent trigger: queue after-hooks so event replay still runs
				-- when the in-flight load finishes (do not fire with half-ready state).
				if after then
					local waiters = Pack._load_waiters[P.name]
					if not waiters then
						waiters = {}
						Pack._load_waiters[P.name] = waiters
					end
					waiters[#waiters + 1] = after
				end
				return
			end
			Pack.loading[P.name] = true
			local entry = Pack.profile.begin(P, allow_startup)
			Pack._loading_entries = Pack._loading_entries or {}
			Pack._loading_entries[P.name] = entry
			local settled = false
			local function done(ok, reason)
				if settled then
					return
				end
				settled = true
				Pack.profile.finish(P, entry, ok, reason)
				Pack.loading[P.name] = nil
				Pack._loading_entries[P.name] = nil
				local waiters = Pack._load_waiters[P.name]
				Pack._load_waiters[P.name] = nil
				local function call_after(fn)
					local after_ok, after_err = pcall(fn, ok)
					if not after_ok then
						vim.notify(
							"Pack.handle:load(" .. P.name .. "): after-load hook failed\n" .. tostring(after_err),
							vim.log.levels.ERROR
						)
					end
				end
				if after then
					call_after(after)
				end
				if waiters then
					for _, waiter in ipairs(waiters) do
						call_after(waiter)
					end
				end
			end
			local R = modules()
			-- Already inited: skip config / var_use (align with dep config_deps guard)
			if Pack.inited[P.name] then
				if not Pack.loaded[P.name] then
					R.pack_load(P, allow_startup)
				end
				done(Pack.loaded[P.name] == true, "already initialized")
				return
			end

			if not R.pack_load(P, allow_startup) then
				done(false, "packadd failed")
				return
			end

			local utils, utils_err = R.require_utils(opts.utils)
			if not utils then
				Pack.loaded[P.name] = nil
				R.notify_once(
					"handle:utils:" .. P.name,
					"Pack.handle:load(" .. P.name .. "): utils failed\n" .. tostring(utils_err),
					vim.log.levels.ERROR
				)
				done(false, "utils failed")
				return
			end

			local _, config_env, use_list, env_err = R.build_env.build(utils, opts.var)
			if not config_env then
				Pack.loaded[P.name] = nil
				R.notify_once(
					"handle:var:" .. P.name,
					"Pack.handle:load(" .. P.name .. "): var/utils env failed\n" .. tostring(env_err),
					vim.log.levels.ERROR
				)
				done(false, "var environment failed")
				return
			end

			if P.dependencies and not R.config_deps.tree(P.dependencies, allow_startup) then
				Pack.loaded[P.name] = nil
				done(false, "dependency config failed")
				return
			end

			if not opts.config then
				local plugin
				if #use_list > 0 then
					local ok, loaded = pcall(require, P.module)
					if not ok then
						Pack.loaded[P.name] = nil
						R.notify_once(
							"handle:require:" .. P.name,
							"Pack.handle:load(" .. P.name .. "): require failed\n" .. tostring(loaded),
							vim.log.levels.ERROR
						)
						done(false, "require failed")
						return
					end
					plugin = loaded
				end
				if not R.run_var_use(P.name, plugin, use_list) then
					Pack.loaded[P.name] = nil
					done(false, "var use failed")
					return
				end
				Pack.inited[P.name] = true
				R.ensure(P.name, P.build)
				done(true)
				return
			end

			local ok, loaded = pcall(require, P.module)
			if not ok then
				Pack.loaded[P.name] = nil
				R.notify_once(
					"handle:require:" .. P.name,
					"Pack.handle:load(" .. P.name .. "): require failed\n" .. tostring(loaded),
					vim.log.levels.ERROR
				)
				done(false, "require failed")
				return
			end

			local setup_ok, err = R.call_config(opts.config, loaded, config_env)
			if not setup_ok then
				Pack.loaded[P.name] = nil
				R.notify_once(
					"handle:config:" .. P.name,
					"Pack.handle:load(" .. P.name .. "): config failed\n" .. tostring(err),
					vim.log.levels.ERROR
				)
				done(false, "config failed")
				return
			end

			if not R.run_var_use(P.name, loaded, use_list) then
				Pack.loaded[P.name] = nil
				done(false, "var use failed")
				return
			end

			-- Mark inited only after full success (aligned with var_used)
			Pack.inited[P.name] = true
			R.ensure(P.name, P.build)
			done(true)
		end
		local function safe_go()
			local ok, err = xpcall(go, debug.traceback)
			if ok then
				return
			end
			local entry = Pack._loading_entries and Pack._loading_entries[P.name]
			if entry then
				Pack.profile.finish(P, entry, false, "unexpected error")
				Pack._loading_entries[P.name] = nil
			end
			Pack.loading[P.name] = nil
			vim.notify("Pack.handle:load(" .. P.name .. ") failed\n" .. tostring(err), vim.log.levels.ERROR)
			if after then
				pcall(after, false)
			end
		end
		if not force_sync and opts.defer and opts.event == "UIEnter" then
			vim.schedule(safe_go)
		else
			safe_go()
		end
	end

	if mode == "lazy" then
		Pack._runners = Pack._runners or {}
		Pack._runners[P.name] = function(force_sync, after)
			run(force_sync, after)
		end
		-- Lazy already fired (late :lazy / manual trigger): load now or never.
		if Pack._lazy_fired then
			run()
			return self
		end
		local au = {
			pattern = "Lazy",
			once = true,
			nested = true,
			desc = "Pack.lazy for " .. P.name,
			callback = function()
				if Pack.inited[P.name] and Pack.loaded[P.name] then
					return
				end
				run()
			end,
			group = vim.api.nvim_create_augroup("PackLoad:" .. P.name .. ":User:Lazy", {
				clear = true,
			}),
		}
		local ok_au, au_err = pcall(vim.api.nvim_create_autocmd, "User", au)
		if not ok_au then
			release_schedule(self)
			vim.notify(
				"Pack.handle:lazy(" .. P.name .. "): failed to create Lazy autocmd\n" .. tostring(au_err),
				vim.log.levels.ERROR
			)
		end
		return self
	end

	-- Expose runner for module loader / shared triggers / colorscheme.
	Pack._runners = Pack._runners or {}
	Pack._runners[P.name] = function(force_sync, after)
		run(force_sync, after)
	end

	local triggers = require("automic.load.triggers")
	local has_triggers = triggers.has(opts)
	local has_event = opts.event ~= nil
	local deferred = has_event or has_triggers
	local scheduled = false

	if has_event then
		local au = vim.tbl_deep_extend("force", {}, opts)
		local event = opts.event
		au.event = nil
		au.defer = nil
		au.config = nil
		au.utils = nil
		au.var = nil
		au.keys = nil
		au.cmd = nil
		au.ft = nil
		au.colorscheme = nil
		-- Always nested so :colorscheme / other cmds inside load fire autocmds
		-- (e.g. packs with colorscheme=… on ColorSchemePre). Not user-configurable.
		au.nested = true
		au.callback = function(ev)
			if Pack.disabled[P.name] then
				return
			end
			if Pack.inited[P.name] and Pack.loaded[P.name] then
				return
			end
			-- Capture before load; re-fire so plugin autocmd handlers see this event
			-- (and FileType → BufReadPost → BufReadPre chain), like lazy.nvim.
			local event_replay = require("automic.load.event_replay")
			local fired = type(ev.event) == "string" and ev.event or event
			if type(fired) == "table" then
				fired = fired[1]
			end
			local state = event_replay.capture(tostring(fired), ev.buf, ev.data)
			run(nil, function(ok)
				if ok then
					event_replay.fire(state)
				end
			end)
		end
		local ev = event
		local ev_key = type(ev) == "table" and table.concat(ev, ",") or tostring(ev)
		local pat = au.pattern
		local pat_key = type(pat) == "table" and table.concat(pat, ",") or tostring(pat or "")
		au.group = vim.api.nvim_create_augroup("PackLoad:" .. P.name .. ":" .. ev_key .. ":" .. pat_key, {
			clear = true,
		})
		local ok_au, au_err = pcall(vim.api.nvim_create_autocmd, event, au)
		if not ok_au then
			vim.notify(
				"Pack.handle:load(" .. P.name .. "): failed to create autocmd\n" .. tostring(au_err),
				vim.log.levels.ERROR
			)
		else
			scheduled = true
		end
	end

	if has_triggers then
		triggers.bind(P.name, opts)
		scheduled = true
	end

	if not deferred then
		run()
		scheduled = true
	end

	-- event/trigger path failed to install anything → allow a corrected retry.
	if deferred and not scheduled then
		release_schedule(self)
	end

	return self
end

---@param opts? Pack.LoadOpts
---@return Pack.Handle self
function M:load(opts)
	if self._noop then
		return self
	end
	opts = opts or {}

	if not validate_setup_fields(opts, self.P.name) then
		return self
	end

	local event, event_err = normalize_event(opts.event)
	if event_err then
		vim.notify("Pack.handle:load(" .. self.P.name .. "): " .. event_err, vim.log.levels.ERROR)
		return self
	end

	local triggers = require("automic.load.triggers")
	local ok_fields, fields_err = triggers.validate(opts)
	if not ok_fields then
		vim.notify("Pack.handle:load(" .. self.P.name .. "): " .. fields_err, vim.log.levels.ERROR)
		return self
	end

	local kinds = triggers.kinds(opts)
	if event ~= nil then
		table.insert(kinds, 1, "event")
	end
	if #kinds > 1 then
		vim.notify(
			"Pack.handle:load("
				.. self.P.name
				.. "): event/keys/cmd/ft/colorscheme are mutually exclusive; got "
				.. table.concat(kinds, "+")
				.. " (choose one)",
			vim.log.levels.ERROR
		)
		return self
	end

	if not claim_schedule(self, "load") then
		return self
	end

	warn_stray_autocmd_fields(opts, event ~= nil, self.P.name)

	local clean = opts
	if event ~= nil and event ~= opts.event then
		clean = vim.tbl_extend("force", {}, opts, { event = event })
	end

	return self:_apply(clean, "load")
end

--- Load after Pack's one-shot post-UIEnter `User Lazy` event.
--- Only `config` / `utils` / `var` are accepted; use `:load()` for triggers.
--- If Lazy already fired, loads immediately.
---@param opts? Pack.LazyOpts
---@return Pack.Handle self
function M:lazy(opts)
	if self._noop then
		return self
	end
	opts = opts or {}

	if not validate_lazy_opts(opts, self.P.name) then
		return self
	end

	if not claim_schedule(self, "lazy") then
		return self
	end

	return self:_apply(opts, "lazy")
end

return M
