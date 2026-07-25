--- Register :PackUpdate / :PackStatus / :PackReBuild / :PackLoadProfile / :PackClean
local applied = false

return function()
	if applied then
		return
	end
	applied = true

	vim.api.nvim_create_user_command("PackUpdate", function(opts)
		local update = require("automic.update").update
		local targets = #opts.fargs > 0 and opts.fargs or nil
		if targets then
			vim.notify("Checking updates for: " .. table.concat(targets, ", "), vim.log.levels.INFO)
		else
			vim.notify("Checking updates for all plugins...", vim.log.levels.INFO)
		end
		update(targets, { force = opts.bang })
	end, {
		nargs = "*",
		bang = true,
		complete = function(...)
			return require("automic.update.complete")(...)
		end,
		desc = "Update plugins (confirm buffer; use ! to apply immediately); build then restart",
	})

	vim.api.nvim_create_user_command("PackStatus", function(opts)
		local update = require("automic.update").update
		local targets = #opts.fargs > 0 and opts.fargs or nil
		update(targets, { offline = true })
	end, {
		nargs = "*",
		complete = function(...)
			return require("automic.update.complete")(...)
		end,
		desc = "Check plugin status without downloading",
	})

	vim.api.nvim_create_user_command("PackReBuild", function(opts)
		local rebuild = require("automic.build.rebuild")
		local targets = #opts.fargs > 0 and opts.fargs or nil
		rebuild(targets, { force = opts.bang })
	end, {
		nargs = "*",
		bang = true,
		complete = function(arg_lead)
			arg_lead = arg_lead or ""
			local cmds = require("automic.build.cmds")
			local failed = require("automic.build.failed")
			local lead = arg_lead:lower()
			local failed_set, out = {}, {}
			for _, name in ipairs(failed.list()) do
				if cmds.get(name) and name:lower():find(lead, 1, true) == 1 then
					failed_set[name] = true
					out[#out + 1] = name
				end
			end
			local rest = {}
			for name in pairs(cmds.all()) do
				if not failed_set[name] and name:lower():find(lead, 1, true) == 1 then
					rest[#rest + 1] = name
				end
			end
			table.sort(rest)
			for _, name in ipairs(rest) do
				out[#out + 1] = name
			end
			return out
		end,
		desc = "Rebuild failed (or specified) plugins; use ! to force",
	})

	vim.api.nvim_create_user_command("PackLoadProfile", function()
		_G.Pack.profile.open()
	end, {
		desc = "Show Pack plugin load profile",
	})

	vim.api.nvim_create_user_command("PackHealth", function(opts)
		require("automic.health").run(opts.fargs)
	end, {
		nargs = "*",
		complete = function(...)
			return require("automic.update.complete")(...)
		end,
		desc = "Local Pack health report (env, installs, path/dev, lock/version notes)",
	})

	vim.api.nvim_create_user_command("PackClean", function(opts)
		require("automic.install.clean")({ force = opts.bang })
	end, {
		bang = true,
		desc = "Remove orphaned on-disk plugins; use ! to prune even when the registry is empty",
	})
end
