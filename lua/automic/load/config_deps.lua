--- Run configs in dependency-tree order (after packadd; no main utils/var injection)
local notify_once = require("automic.util.notify_once")
local require_utils = require("automic.load.require_utils")
local call_config = require("automic.load.call_config")
local norm = require("automic.deps.norm")
local ensure = require("automic.build.ensure")

---@param item table
---@param allow_startup? boolean
---@return boolean
local function run_config(item, allow_startup)
	if not item.config or _G.Pack.inited[item.name] then
		return true
	end
	local entry = _G.Pack.profile.begin(item, allow_startup)
	local function done(result, reason)
		_G.Pack.profile.finish(item, entry, result, reason)
		return result
	end
	if type(item.module) ~= "string" or item.module == "" then
		notify_once(
			"dep:module:" .. item.name,
			"dependency " .. item.name .. " has config but missing module",
			vim.log.levels.ERROR
		)
		return done(false, "missing module")
	end
	local mod_ok, mod = pcall(require, item.module)
	if not mod_ok then
		notify_once(
			"dep:require:" .. item.name,
			"dependency require failed: " .. item.name .. "\n" .. tostring(mod),
			vim.log.levels.ERROR
		)
		return done(false, "require failed")
	end
	-- Dep-local utils still for its own config only (main utils not injected)
	local dep_utils, utils_err = require_utils(item.utils)
	if not dep_utils then
		notify_once(
			"dep:utils:" .. item.name,
			"dependency utils failed: " .. item.name .. "\n" .. tostring(utils_err),
			vim.log.levels.ERROR
		)
		return done(false, "utils failed")
	end
	local ok, err = call_config(item.config, mod, dep_utils)
	if not ok then
		notify_once(
			"dep:config:" .. item.name,
			"dependency config failed: " .. item.name .. "\n" .. tostring(err),
			vim.log.levels.ERROR
		)
		return done(false, "config failed")
	end
	_G.Pack.inited[item.name] = true
	ensure(item.name, item.build)
	return done(true)
end

---@param deps any[]?
---@param allow_startup? boolean
---@return boolean
local function config_tree(deps, allow_startup)
	if not deps then
		return true
	end
	for _, dep in ipairs(deps) do
		local ok_norm, item = pcall(norm, dep)
		if not ok_norm then
			notify_once(
				"dep:norm:" .. tostring(dep),
				"dependency resolve failed: " .. tostring(item),
				vim.log.levels.ERROR
			)
			return false
		end
		if item.dependencies and not config_tree(item.dependencies, allow_startup) then
			return false
		end
		if not run_config(item, allow_startup) then
			return false
		end
	end
	return true
end

return {
	run = run_config,
	tree = config_tree,
}
