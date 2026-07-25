--- Drop cached Lua modules for a pack so post-update builds re-read on-disk sources.
---
--- Applies to every pack with a build (function / :Vim / shell), not a single plugin.
--- Plugins often freeze checkout metadata (git HEAD, paths, compiled artifact names)
--- at require time; building in the same session after vim.pack checkout would
--- otherwise run against stale module state, then stamp.write records the new HEAD.
---
--- Do not clear Pack.loaded / Pack.inited here: that would make module_loader treat
--- require() as a cold :load during build and recurse (loop or previous error).
--- Session restart after a successful build resets those flags.
local M = {}

---@param name string
---@param dir string
function M.modules(name, dir)
	local Pack = _G.Pack
	name = Pack.parse(name)
	dir = vim.fs.normalize(dir)
	local lua_root = dir .. "/lua"

	if vim.loader and vim.loader.reset then
		pcall(vim.loader.reset, dir)
		pcall(vim.loader.reset, lua_root)
	end

	local P = Pack.registry and Pack.registry[name]
	local root_mod = P and type(P.module) == "string" and P.module or nil
	local drop = {}

	for modname in pairs(package.loaded) do
		if type(modname) == "string" then
			local match = root_mod
				and (modname == root_mod or vim.startswith(modname, root_mod .. "."))
			if not match then
				local ok, path = pcall(package.searchpath, modname, package.path)
				if ok and type(path) == "string" then
					path = vim.fs.normalize(path)
					match = path == lua_root or vim.startswith(path, lua_root .. "/")
				end
			end
			if match then
				drop[#drop + 1] = modname
			end
		end
	end

	for _, modname in ipairs(drop) do
		package.loaded[modname] = nil
	end
end

return M
