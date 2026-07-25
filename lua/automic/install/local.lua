--- Symlink local/dev plugin directories into the vim.pack opt layout.
local M = {}

---@param name string
---@return string
function M.target(name)
	return vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. name
end

--- Ensure `name` under packpath is a symlink to `path`.
---@param name string
---@param path string
---@return boolean ok
---@return string? err
function M.link(name, path)
	if type(name) ~= "string" or name == "" then
		return false, "missing pack name"
	end
	if type(path) ~= "string" or path == "" then
		return false, "missing path"
	end
	path = vim.fs.normalize(path)
	if vim.fn.isdirectory(path) ~= 1 then
		return false, "path is not a directory: " .. path
	end

	local parent = vim.fn.stdpath("data") .. "/site/pack/core/opt"
	vim.fn.mkdir(parent, "p")
	local target = M.target(name)
	local uv = vim.uv

	local stat = uv.fs_lstat(target)
	if stat then
		if stat.type == "link" then
			local current = uv.fs_readlink(target)
			if current and vim.fs.normalize(current) == path then
				return true
			end
			local ok_rm, rm_err = uv.fs_unlink(target)
			if not ok_rm then
				return false, "failed to replace symlink: " .. tostring(rm_err)
			end
		else
			return false,
				"pack path already exists as a real directory (not a symlink): "
					.. target
					.. "\nRemove it manually or use a different spec.name before linking path = "
					.. path
		end
	end

	-- macOS/Linux: directory symlink. Windows: pass { dir = true } when available.
	local ok, err = uv.fs_symlink(path, target, { dir = true })
	if not ok then
		-- Older libuv may reject the options table; retry without.
		ok, err = uv.fs_symlink(path, target)
	end
	if not ok then
		return false, "symlink failed: " .. tostring(err)
	end
	require("automic.deps.healthy").invalidate(target)
	require("automic.deps.path").invalidate(name)
	return true
end

--- Remove a local symlink at the pack path (never deletes a real directory).
---@param name string
---@return boolean removed
function M.unlink(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local target = M.target(name)
	local uv = vim.uv
	local stat = uv.fs_lstat(target)
	if not stat or stat.type ~= "link" then
		return false
	end
	local ok = uv.fs_unlink(target)
	require("automic.deps.healthy").invalidate(target)
	require("automic.deps.path").invalidate(name)
	return ok and true or false
end

--- Link every registered plugin that declares `path`.
---@return string[] linked names
---@return string[] errors
function M.link_all()
	local Pack = _G.Pack
	local linked, errors = {}, {}
	for name, P in pairs(Pack.registry) do
		if type(P.path) == "string" and P.path ~= "" and not Pack.disabled[name] then
			local ok, err = M.link(name, P.path)
			if ok then
				linked[#linked + 1] = name
			else
				errors[#errors + 1] = name .. ": " .. tostring(err)
			end
		end
	end
	table.sort(linked)
	return linked, errors
end

--- Whether a vim.pack spec belongs to a local/path plugin (skip vim.pack.add/update).
---@param spec any
---@return boolean
function M.is_local_spec(spec)
	local Pack = _G.Pack
	local ok, name = pcall(Pack.parse, spec)
	if not ok then
		return false
	end
	local P = Pack.registry[name]
	return type(P) == "table" and type(P.path) == "string" and P.path ~= ""
end

--- Partition specs into remote (vim.pack) and local (symlink).
---@param specs table[]
---@return table[] remote
---@return table[] local_specs
function M.partition(specs)
	local remote, local_specs = {}, {}
	for _, spec in ipairs(specs) do
		if M.is_local_spec(spec) then
			local_specs[#local_specs + 1] = spec
		else
			remote[#remote + 1] = spec
		end
	end
	return remote, local_specs
end

return M
