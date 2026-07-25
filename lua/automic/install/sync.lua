--- Sync plugin registry: prune orphans and record disabled list.
--- Returns the list of deleted package names (may be empty).
---@param active_specs? table
---@param disabled_specs? table
---@param opts? { force_prune?: boolean }
---@return string[] deleted
return function(active_specs, disabled_specs, opts)
	local Pack = _G.Pack
	active_specs = active_specs or Pack.active
	disabled_specs = disabled_specs or {}

	for _, spec in ipairs(active_specs) do
		local name = Pack.parse(spec)
		Pack.disabled[name] = nil
	end

	for _, spec in ipairs(disabled_specs) do
		local name = Pack.parse(spec)
		Pack.disabled[name] = true
	end

	local protected = require("automic.deps.protect").protect()
	local pack_dir = vim.fn.stdpath("data") .. "/site/pack"
	local installed_plugins = {}
	local seen = {}

	if vim.fn.isdirectory(pack_dir) ~= 1 then
		return {}
	end

	for pkg_name, pkg_type in vim.fs.dir(pack_dir) do
		if pkg_type == "directory" and pkg_name:sub(1, 1) ~= "." then
			for _, type_dir in ipairs({ "start", "opt" }) do
				local dir = pack_dir .. "/" .. pkg_name .. "/" .. type_dir
				if vim.fn.isdirectory(dir) == 1 then
					for name, ftype in vim.fs.dir(dir) do
						if ftype == "directory" and name ~= "doc" and not seen[name] then
							seen[name] = true
							installed_plugins[#installed_plugins + 1] = name
						end
					end
				end
			end
		end
	end

	-- Empty registry ⇒ empty protect ⇒ every on-disk pack looks orphaned; refuse by default
	local force_prune = type(opts) == "table" and opts.force_prune == true
	if #installed_plugins > 0 and vim.tbl_isempty(Pack.registry) and not force_prune then
		vim.notify(
			"Pack.sync: registry is empty; orphan pruning was skipped to prevent accidental deletion.\n"
				.. "To remove every unregistered plugin, use: Pack.sync(nil, nil, { force_prune = true })"
				.. " or :PackClean!",
			vim.log.levels.ERROR
		)
		return {}
	end

	local to_delete = {}
	local kept_shared = {}

	for _, installed in ipairs(installed_plugins) do
		if not protected[installed] then
			if require("automic.deps.needed")(installed) then
				local dependents = require("automic.deps.protect").users(installed)
				kept_shared[#kept_shared + 1] = installed
					.. " (still used by "
					.. table.concat(dependents, ", ")
					.. ")"
			else
				to_delete[#to_delete + 1] = installed
			end
		end
	end

	if #kept_shared > 0 then
		vim.schedule(function()
			vim.notify(
				"Keeping shared dependencies: " .. table.concat(kept_shared, "; "),
				vim.log.levels.INFO
			)
		end)
	end

	if #to_delete > 0 then
		vim.notify("🧹 Clean Up Orphaned Plugins: " .. table.concat(to_delete, ", "), vim.log.levels.INFO)
		vim.pack.del(to_delete)
		local restart_state = require("automic.restart.state")
		local healthy = require("automic.deps.healthy")
		for _, name in ipairs(to_delete) do
			restart_state.removed[#restart_state.removed + 1] = name
			local dir = Pack.path(name)
			if dir then
				healthy.invalidate(dir)
			end
		end
	end

	return to_delete
end
