---@param dir string
---@return string
local function path_to_module_prefix(dir)
	return (dir:gsub("\\", "/"):gsub("/", "."))
end

---@param root string
---@param dir string
---@return boolean
local function is_descendant(root, dir)
	return dir:sub(1, #root + 1) == root .. "/"
end

---@param path string
---@return boolean
local function is_absolute(path)
	return path:match("^[/\\]") ~= nil or path:match("^%a:[/\\]") ~= nil
end

---@return string? root
local function lua_root()
	local root = vim.uv.fs_realpath(vim.fn.stdpath("config") .. "/lua")
	return root and vim.fs.normalize(root) or nil
end

---@param dir string
---@return string? real_dir
local function safe_dir(dir)
	local root = lua_root()
	local real_dir = vim.uv.fs_realpath(dir)
	if not root or not real_dir then
		return nil
	end
	real_dir = vim.fs.normalize(real_dir)
	return is_descendant(root, real_dir) and real_dir or nil
end

---@param config string
---@return string? dir
---@return string? prefix
return function(config)
	if config:find("[/\\]") then
		local dir = config
		if not is_absolute(dir) then
			dir = vim.fn.stdpath("config") .. "/lua/" .. dir
		end
		dir = safe_dir(dir)
		if not dir then
			vim.notify("Pack.boot: directory is outside config/lua or unavailable: " .. config, vim.log.levels.ERROR)
			return nil, nil
		end
		local rel = dir:sub(#lua_root() + 2)
		return dir, path_to_module_prefix(rel)
	end

	local prefix = config
	local dir = safe_dir(vim.fn.stdpath("config") .. "/lua/" .. prefix:gsub("%.", "/"))
	if not dir then
		vim.notify("Pack.boot: configuration directory does not exist or is outside config/lua: " .. prefix, vim.log.levels.ERROR)
		return nil, nil
	end
	return dir, prefix
end
