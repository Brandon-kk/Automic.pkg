local notify_once = require("automic.util.notify_once")
local norm = require("automic.deps.norm")
local ready = require("automic.build.ready")

local load_dep

---@param dep any
---@param consumer_name string
---@param stack? table<string, boolean>
---@param opts? { skip_config?: boolean, allow_startup?: boolean }
load_dep = function(dep, consumer_name, stack, opts)
	opts = opts or {}
	stack = stack or {}
	local Pack = _G.Pack

	local ok_norm, item = pcall(norm, dep)
	if not ok_norm then
		notify_once(
			"dep:norm:" .. tostring(dep),
			"dependency resolve failed (" .. (consumer_name or "?") .. "): " .. tostring(item),
			vim.log.levels.ERROR
		)
		return false
	end
	local entry = Pack.profile.begin(item, opts.allow_startup)
	local function done(result, reason)
		Pack.profile.finish(item, entry, result, reason)
		return result
	end

	if stack[item.name] then
		notify_once(
			"dep:cycle:" .. item.name,
			"dependency cycle: " .. (consumer_name or "?") .. " -> " .. item.name,
			vim.log.levels.ERROR
		)
		return done(false, "dependency cycle")
	end
	stack[item.name] = true

	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			if not load_dep(nested, item.name, stack, opts) then
				stack[item.name] = nil
				return done(false, "nested dependency failed")
			end
		end
	end

	stack[item.name] = nil

	if Pack.disabled[item.name] then
		return done(false, "dependency disabled")
	end
	if not Pack.available(item.name) then
		notify_once(
			"dep:missing:" .. item.name,
			"dependency " .. item.name .. " not installed (from " .. (consumer_name or "?") .. "), skipped",
			vim.log.levels.WARN
		)
		return done(false, "dependency not installed")
	end

	if Pack.loaded[item.name] then
		-- Still gate preconfig builds: a prior packadd may have skipped build.
		if not ready(item.name, item.build) then
			notify_once(
				"dep:build:" .. item.name,
				"dependency build not ready: " .. item.name .. " (from " .. (consumer_name or "?") .. ")",
				vim.log.levels.ERROR
			)
			return done(false, "build not ready")
		end
		return done(true, "already loaded")
	end

	local dep_ok = pcall(vim.cmd.packadd, item.name)
	if not dep_ok then
		notify_once(
			"dep:packadd:" .. item.name,
			"dependency packadd failed: " .. item.name .. " (from " .. (consumer_name or "?") .. ")",
			vim.log.levels.WARN
		)
		return done(false, "packadd failed")
	end

	Pack.loaded[item.name] = true
	if not ready(item.name, item.build) then
		Pack.loaded[item.name] = nil
		notify_once(
			"dep:build:" .. item.name,
			"dependency build not ready: " .. item.name .. " (from " .. (consumer_name or "?") .. ")",
			vim.log.levels.ERROR
		)
		return done(false, "build not ready")
	end

	notify_once.clear("dep:missing:" .. item.name)
	notify_once.clear("dep:packadd:" .. item.name)
	return done(true)
end

return load_dep
