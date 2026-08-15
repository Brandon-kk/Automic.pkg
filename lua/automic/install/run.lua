--- Sync registry, install plugins, batch-build, then restart automatically
---@param active_specs? table
---@param disabled_specs? table
return function(active_specs, disabled_specs)
	local Pack = _G.Pack
	local sort = require("automic.install.sort")
	local sync = require("automic.install.sync")
	local repair = require("automic.install.repair")
	local local_install = require("automic.install.local")
	local batch = require("automic.build.batch")
	local build_cmds = require("automic.build.cmds")
	local build_stamp = require("automic.build.stamp")
	local relaunch = require("automic.restart").relaunch
	local restart_state = require("automic.restart.state")
	active_specs = active_specs or Pack.active
	disabled_specs = disabled_specs or Pack.idle

	local stamp_path = require("automic.util.platform").state_path("pack-hooks-install.stamp")

	local function spec_key(spec)
		local name = Pack.parse(spec)
		local src = type(spec) == "table" and tostring(spec.src or spec[1] or name) or tostring(spec)
		local P = Pack.registry[name]
		local local_path = P and P.path or ""
		return name .. "\t" .. src .. "\t" .. tostring(local_path)
	end

	local function build_key(name, build)
		return name .. "\t" .. build_stamp.fingerprint(build)
	end

	local function fingerprint()
		local keys = {}
		for _, spec in ipairs(active_specs) do
			keys[#keys + 1] = "a:" .. spec_key(spec)
		end
		for _, spec in ipairs(disabled_specs) do
			keys[#keys + 1] = "i:" .. spec_key(spec)
		end
		for name, plugin in pairs(Pack.registry) do
			if plugin.build then
				keys[#keys + 1] = "b:" .. build_key(name, plugin.build)
			end
			if type(plugin.path) == "string" and plugin.path ~= "" then
				keys[#keys + 1] = "p:" .. name .. "\t" .. plugin.path
			end
		end
		table.sort(keys)
		return vim.fn.sha256(table.concat(keys, "\0"))
	end

	--- Avoid per-plugin git subprocesses on the unchanged startup path.
	local function dirs_present()
		local seen = {}
		local function check_name(name)
			if seen[name] then
				return true
			end
			seen[name] = true
			local dir = Pack.path(name)
			if not dir then
				return false
			end
			if vim.fn.isdirectory(dir) ~= 1 then
				return false
			end
			local git_dir = dir .. "/.git"
			if vim.fn.isdirectory(git_dir) == 1 then
				return vim.fn.filereadable(git_dir .. "/HEAD") == 1
			end
			if vim.fn.filereadable(git_dir) == 1 then
				return true
			end
			for _ in vim.fs.dir(dir) do
				return true
			end
			return false
		end
		for name in pairs(Pack.registry) do
			if not check_name(name) then
				return false
			end
		end
		for _, spec in ipairs(active_specs) do
			if not check_name(Pack.parse(spec)) then
				return false
			end
		end
		for _, spec in ipairs(disabled_specs) do
			if not check_name(Pack.parse(spec)) then
				return false
			end
		end
		return true
	end

	local function after_install(on_success, skipped_builds)
		local build_names = {}
		for name in pairs(build_cmds.all()) do
			if not Pack.disabled[name] and not (skipped_builds and skipped_builds[name]) then
				build_names[#build_names + 1] = name
			end
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
				restart_state.built[#restart_state.built + 1] = name
			end
			if on_success then
				on_success()
			end
			relaunch()
		end, build_names)
	end

	---@return table<string, boolean>
	local function missing_builds()
		local skipped = {}
		for name in pairs(build_cmds.all()) do
			if not Pack.disabled[name] and not Pack.available(name) then
				skipped[name] = true
			end
		end
		return skipped
	end

	local function has_pending_build()
		for name, build in pairs(build_cmds.all()) do
			if not Pack.disabled[name] then
				local dir = Pack.path(name)
				if not dir or not build_stamp.current(dir, build) then
					return true
				end
			end
		end
		return false
	end

	local function link_locals()
		local _, link_errs = local_install.link_all()
		if #link_errs > 0 then
			vim.notify("Local/dev plugin link failed:\n" .. table.concat(link_errs, "\n"), vim.log.levels.ERROR)
		end
	end

	local fp = fingerprint()
	local stamp_lines = vim.fn.filereadable(stamp_path) == 1 and vim.fn.readfile(stamp_path) or {}

	-- Fast path first: skip topological sort when declarations are unchanged.
	-- vim.pack.add(..., { load = false }) only registers packs for the session;
	-- load order is enforced later by :packadd / ensure.
	if stamp_lines[1] == fp and dirs_present() then
		link_locals()
		local remote_specs = local_install.partition(active_specs)
		if #remote_specs > 0 then
			pcall(vim.pack.add, remote_specs, { confirm = false, load = false })
		end
		if not has_pending_build() then
			return
		end
		after_install()
		return
	end

	local sorted = sort(active_specs)
	if not sorted then
		vim.notify("install aborted: dependency sort failed", vim.log.levels.ERROR)
		return
	end

	local remote_specs = local_install.partition(sorted)

	sync(active_specs, disabled_specs)
	repair()
	link_locals()
	if #remote_specs > 0 then
		local ok, err = pcall(vim.pack.add, remote_specs, { confirm = false, load = false })
		if not ok then
			vim.notify("Some plugins failed to install:\n" .. tostring(err), vim.log.levels.ERROR)
		end
	end
	after_install(function()
		local tmp = stamp_path .. ".tmp." .. tostring(vim.uv.os_getpid())
		vim.fn.writefile({ fp }, tmp)
		vim.uv.fs_rename(tmp, stamp_path)
	end, missing_builds())
end
