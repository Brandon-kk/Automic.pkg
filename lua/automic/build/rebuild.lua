--- :PackReBuild — rebuild failed-recorded plugins (or given names)
--- :PackReBuild! — force rebuild even when stamp is current
local batch = require("automic.build.batch")
local failed = require("automic.build.failed")
local cmds = require("automic.build.cmds")
local stamp = require("automic.build.stamp")

---@param name string
---@return boolean
local function needs_build(name)
	local build = cmds.get(name)
	if not build then
		return false
	end
	local Pack = _G.Pack
	local dir = Pack.path(name)
	if not dir then
		return false
	end
	return not stamp.current(dir, build)
end

---@param targets? string[]
---@param opts? { force?: boolean }
return function(targets, opts)
	opts = opts or {}
	local force = opts.force == true
	local explicit = targets and #targets > 0
	local names = explicit and targets or failed.list()

	local pending = {}
	for _, name in ipairs(names) do
		local n = _G.Pack.parse(name)
		if not cmds.get(n) then
			if not explicit then
				failed.remove(n)
			end
		elseif force or needs_build(n) then
			pending[#pending + 1] = n
		elseif not explicit then
			failed.remove(n)
		end
	end
	names = pending

	if #names == 0 then
		vim.notify("No plugins need building", vim.log.levels.INFO)
		return
	end

	batch(function(result)
		if result.ran == 0 then
			vim.notify("No plugins need building", vim.log.levels.INFO)
			return
		end
		if #result.fail_names > 0 then
			vim.notify("Build failed; automatic restart skipped: " .. table.concat(result.fail_names, ", "), vim.log.levels.ERROR)
			return
		end
		local state = require("automic.restart.state")
		for _, name in ipairs(result.ok_names) do
			state.built[#state.built + 1] = name
		end
		require("automic.restart").relaunch()
	end, names, { force = force, silent_start = false })
end
