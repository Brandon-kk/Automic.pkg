--- Resolve install path on packpath (prefer data/site/pack; session-cached)
local platform = require("automic.util.platform")
local cache = {}

local function invalidate(name)
	if name then
		cache[name] = nil
	else
		cache = {}
	end
end

local function listen()
	local Pack = _G.Pack
	if not Pack then
		return
	end
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.path then
		return
	end
	Pack._listeners.path = true
	vim.api.nvim_create_autocmd("PackChanged", {
		group = vim.api.nvim_create_augroup("PackPathCache", { clear = true }),
		callback = function(ev)
			local pkg = ev.data and ev.data.spec and ev.data.spec.name
			if pkg then
				invalidate(pkg)
			else
				invalidate()
			end
		end,
	})
end

---@param name string
---@return string?
local function resolve(name)
	listen()
	local Pack = _G.Pack
	local ok, parsed = pcall(Pack.parse, name)
	if not ok then
		return nil
	end
	name = parsed
	-- Defense in depth: never join names with separators into paths
	if name:find("[/\\]") or name == ".." or name == "." then
		return nil
	end
	local hit = cache[name]
	if hit ~= nil then
		return hit ~= false and hit or nil
	end

	-- Fast path: vim.pack default layout (includes links to local/dev dirs)
	local data_pack = platform.data_pack()
	for _, kind in ipairs({ "opt", "start" }) do
		local p = vim.fs.joinpath(data_pack, "core", kind, name)
		if vim.fn.isdirectory(p) == 1 then
			cache[name] = p
			return p
		end
	end

	-- Literal path lookup; avoid glob metacharacters
	local paths = {}
	local data_norm = platform.abspath(data_pack)
	for _, root in ipairs(vim.opt.packpath:get()) do
		for _, kind in ipairs({ "opt", "start" }) do
			local pattern = vim.fs.joinpath(root, "pack", "*", kind, name)
			local matches = vim.fn.glob(pattern, false, true)
			for _, p in ipairs(matches) do
				if vim.fs.basename(p) == name then
					paths[#paths + 1] = p
				end
			end
		end
	end
	if #paths == 0 then
		cache[name] = false
		return nil
	end
	for _, p in ipairs(paths) do
		if platform.abspath(p):find(data_norm, 1, true) then
			cache[name] = p
			return p
		end
	end
	cache[name] = paths[1]
	return paths[1]
end

return setmetatable({
	invalidate = invalidate,
}, {
	__call = function(_, name)
		return resolve(name)
	end,
})
