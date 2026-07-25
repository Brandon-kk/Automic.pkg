--- Built-in: attach Pack.utils/var lua_ls plugin (no external .luarc / no config edits)
---
--- Call only when Pack.boot():lsp() activates; do not eager-load vim.lsp.
local applied = false

---@return string
local function plugin_path()
	local src = debug.getinfo(1, "S").source
	if type(src) == "string" and src:sub(1, 1) == "@" then
		local here = vim.fs.normalize(src:sub(2))
		return vim.fs.normalize(vim.fs.dirname(here) .. "/../lsp_plugin/pack_utils.lua")
	end
	error("unable to resolve Automic.pkg lua_ls plugin path")
end

--- Trust only the built-in pack_utils path (write trusted; skip interactive prompt)
---@param path string
local function ensure_trusted(path)
	-- Only state dir; do not widen log/cache trust surface
	local dir = vim.fn.stdpath("state") .. "/lua-language-server"
	vim.fn.mkdir(dir, "p")
	local trusted = dir .. "/trusted"
	local existing = ""
	if vim.fn.filereadable(trusted) == 1 then
		existing = table.concat(vim.fn.readfile(trusted), "\n")
	end
	if not existing:find(path, 1, true) then
		local lines = {}
		if existing ~= "" then
			for line in (existing .. "\n"):gmatch("([^\n]*)\n") do
				if line ~= "" then
					lines[#lines + 1] = line
				end
			end
		end
		lines[#lines + 1] = path
		vim.fn.writefile(lines, trusted)
	end
end

--- Merge into vim.lsp.config("lua_ls"); safe to call repeatedly
return function()
	if applied then
		return
	end
	applied = true

	local path = plugin_path()
	ensure_trusted(path)

	local library = {
		vim.env.VIMRUNTIME,
		vim.fn.stdpath("config") .. "/lua",
	}
	for _, rtp in ipairs(vim.opt.runtimepath:get()) do
		if rtp:find("[/\\]site[/\\]pack[/\\]", 1) or rtp:find("[/\\]lazy[/\\]", 1) then
			library[#library + 1] = rtp
		end
	end

	vim.lsp.config("lua_ls", {
		-- No --develop: smaller LSP surface; trust via trusted + trustByClient
		cmd = { "lua-language-server" },
		init_options = {
			trustByClient = true,
		},
		settings = {
			Lua = {
				runtime = {
					version = "LuaJIT",
					plugin = { path },
				},
				diagnostics = {
					globals = { "vim", "Pack", "Snacks" },
				},
				workspace = {
					checkThirdParty = false,
					library = library,
				},
			},
		},
	})
end
