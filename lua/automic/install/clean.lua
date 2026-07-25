--- Remove on-disk packs that are not protected by the current registry.
---@param opts? { force?: boolean }
---@return string[] deleted
return function(opts)
	opts = opts or {}
	local Pack = _G.Pack
	local sync = require("automic.install.sync")
	local deleted = sync(Pack.active, Pack.idle, { force_prune = opts.force == true }) or {}

	if #deleted == 0 then
		vim.notify("PackClean: no orphaned plugins", vim.log.levels.INFO)
		return deleted
	end

	require("automic.restart").relaunch()
	return deleted
end
