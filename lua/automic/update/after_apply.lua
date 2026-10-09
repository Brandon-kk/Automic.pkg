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

	local function mark_built(ok_names)
		for _, name in ipairs(ok_names) do
			state.built[#state.built + 1] = name
		end
	end

	if #names == 0 then
		require("automic.restart").relaunch()
		return
	end

	batch(function(result)
		mark_built(result.ok_names)
		if #result.fail_names > 0 then
			vim.notify(
				"Build failed for: " .. table.concat(result.fail_names, ", ")
					.. "\nRestarting; affected plugins stay disabled until :PackReBuild <name> succeeds.",
				vim.log.levels.ERROR
			)
			-- The live session was partially unloaded for the build; staying in it only
			-- produces require-error cascades. Restart so boot gating (ready) holds the
			-- failed plugins disabled with a single message instead.
			vim.defer_fn(function()
				require("automic.restart").relaunch()
			end, 3000)
			return
		end
		require("automic.restart").relaunch()
	end, names)
end
