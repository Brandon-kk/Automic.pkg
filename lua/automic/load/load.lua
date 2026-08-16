--- Load plugin: dependencies → packadd (config runs from :load after utils/var are ready)
---
--- Pre-config builds (function/shell) are gated by automic.build.ready in :load/config_deps,
--- not fire-and-forget ensure() here (that races with config).
local notify_once = require("automic.util.notify_once")
local cycle = require("automic.deps.cycle")
local prepare = require("automic.load.prepare")
local load_dep = require("automic.load.load_dep")

---@param P table
---@param allow_startup? boolean
---@return boolean ok
return function(P, allow_startup)
	local Pack = _G.Pack

	if not prepare(P) then
		return false
	end

	local reg = Pack.registry[P.name]
	if reg then
		P = reg
	end

	if Pack.disabled[P.name] then
		return false
	end

	if not Pack.available(P.name) then
		notify_once(
			"load:missing:" .. P.name,
			"load(" .. P.name .. "): not installed yet, skipped",
			vim.log.levels.WARN
		)
		return false
	end

	if P.dependencies then
		local dep_ok, dep_err = cycle.check_tree(P.name, P.dependencies)
		if not dep_ok then
			notify_once("load:cycle:" .. P.name, dep_err, vim.log.levels.ERROR)
			return false
		end
	end

	if Pack.loaded[P.name] then
		return true
	end

	if P.dependencies then
		for _, dep in ipairs(P.dependencies) do
			if not load_dep(dep, P.name, { [P.name] = true }, { allow_startup = allow_startup }) then
				return false
			end
		end
	end
	local packadd_ok = pcall(vim.cmd.packadd, P.name)
	if not packadd_ok then
		notify_once("load:packadd:" .. P.name, "load(" .. P.name .. "): packadd failed", vim.log.levels.WARN)
		return false
	end
	Pack.loaded[P.name] = true
	notify_once.clear("load:missing:" .. P.name)
	notify_once.clear("load:packadd:" .. P.name)
	return true
end
