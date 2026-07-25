local require_mod = require("automic.boot.require_mod")

---@param dir string
---@param prefix string
---@return boolean ok
return function(dir, prefix)
	local failed = false
	local files = {}
	for name, ftype in vim.fs.dir(dir) do
		if ftype == "file" and name:match("%.lua$") then
			files[#files + 1] = name
		end
	end
	-- Load order is alphabetical (use numeric filename prefixes for priority)
	table.sort(files)
	for _, name in ipairs(files) do
		local mod = prefix .. "." .. name:gsub("%.lua$", "")
		if not require_mod(mod) then
			failed = true
		end
	end
	return not failed
end
