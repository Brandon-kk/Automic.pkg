--- Load Pack plugins when `:colorscheme` targets a registered scheme name.
local M = {}

---@param schemes string|string[]|true|nil
---@param pack_name string
---@param module? string
---@return string[]
function M.normalize(schemes, pack_name, module)
	if schemes == true then
		local out = { pack_name }
		if type(module) == "string" and module ~= "" and module ~= pack_name then
			out[#out + 1] = module
		end
		return out
	end
	if type(schemes) == "string" then
		return schemes ~= "" and { schemes } or {}
	end
	if type(schemes) ~= "table" then
		return {}
	end
	local out = {}
	for _, item in ipairs(schemes) do
		if type(item) == "string" and item ~= "" then
			out[#out + 1] = item
		end
	end
	return out
end

--- Remove a pack from all scheme indexes (re-register / retarget).
---@param name string
function M.unbind(name)
	local Pack = _G.Pack
	local index = Pack._colorschemes
	if type(index) ~= "table" then
		return
	end
	for scheme, list in pairs(index) do
		if type(list) == "table" then
			local next_list = {}
			for _, item in ipairs(list) do
				if item ~= name then
					next_list[#next_list + 1] = item
				end
			end
			if #next_list == 0 then
				index[scheme] = nil
			else
				index[scheme] = next_list
			end
		end
	end
end

---@param name string pack name
---@param schemes string[]
function M.bind(name, schemes)
	local Pack = _G.Pack
	Pack._colorschemes = Pack._colorschemes or {}
	M.unbind(name)
	for _, scheme in ipairs(schemes) do
		local list = Pack._colorschemes[scheme]
		if not list then
			list = {}
			Pack._colorschemes[scheme] = list
		end
		list[#list + 1] = name
	end
end

function M.setup()
	local Pack = _G.Pack
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.colorscheme then
		return
	end
	Pack._listeners.colorscheme = true
	Pack._colorschemes = Pack._colorschemes or {}

	vim.api.nvim_create_autocmd("ColorSchemePre", {
		group = vim.api.nvim_create_augroup("PackColorscheme", { clear = true }),
		desc = "Pack: load plugin providing the colorscheme",
		callback = function(ev)
			local scheme = ev.match
			if type(scheme) ~= "string" or scheme == "" then
				return
			end
			local names = Pack._colorschemes[scheme]
			if not names or #names == 0 then
				return
			end
			local ensure = require("automic.load.ensure")
			for _, name in ipairs(names) do
				ensure(name, true)
			end
		end,
	})
end

return M
