local filter_targets = require("automic.update.filter")

--- Call vim.pack.update after filtering lock=true plugins and their dependencies.
--- Default shows the confirmation buffer; `force = true` applies immediately.
--- After updates are applied, builds run (same as install), then Neovim restarts.
---@param targets? string[]
---@param opts? table
return function(targets, opts)
	opts = opts or {}
	local filtered, skipped = filter_targets(targets)
	if #skipped > 0 then
		vim.notify("Skipped updates for locked plugins: " .. table.concat(skipped, ", "), vim.log.levels.INFO)
	end
	if #filtered == 0 then
		vim.notify("No plugins available to update (all are locked or the list is empty)", vim.log.levels.INFO)
		return nil
	end
	if opts.offline then
		return vim.pack.update(filtered, opts)
	end

	opts.force = opts.force == true
	return vim.pack.update(filtered, opts)
end
