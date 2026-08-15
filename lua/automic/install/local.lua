--- Link local/dev plugin directories into the vim.pack opt layout.
--- One mechanism per OS — same Pack API, no fallback chains.
local platform = require("automic.util.platform")

local M = {}

---@param name string
---@return string
function M.target(name)
	return platform.data_pack("core", "opt", name)
end

--- Create the platform directory link (exactly one strategy; no retries).
--- Windows: junction. macOS / Linux: directory symlink.
---@param path string absolute source directory
---@param target string absolute link path
---@return boolean ok
---@return string? err
local function link_dir(path, target)
	local uv = vim.uv
	path, target = platform.abspath(path), platform.abspath(target)
	local opts = platform.is_windows() and { junction = true } or { dir = true }
	local ok, err = uv.fs_symlink(path, target, opts)
	if not ok then
		return false, tostring(err)
	end
	return true
end

--- Whether `target` is a directory link Automic owns (symlink or junction).
---@param target string
---@return boolean
local function is_pack_link(target)
	local stat = vim.uv.fs_lstat(target)
	return stat ~= nil and stat.type == "link"
end

--- Ensure `name` under packpath is a link to `path`.
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
	path = platform.abspath(path)
	if vim.fn.isdirectory(path) ~= 1 then
		return false, "path is not a directory: " .. path
	end

	local parent = platform.data_pack("core", "opt")
	vim.fn.mkdir(parent, "p")
	local target = platform.abspath(M.target(name))
	local uv = vim.uv

	if is_pack_link(target) then
		local current = uv.fs_readlink(target)
		if current and platform.same_path(current, path) then
			return true
		end
		local ok_rm, rm_err = uv.fs_unlink(target)
		if not ok_rm then
			return false, "failed to replace link: " .. tostring(rm_err)
		end
	elseif uv.fs_lstat(target) then
		return false,
			"pack path already exists as a real directory (not a link): "
				.. target
				.. "\nRemove it manually or use a different spec.name before linking path = "
				.. path
	end

	local ok, err = link_dir(path, target)
	if not ok then
		return false, "link failed: " .. tostring(err)
	end
	require("automic.deps.healthy").invalidate(target)
	require("automic.deps.path").invalidate(name)
	return true
end

--- Remove a local link at the pack path (never deletes a real directory).
---@param name string
---@return boolean removed
function M.unlink(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local target = M.target(name)
	if not is_pack_link(target) then
		return false
	end
	local ok = vim.uv.fs_unlink(target)
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

--- Partition specs into remote (vim.pack) and local (link).
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
