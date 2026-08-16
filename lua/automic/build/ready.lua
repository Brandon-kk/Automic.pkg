--- Gate: function/shell builds must be stamped before config/require.
---
--- :Vim builds are skipped here — they need plugin commands and run via
--- ensure() only after Pack.inited.
---
--- This is the single pre-config entry point. load/load_dep must NOT fire-and-forget
--- ensure() for preconfig builds (that races with config).
local stamp = require("automic.build.stamp")
local retry = require("automic.build.retry")
local kind = require("automic.build.kind")
local BUILD_TIMEOUT_MS = 300000

---@param name string
---@param build? string|string[]|function
---@return boolean ok
return function(name, build)
	local Pack = _G.Pack
	name = Pack.parse(name)
	if Pack.disabled[name] or not kind.is_preconfig(build) then
		return true
	end

	local dir = Pack.path(name)
	if not dir then
		return false
	end
	if stamp.current(dir, build) then
		return true
	end

	-- Wait out an in-flight batch/ensure build started earlier in this session.
	if Pack.building[name] or retry.pending(name) then
		local finished = vim.wait(BUILD_TIMEOUT_MS, function()
			return not Pack.building[name] and not retry.pending(name)
		end, 20)
		return finished == true and stamp.current(dir, build)
	end

	local done, ok_result = false, false
	require("automic.build.run")(name, build, function(ok)
		done = true
		ok_result = ok
	end, { no_retry = true, sync = true })

	if not done then
		vim.wait(BUILD_TIMEOUT_MS, function()
			return done
		end, 20)
	end
	return ok_result == true and stamp.current(dir, build)
end
