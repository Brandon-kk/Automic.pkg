--- After all updates are applied: build only updated packages that declare build,
--- then restart on full success (same ordering as install → build → restart).
local batch = require("automic.build.batch")
local cmds = require("automic.build.cmds")
local state = require("automic.restart.state")

return function()
	local Pack = _G.Pack
	local names, seen = {}, {}
	for _, name in ipairs(state.updated) do
		if not seen[name] and cmds.get(name) and not Pack.disabled[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end

	if #names == 0 then
		require("automic.restart").relaunch()
		return
	end

	batch(function(result)
		if #result.fail_names > 0 then
			vim.notify(
				"Build failed; automatic restart skipped: " .. table.concat(result.fail_names, ", "),
				vim.log.levels.ERROR
			)
			return
		end
		for _, name in ipairs(result.ok_names) do
			state.built[#state.built + 1] = name
		end
		require("automic.restart").relaunch()
	end, names)
end
