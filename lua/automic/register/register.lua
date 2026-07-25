--- Register plugin declaration from config
---
--- Usage:
---   Pack.register({ "https://...", module = "plug" }):load({ utils = { menu = "plug.menu" }, var = {...}, config = fn })
---   Pack.register(...):lazy({ config = fn }) -- post-UIEnter; only config/utils/var
---   Pack.register({ spec = { src = "...", name = "..." }, module = "..." })
local cycle = require("automic.deps.cycle")
local notify_once = require("automic.util.notify_once")
local ensure_spec = require("automic.register.ensure_spec")
local register_dep_tree = require("automic.register.dep_tree")
local Handle = require("automic.register.handle")
local identity = require("automic.register.identity")
local listen = require("automic.build.listen")

--- Before re-register, remove this consumer from all dep ref lists
---@param consumer string
local function prune_refs(consumer)
	local Pack = _G.Pack
	for dep_name, refs in pairs(Pack.refs) do
		for i = #refs, 1, -1 do
			if refs[i] == consumer then
				table.remove(refs, i)
			end
		end
		if #refs == 0 then
			Pack.refs[dep_name] = nil
		end
	end
end

--- Remove all specs resolving to a package name.
---@param spec_list table
---@param name string
local function remove_spec(spec_list, name)
	local Pack = _G.Pack
	for i = #spec_list, 1, -1 do
		local ok, spec_name = pcall(Pack.parse, spec_list[i])
		if ok and spec_name == name then
			table.remove(spec_list, i)
		end
	end
end

--- True when the caller passed an empty placeholder (e.g. Pack.register({})).
---@param plugin table|nil
---@return boolean
local function is_blank_register(plugin)
	return type(plugin) == "table" and next(plugin) == nil
end

--- Normalize a single plugin table: [1] URL → spec.src; spec must be a table.
--- Always copy; never mutate the caller's table.
--- Accepts either a remote `spec.src` / `[1]` URL or a local `path` / `dev` pack.
---@param plugin table
---@return Pack.Plugin|nil
local function normalize_plugin(plugin)
	local P = vim.tbl_deep_extend("force", {}, plugin)

	if type(P[1]) == "string" then
		local src = P[1]
		P[1] = nil
		if P.spec ~= nil then
			notify_once(
				"register:spec_conflict",
				"Pack.register: do not pass spec when [1] is already a URL",
				vim.log.levels.ERROR
			)
			return nil
		end
		P.spec = { src = src }
	end

	if type(P.spec) == "string" then
		notify_once(
			"register:spec_string",
			"Pack.register: spec must be a table; use [1] = \"url\" or spec = { src = \"url\" }",
			vim.log.levels.ERROR
		)
		return nil
	end

	-- Local / dev packs: resolve path before requiring remote src.
	local has_path = type(P.path) == "string" and P.path ~= ""
	local want_dev = P.dev == true
	if has_path then
		P.path = vim.fs.normalize(vim.fn.expand(P.path))
	elseif want_dev then
		local root = vim.g.automic_dev_path
		if type(root) ~= "string" or root == "" then
			notify_once(
				"register:dev_path",
				"Pack.register: dev = true requires path = \"...\" or vim.g.automic_dev_path",
				vim.log.levels.ERROR
			)
			return nil
		end
		local hint = (type(P.spec) == "table" and P.spec.name)
			or P.name
			or (type(P.module) == "string" and P.module:match("([^%.]+)$"))
		-- Validate as a pack directory name before joining under automic_dev_path
		-- (rejects path separators / ".." from a hostile module hint).
		local Pack = _G.Pack
		local name_ok, safe = pcall(Pack.parse, { name = hint })
		if not name_ok then
			notify_once(
				"register:dev_name",
				"Pack.register: dev = true needs a safe spec.name / name / module segment\n"
					.. tostring(safe),
				vim.log.levels.ERROR
			)
			return nil
		end
		P.path = vim.fs.normalize(vim.fs.joinpath(vim.fn.expand(root), safe))
		has_path = true
	end

	if has_path then
		if vim.fn.isdirectory(P.path) ~= 1 then
			notify_once(
				"register:path_missing",
				"Pack.register: path is not a directory: " .. tostring(P.path),
				vim.log.levels.ERROR
			)
			return nil
		end
		P.spec = type(P.spec) == "table" and P.spec or {}
		if type(P.spec.name) ~= "string" or P.spec.name == "" then
			P.spec.name = (type(P.name) == "string" and P.name ~= "" and P.name)
				or vim.fs.basename(P.path)
		end
		-- Marker src so Pack.parse / fingerprint still work; never passed to vim.pack.add.
		if type(P.spec.src) ~= "string" or P.spec.src == "" then
			P.spec.src = "local:" .. P.path
		end
		-- Local packs default to lock so :PackUpdate does not touch them.
		if P.lock == nil then
			P.lock = true
		end
		if want_dev then
			P.dev = true
		end
		return P
	end

	if type(P.spec) ~= "table" or type(P.spec.src) ~= "string" or P.spec.src == "" then
		notify_once(
			"register:spec_invalid",
			"Pack.register: requires [1] = \"url\", spec = { src = \"...\" }, or path / dev = true",
			vim.log.levels.ERROR
		)
		return nil
	end

	return P
end

---@param plugin Pack.Plugin
---@return Pack.Handle|nil handle
return function(plugin, ...)
	if select("#", ...) > 0 then
		notify_once(
			"register:arity",
			"Pack.register: accepts a single table argument ([1] = \"url\" or spec = { src = \"...\" })",
			vim.log.levels.ERROR
		)
		return nil
	end
	if type(plugin) == "string" then
		notify_once(
			"register:string_arg",
			"Pack.register: URL must be table [1] or spec.src; a leading string argument is not allowed",
			vim.log.levels.ERROR
		)
		return nil
	end
	if type(plugin) ~= "table" then
		notify_once(
			"register:not_table",
			"Pack.register: expects a single table argument",
			vim.log.levels.ERROR
		)
		return nil
	end

	-- Empty placeholders (e.g. Pack.register({}):load({})) are allowed as no-ops.
	if is_blank_register(plugin) then
		return Handle.noop()
	end

	local Pack = _G.Pack
	local P = normalize_plugin(plugin)
	if not P then
		return nil
	end

	local id_ok, id_err = pcall(identity, P)
	if not id_ok or not P.name then
		notify_once(
			"register:identity",
			"Pack.register: unable to resolve plugin name\n" .. tostring(id_err or "unknown"),
			vim.log.levels.ERROR
		)
		return nil
	end

	if type(P.module) ~= "string" or P.module == "" then
		notify_once(
			"register:module",
			"Pack.register(" .. P.name .. "): module is a required string (it is no longer inferred from name)",
			vim.log.levels.ERROR
		)
		return nil
	end

	if P.utils ~= nil then
		notify_once(
			"register:utils",
			"Pack.register(" .. P.name .. "): utils moved to :load({ utils = ... })",
			vim.log.levels.ERROR
		)
		return nil
	end
	if P.var ~= nil then
		notify_once(
			"register:var",
			"Pack.register(" .. P.name .. "): var belongs on :load({ var = ... })",
			vim.log.levels.ERROR
		)
		return nil
	end
	if rawget(P, "disabled") ~= nil then
		notify_once(
			"register:disabled",
			"Pack.register(" .. P.name .. "): disabled was removed; use cond = false or cond = function()",
			vim.log.levels.ERROR
		)
		return nil
	end

	local disabled = false
	if P.cond ~= nil then
		local cond = P.cond
		if type(cond) == "function" then
			local ok, result = pcall(cond)
			if not ok then
				notify_once(
					"register:cond:" .. P.name,
					"Pack.register(" .. P.name .. "): cond() failed\n" .. tostring(result),
					vim.log.levels.ERROR
				)
				disabled = true
			else
				disabled = not result
			end
		elseif type(cond) == "boolean" then
			disabled = not cond
		else
			notify_once(
				"register:cond:" .. P.name,
				"Pack.register(" .. P.name .. "): cond must be a boolean or function",
				vim.log.levels.ERROR
			)
			return nil
		end
	end
	-- Derived idle flag for load/install/protect (not a public register field).
	P.disabled = disabled

	local existing = Pack.registry[P.name]
	local previous_module = existing and existing.module or nil
	local previous_path = existing and existing.path or nil
	if existing and existing._registered then
		for k, v in pairs(P) do
			existing[k] = v
		end
		-- pairs skips explicit nil; clear omitted fields to avoid stale data
		if rawget(P, "dependencies") == nil then
			existing.dependencies = nil
		end
		if rawget(P, "build") == nil then
			existing.build = nil
		end
		if rawget(P, "cond") == nil then
			existing.cond = nil
		end
		if rawget(P, "path") == nil then
			existing.path = nil
		end
		if rawget(P, "dev") == nil then
			existing.dev = nil
		end
		if rawget(P, "lock") == nil then
			existing.lock = nil
		end
		existing.utils = nil
		existing.var = nil
		P = existing
	end

	-- Drop stale local symlink when re-register removes `path`.
	if type(previous_path) == "string" and previous_path ~= "" then
		local still_local = type(P.path) == "string" and P.path ~= ""
		if not still_local then
			require("automic.install.local").unlink(P.name)
		end
	end

	local cycle_ok, cycle_err = cycle.check_tree(P.name, P.dependencies)
	if not cycle_ok then
		notify_once("register:cycle:" .. (P.name or "?"), cycle_err, vim.log.levels.ERROR)
		return nil
	end

	prune_refs(P.name)
	if P.dependencies then
		for _, dep in ipairs(P.dependencies) do
			register_dep_tree(dep, P.name, P.disabled, ensure_spec)
		end
	end

	if P.disabled then
		remove_spec(Pack.active, P.name)
		ensure_spec(Pack.idle, P.spec)
		Pack.disabled[P.name] = true
	else
		remove_spec(Pack.idle, P.name)
		ensure_spec(Pack.active, P.spec)
		Pack.disabled[P.name] = nil
	end

	-- Drop stale module→name mapping when re-register changes `module`.
	if type(previous_module) == "string" and previous_module ~= P.module then
		Pack.modules = Pack.modules or {}
		if Pack.modules[previous_module] == P.name then
			Pack.modules[previous_module] = nil
		end
	end

	Pack.registry[P.name] = P
	P._registered = true

	-- module → pack name for require() auto-load (longest prefix wins in the loader).
	Pack.modules = Pack.modules or {}
	local prev = Pack.modules[P.module]
	if prev and prev ~= P.name then
		vim.notify(
			"Pack.register("
				.. P.name
				.. "): module '"
				.. P.module
				.. "' was already claimed by "
				.. prev
				.. "; require() auto-load will use "
				.. P.name,
			vim.log.levels.WARN
		)
	end
	Pack.modules[P.module] = P.name

	local caller = debug.getinfo(2, "S")
	Pack.profile.track(P, nil, caller and caller.source, "plugin")

	-- Always sync cmds: clearing build must cmds.set(nil)
	listen(P.name, P.build)

	return Handle.new(P)
end
