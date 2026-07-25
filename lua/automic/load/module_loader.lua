--- Auto-load a Pack-scheduled plugin when its Lua module is required.
local M = {}

--- Resolve pack for `modname` via exact map, then parent dotted prefixes.
--- O(segments) hash lookups — not O(#registered modules).
---@param modname string
---@return string|nil pack_name
local function resolve(modname)
	local Pack = _G.Pack
	local modules = Pack.modules
	if type(modules) ~= "table" or type(modname) ~= "string" or modname == "" then
		return nil
	end
	local direct = modules[modname]
	if direct then
		return direct
	end
	-- require("flash.jump.foo") → try "flash.jump", then "flash"
	local cur = modname
	while true do
		local parent = cur:match("^(.*)%.[^%.]+$")
		if not parent then
			return nil
		end
		local hit = modules[parent]
		if hit then
			return hit
		end
		cur = parent
	end
end

function M.setup()
	local Pack = _G.Pack
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.module_loader then
		return
	end
	Pack._listeners.module_loader = true
	Pack.modules = Pack.modules or {}

	---@param modname string
	---@return function|nil
	local function loader(modname)
		local name = resolve(modname)
		if not name then
			return nil
		end
		-- Already available on rtp / currently loading via :load run() → fall through.
		-- During build, packadd already put the pack on rtp; do not re-enter :load.
		if Pack.loaded[name] or Pack.loading[name] or Pack.inited[name] or Pack.building[name] then
			return nil
		end
		if Pack.disabled[name] or not (Pack._runners and Pack._runners[name]) then
			return nil
		end
		return function()
			local ensure = require("automic.load.ensure")
			if not ensure(name, true) then
				error("Pack.module_loader: failed to load " .. name .. " for require('" .. modname .. "')", 0)
			end
			package.loaded[modname] = nil
			return require(modname)
		end
	end

	-- After preload, before path search — so packadd can put files on rtp first.
	table.insert(package.loaders, 2, loader)
end

return M
