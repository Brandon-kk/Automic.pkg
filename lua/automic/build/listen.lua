--- Register build; PackChanged only clears stamp — batch runs after install
local stamp = require("automic.build.stamp")
local cmds = require("automic.build.cmds")
local fresh = require("automic.build.fresh")

---@param name string
---@param build string|string[]|function
return function(name, build)
	local Pack = _G.Pack
	name = Pack.parse(name)
	if Pack.disabled[name] or not build then
		cmds.set(name, nil)
		return
	end
	cmds.set(name, build)

	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.build then
		return
	end
	Pack._listeners.build = true

	vim.api.nvim_create_autocmd("PackChanged", {
		group = vim.api.nvim_create_augroup("PackBuildListen", { clear = true }),
		callback = function(ev)
			local data = ev.data
			if not data or not data.spec or not data.spec.name then
				return
			end
			if data.kind == "update" or data.kind == "install" then
				-- Force the next install pass to run the unified post-update build batch.
				pcall(vim.fn.delete, require("automic.util.platform").state_path("pack-hooks-install.stamp"))
				if cmds.get(data.spec.name) then
					stamp.clear(data.path)
					-- Any pack with build: same-session require()/commands may still
					-- hold pre-checkout module state; force a fresh load before build.
					fresh.mark(data.spec.name)
				end
			end
		end,
	})
end
