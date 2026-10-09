--- Drop cached Lua modules for a pack so post-update builds re-read on-disk sources.
---
--- Applies to every pack with a build (function / :Vim / shell), not a single plugin.
--- Plugins often freeze checkout metadata (git HEAD, paths, compiled artifact names)
--- at require time; building in the same session after vim.pack checkout would
--- otherwise run against stale module state, then stamp.write records the new HEAD.
---
--- Cascade: dependency packs that were themselves updated this session (fresh mark,
--- set by listen on PackChanged) are dropped too — new plugin code must not run
--- against stale dependency modules (e.g. blink.cmp vs an updated blink.lib).
--- Un-updated shared deps (devicons, lspkind, …) stay loaded for other plugins.
---
--- Do not clear Pack.loaded / Pack.inited here: that would make module_loader treat
--- require() as a cold :load during build and recurse (loop or previous error).
--- Session restart after a successful build resets those flags.
local fresh = require("automic.build.fresh")

local M = {}

---@param name string
---@param dir string
local function drop_modules(name, dir)
	local Pack = _G.Pack
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

--- Dependency packs updated in this session, transitively (fresh-marked only).
---@param root_name string
---@return { name: string, dir: string }[]
local function updated_deps(root_name)
	local Pack = _G.Pack
	local resolve_path = require("automic.deps.path")
	local seen = { [root_name] = true }
	local queue = { root_name }
	local out = {}
	while #queue > 0 do
		local name = table.remove(queue)
		local P = Pack.registry and Pack.registry[name]
		local deps = P and type(P.dependencies) == "table" and P.dependencies or nil
		if deps then
			for _, dep in ipairs(deps) do
				local ok, dep_name = pcall(Pack.parse, dep)
				if ok and type(dep_name) == "string" and dep_name ~= "" and not seen[dep_name] then
					seen[dep_name] = true
					queue[#queue + 1] = dep_name
					if not Pack.disabled[dep_name] and fresh.pending(dep_name) then
						local dep_dir = resolve_path(dep_name)
						if dep_dir then
							out[#out + 1] = { name = dep_name, dir = dep_dir }
						end
					end
				end
			end
		end
	end
	return out
end

---@param name string
---@param dir string
function M.modules(name, dir)
	local Pack = _G.Pack
	name = Pack.parse(name)
	drop_modules(name, dir)
	for _, item in ipairs(updated_deps(name)) do
		drop_modules(item.name, item.dir)
		fresh.consume(item.name)
	end
end

return M
