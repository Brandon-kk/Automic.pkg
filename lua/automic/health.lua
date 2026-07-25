--- :PackHealth — local environment and declaration diagnostics (no network).
local M = {}

---@class Pack.HealthItem
---@field name string
---@field level "ok"|"warn"|"error"|"info"
---@field msg string

---@param items Pack.HealthItem[]
---@param name string
---@param level Pack.HealthItem["level"]
---@param msg string
local function add(items, name, level, msg)
	items[#items + 1] = { name = name, level = level, msg = msg }
end

---@param names? string[]
---@return Pack.HealthItem[]
function M.collect(names)
	local Pack = _G.Pack
	local items = {}
	local filter
	if type(names) == "table" and #names > 0 then
		filter = {}
		for _, n in ipairs(names) do
			local ok, parsed = pcall(Pack.parse, n)
			if ok then
				filter[parsed] = true
			end
		end
	end

	-- Environment
	local ver = vim.version()
	local ver_ok = vim.fn.has("nvim-0.12") == 1
	add(
		items,
		"neovim",
		ver_ok and "ok" or "error",
		string.format(
			"Neovim %d.%d.%d (Automic.pkg requires 0.12+)%s",
			ver.major,
			ver.minor,
			ver.patch,
			ver_ok and "" or " — upgrade required"
		)
	)

	local git = vim.fn.executable("git") == 1
	add(items, "git", git and "ok" or "error", git and "git executable found" or "git not found on PATH")

	local packadd_ok = vim.fn.exists(":packadd") == 2
	add(items, "packadd", packadd_ok and "ok" or "error", packadd_ok and ":packadd available" or ":packadd missing")

	local lockfile = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
	if vim.fn.filereadable(lockfile) == 1 then
		add(items, "vim.pack-lockfile", "info", "Found native lockfile: " .. lockfile)
	else
		add(
			items,
			"vim.pack-lockfile",
			"info",
			"No nvim-pack-lock.json yet (created by vim.pack after installs)"
		)
	end

	local booted = Pack._booted == true
	add(
		items,
		"boot",
		booted and "ok" or "warn",
		booted and "Pack.boot():run() completed this session" or "Pack.boot():run() has not completed (or skipped)"
	)

	local dev_root = vim.g.automic_dev_path
	if type(dev_root) == "string" and dev_root ~= "" then
		local expanded = vim.fs.normalize(vim.fn.expand(dev_root))
		local exists = vim.fn.isdirectory(expanded) == 1
		add(
			items,
			"automic_dev_path",
			exists and "ok" or "warn",
			exists and ("vim.g.automic_dev_path → " .. expanded) or ("vim.g.automic_dev_path missing: " .. expanded)
		)
	else
		add(items, "automic_dev_path", "info", "vim.g.automic_dev_path unset (optional; used by dev = true)")
	end

	-- Module collisions (scan registry; Pack.modules only keeps the last owner)
	local by_module = {}
	for pack_name, P in pairs(Pack.registry) do
		if type(P.module) == "string" and P.module ~= "" then
			by_module[P.module] = by_module[P.module] or {}
			by_module[P.module][#by_module[P.module] + 1] = pack_name
		end
	end

	local names_list = {}
	for name, _ in pairs(Pack.registry) do
		if not filter or filter[name] then
			names_list[#names_list + 1] = name
		end
	end
	table.sort(names_list)

	if #names_list == 0 then
		if filter then
			add(items, "registry", "warn", "No matching plugins for the given name(s)")
		else
			add(items, "registry", "warn", "No plugins in Pack.registry (load your declaration configs first)")
		end
		return items
	end

	for _, name in ipairs(names_list) do
		local P = Pack.registry[name]
		if Pack.disabled[name] or P.disabled then
			add(items, name, "info", "idle (cond disabled) — not installed/loaded by Automic")
		else
			local dir = Pack.path(name)
			local available = Pack.available(name)
			if type(P.path) == "string" and P.path ~= "" then
				if vim.fn.isdirectory(P.path) ~= 1 then
					add(items, name, "error", "path missing: " .. P.path)
				elseif not dir then
					add(items, name, "warn", "local path set but not linked into packpath yet (run Pack.boot / install)")
				elseif available then
					add(items, name, "ok", "local path linked → " .. P.path)
				else
					add(items, name, "warn", "local link present but not healthy: " .. tostring(dir))
				end
			elseif available then
				local bits = { "installed at " .. tostring(dir) }
				if P.lock then
					bits[#bits + 1] = "lock=true (skipped by :PackUpdate)"
				end
				if P.spec and P.spec.version ~= nil then
					bits[#bits + 1] = "version pinned"
				end
				-- Automic.pkg is packadd'd as the manager itself; it has no :load/:lazy runner.
				local is_self = name == "Automic.pkg"
				if not is_self and not (Pack._runners and Pack._runners[name]) then
					bits[#bits + 1] = "no :load/:lazy scheduled yet"
					add(items, name, "warn", table.concat(bits, "; "))
				else
					if is_self then
						bits[#bits + 1] = "manager (packadd; no :load/:lazy needed)"
					end
					add(items, name, "ok", table.concat(bits, "; "))
				end
			else
				add(items, name, "error", "not installed / unhealthy (missing under packpath)")
			end

			if type(P.module) == "string" and P.module ~= "" then
				local owners = by_module[P.module]
				if owners and #owners > 1 then
					add(
						items,
						name,
						"warn",
						"module '" .. P.module .. "' also claimed by: " .. table.concat(owners, ", ")
					)
				end
			end

			if P.build then
				local build_stamp = require("automic.build.stamp")
				local pdir = Pack.path(name)
				if pdir and not build_stamp.current(pdir, P.build) then
					add(items, name, "warn", "build stamp stale or missing — needs rebuild")
				end
			end
		end
	end

	return items
end

---@param level Pack.HealthItem["level"]
---@return integer
local function level_rank(level)
	if level == "error" then
		return 1
	end
	if level == "warn" then
		return 2
	end
	if level == "ok" then
		return 3
	end
	return 4
end

--- Open a fullscreen health report with level colors.
---@param names? string[]
function M.run(names)
	local items = M.collect(names)
	local lines = {
		"PackHealth",
		"==========",
		"",
		"Local diagnostics only (no network).",
		"Automic lock=true ≠ vim.pack nvim-pack-lock.json — see :help Pack.register()",
		"",
	}

	---@type { line: integer, level: string }[]
	local row_meta = {}

	local counts = { ok = 0, warn = 0, error = 0, info = 0 }
	table.sort(items, function(a, b)
		local ra, rb = level_rank(a.level), level_rank(b.level)
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)

	for _, item in ipairs(items) do
		counts[item.level] = (counts[item.level] or 0) + 1
		local tag = string.upper(item.level)
		lines[#lines + 1] = string.format("[%s] %s: %s", tag, item.name, item.msg)
		row_meta[#row_meta + 1] = { line = #lines - 1, level = item.level }
	end

	lines[#lines + 1] = ""
	local summary_line = string.format(
		"Summary: %d ok, %d warn, %d error, %d info",
		counts.ok,
		counts.warn,
		counts.error,
		counts.info
	)
	lines[#lines + 1] = summary_line
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Press q to close"

	local hl = {
		error = "DiagnosticError",
		warn = "DiagnosticWarn",
		ok = "DiagnosticOk",
		info = "DiagnosticInfo",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.bo[buf].filetype = "packhealth"
	vim.bo[buf].textwidth = 0

	-- Full-screen tab (not a short split).
	vim.cmd("tabnew")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].list = false
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true
	vim.wo[win].colorcolumn = ""

	local ns = vim.api.nvim_create_namespace("PackHealth")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	-- Title
	vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 1, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 3, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 4, 0, -1)

	for _, meta in ipairs(row_meta) do
		local group = hl[meta.level] or "Normal"
		local line = vim.api.nvim_buf_get_lines(buf, meta.line, meta.line + 1, false)[1] or ""
		local tag_end = line:find("]", 1, true) or 0
		-- Color the [LEVEL] tag
		vim.api.nvim_buf_add_highlight(buf, ns, group, meta.line, 0, tag_end)
		-- Color the pack name (between "] " and ":")
		local name_start = tag_end + 1
		local colon = line:find(":", name_start, true)
		if colon then
			vim.api.nvim_buf_add_highlight(buf, ns, "Identifier", meta.line, name_start, colon - 1)
			vim.api.nvim_buf_add_highlight(buf, ns, group, meta.line, colon, -1)
		else
			vim.api.nvim_buf_add_highlight(buf, ns, group, meta.line, name_start, -1)
		end
	end

	vim.api.nvim_buf_add_highlight(buf, ns, "Title", #lines - 3, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Comment", #lines - 1, 0, -1)

	vim.keymap.set("n", "q", function()
		if vim.fn.tabpagenr("$") > 1 then
			vim.cmd("tabclose")
		else
			vim.cmd("bdelete!")
		end
	end, { buffer = buf, nowait = true, silent = true, desc = "Close PackHealth" })

	local summary = string.format(
		"PackHealth: %d ok, %d warn, %d error",
		counts.ok,
		counts.warn,
		counts.error
	)
	local level = counts.error > 0 and vim.log.levels.ERROR
		or (counts.warn > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
	vim.notify(summary, level)
end

return M
