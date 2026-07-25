--- Run plugin build (function / :Vim command / shell)
---
--- opts.quiet: reserved (batch passes it; per-plugin start/success are always silent)
--- opts.no_retry: do not auto-retry on failure
local stamp = require("automic.build.stamp")
local retry = require("automic.build.retry")
local failed = require("automic.build.failed")
local fresh = require("automic.build.fresh")
local unload = require("automic.build.unload")
local BUILD_TIMEOUT_MS = 300000

--- After install/update/force rebuild, drop this pack's cached Lua modules so any
--- build path (function or :Vim) re-reads post-checkout sources. Shell builds still
--- consume the mark so it cannot leak into a later ensure/function build.
---@param name string
---@param dir string
local function prepare_fresh(name, dir)
	if fresh.consume(name) then
		unload.modules(name, dir)
	end
end

---@param name string
---@param build_cmd string|string[]|function
---@param on_finish? fun(ok: boolean, err?: any)
---@param opts? { quiet?: boolean, no_retry?: boolean }
return function(name, build_cmd, on_finish, opts)
	opts = opts or {}
	local no_retry = opts.no_retry == true or on_finish ~= nil

	local Pack = _G.Pack
	name = Pack.parse(name)
	if Pack.disabled[name] or not build_cmd then
		if on_finish then
			on_finish(false, "disabled or missing build")
		end
		return
	end
	if Pack.building[name] or retry.pending(name) then
		if on_finish then
			on_finish(false, "already building")
		end
		return
	end
	local dir = Pack.path(name)
	if not dir then
		if on_finish then
			on_finish(false, "missing path")
		end
		return
	end
	Pack.building[name] = true

	-- vim.system on_exit is a fast event; vim.fn (sha256/writefile/…) must be scheduled
	local function finish(ok, err_msg)
		vim.schedule(function()
			Pack.building[name] = false
			if ok then
				retry.reset(name)
				failed.remove(name)
				local P = Pack.registry[name]
				stamp.write(dir, build_cmd)
				-- Per-plugin success is silent; batch reports overall "Build success"
				vim.api.nvim_exec_autocmds("User", {
					pattern = "PackBuildDone",
					data = { name = name },
				})
				if on_finish then
					on_finish(true)
				end
			else
				-- On failure: no stamp (clear if any); next boot still rebuilds via missing stamp
				stamp.clear(dir)
				failed.add(name)
				vim.notify(name .. " build failed: " .. tostring(err_msg), vim.log.levels.ERROR)
				if on_finish then
					on_finish(false, err_msg)
				elseif not no_retry then
					retry.schedule(name, build_cmd)
				end
			end
		end)
	end

	if type(build_cmd) == "function" then
		vim.schedule(function()
			pcall(vim.cmd.packadd, name)
			prepare_fresh(name, dir)
			local ok, err = pcall(build_cmd, name, dir)
			finish(ok, err)
		end)
		return
	end

	local is_vim_cmd = false
	local vim_cmd_str = ""

	if type(build_cmd) == "string" and build_cmd:sub(1, 1) == ":" then
		is_vim_cmd = true
		vim_cmd_str = build_cmd:sub(2)
	elseif type(build_cmd) == "table" and type(build_cmd[1]) == "string" and build_cmd[1]:sub(1, 1) == ":" then
		is_vim_cmd = true
		vim_cmd_str = build_cmd[1]:sub(2)
	end

	if is_vim_cmd then
		vim.schedule(function()
			pcall(vim.cmd.packadd, name)
			prepare_fresh(name, dir)
			local ok, err = pcall(vim.cmd, vim_cmd_str)
			finish(ok, err)
		end)
	else
		local final_cmd = {}
		if type(build_cmd) == "string" then
			if build_cmd:match("^%s*$") then
				Pack.building[name] = false
				stamp.clear(dir)
				failed.add(name)
				vim.notify(name .. " build failed: empty build rejected", vim.log.levels.ERROR)
				if on_finish then
					on_finish(false, "empty build")
				end
				return
			end
			if build_cmd:find('["\']') then
				Pack.building[name] = false
				stamp.clear(dir)
				failed.add(name)
				vim.notify(
					name .. " build failed: quoted shell strings must use string[] form",
					vim.log.levels.ERROR
				)
				if on_finish then
					on_finish(false, "quoted shell string")
				end
				return
			end
			for word in build_cmd:gmatch("%S+") do
				table.insert(final_cmd, word)
			end
		else
			for i, word in ipairs(build_cmd) do
				if type(word) ~= "string" then
					Pack.building[name] = false
					stamp.clear(dir)
					failed.add(name)
					vim.notify(name .. " build failed: argv[" .. i .. "] must be string", vim.log.levels.ERROR)
					if on_finish then
						on_finish(false, "invalid argv")
					end
					return
				end
			end
			final_cmd = build_cmd
		end
		if type(final_cmd) ~= "table" or #final_cmd == 0 or type(final_cmd[1]) ~= "string" then
			Pack.building[name] = false
			stamp.clear(dir)
			failed.add(name)
			vim.notify(name .. " build failed: invalid shell argv", vim.log.levels.ERROR)
			if on_finish then
				on_finish(false, "invalid argv")
			end
			return
		end
		-- Shell has its own process; still consume fresh + clear Lua caches so a later
		-- ensure/function build in this session cannot see a leftover mark / stale modules.
		prepare_fresh(name, dir)
		vim.system(final_cmd, { cwd = dir, timeout = BUILD_TIMEOUT_MS }, function(out)
			if out.code == 0 then
				finish(true)
			else
				finish(false, out.stderr or "Unknown Error")
			end
		end)
	end
end
