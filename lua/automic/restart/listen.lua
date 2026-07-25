local state = require("automic.restart.state")

---@param delay_ms integer
local function schedule_after_updates(delay_ms)
	if state.update_restart_timer then
		state.update_restart_timer:stop()
		state.update_restart_timer:close()
		state.update_restart_timer = nil
	end
	local timer = vim.uv.new_timer()
	if not timer then
		vim.schedule(function()
			require("automic.update.after_apply")()
		end)
		return
	end
	state.update_restart_timer = timer
	timer:start(
		delay_ms,
		0,
		vim.schedule_wrap(function()
			if state.update_restart_timer ~= timer then
				return
			end
			state.update_restart_timer = nil
			timer:stop()
			timer:close()
			require("automic.update.after_apply")()
		end)
	)
end

return function()
	local Pack = _G.Pack
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.restart then
		return
	end
	Pack._listeners.restart = true

	vim.api.nvim_create_autocmd("PackChanged", {
		group = vim.api.nvim_create_augroup("PackAutoRestart", { clear = true }),
		callback = function(ev)
			local data = ev.data
			if not (data and data.spec and data.spec.name) then
				return
			end
			if data.kind == "install" then
				state.installed[#state.installed + 1] = data.spec.name
			elseif data.kind == "update" then
				state.updated[#state.updated + 1] = data.spec.name
				-- Wait until the full update wave finishes, then build → restart.
				schedule_after_updates(400)
			elseif data.kind == "delete" then
				state.removed[#state.removed + 1] = data.spec.name
			end
		end,
	})
end
