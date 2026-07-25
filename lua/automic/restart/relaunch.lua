--- Restart automatically after package changes.
local state = require("automic.restart.state")
local should_auto_restart = require("automic.restart.should_restart")
local save_all = require("automic.restart.save_all")

local function do_restart()
	-- Silent write (then clear remaining modified flags); `:restart` has no bang form.
	pcall(save_all)
	vim.notify("Restarting Neovim...", vim.log.levels.INFO)
	vim.schedule(function()
		vim.cmd("restart")
	end)
end

return function()
	if #state.installed == 0 and #state.built == 0 and #state.updated == 0 and #state.removed == 0 then
		return
	end

	if not should_auto_restart() then
		state.installed = {}
		state.built = {}
		state.updated = {}
		state.removed = {}
		if state.update_restart_timer then
			state.update_restart_timer:stop()
			state.update_restart_timer:close()
			state.update_restart_timer = nil
		end
		return
	end

	state.installed = {}
	state.built = {}
	state.updated = {}
	state.removed = {}
	if state.update_restart_timer then
		state.update_restart_timer:stop()
		state.update_restart_timer:close()
		state.update_restart_timer = nil
	end
	do_restart()
end
