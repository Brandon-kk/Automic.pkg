--- Detect and remove registered plugins with incomplete git repos (e.g. interrupted clone)
local healthy = require("automic.deps.healthy")

local function repair()
	local Pack = _G.Pack

	if vim.tbl_isempty(Pack.registry) and vim.tbl_isempty(Pack.active) then
		return
	end

	local names = {}
	for name in pairs(Pack.registry) do
		names[name] = true
	end
	for _, spec in ipairs(Pack.active) do
		names[Pack.parse(spec)] = true
	end
	for _, spec in ipairs(Pack.idle) do
		names[Pack.parse(spec)] = true
	end

	local to_delete = {}

	for name in pairs(names) do
		local dir = Pack.path(name)
		if dir and vim.fn.isdirectory(dir) == 1 then
			local git_path = dir .. "/.git"
			local has_git = vim.fn.isdirectory(git_path) == 1 or vim.fn.filereadable(git_path) == 1
			-- Only remove broken git clones; keep non-git local packages
			if has_git and not healthy.healthy(dir) then
				to_delete[#to_delete + 1] = name
				healthy.invalidate(dir)
			end
		end
	end

	if #to_delete == 0 then
		return
	end

	vim.notify("🔧 Removing incomplete plugins: " .. table.concat(to_delete, ", "), vim.log.levels.WARN)
	vim.pack.del(to_delete)
end

return repair
