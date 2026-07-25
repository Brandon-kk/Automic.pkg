--- Declarative core-configuration helpers used by Pack.boot().
local M = {}

---@param value table|string
---@param method string
---@return table|nil
local function resolve(value, method)
	if type(value) == "table" then
		return value
	end
	if type(value) ~= "string" then
		vim.notify("Pack.boot:" .. method .. ": expected a table or module path", vim.log.levels.ERROR)
		return nil
	end

	local ok, result = pcall(require, value)
	if not ok then
		vim.notify("Pack.boot:" .. method .. ": failed to load module " .. value .. "\n" .. tostring(result), vim.log.levels.ERROR)
		return nil
	end
	if type(result) ~= "table" then
		vim.notify("Pack.boot:" .. method .. ": module " .. value .. " must return a table", vim.log.levels.ERROR)
		return nil
	end
	return result
end

---@param pattern string|string[]|nil
---@param ft string
---@return boolean
local function filetype_matches(pattern, ft)
	if ft == nil or ft == "" then
		return false
	end
	if pattern == nil then
		return true
	end
	local pats = type(pattern) == "string" and { pattern } or pattern
	if type(pats) ~= "table" then
		return false
	end
	for _, pat in ipairs(pats) do
		if pat == "*" or pat == ft then
			return true
		end
	end
	return false
end

---@param pattern string|string[]|nil
---@param name string
---@return boolean
local function name_matches(pattern, name)
	if pattern == nil then
		return true
	end
	local pats = type(pattern) == "string" and { pattern } or pattern
	if type(pats) ~= "table" then
		return false
	end
	for _, pat in ipairs(pats) do
		if pat == "*" then
			return true
		end
		local ok, reg = pcall(vim.fn.glob2regpat, pat)
		if ok and type(reg) == "string" and vim.fn.match(name, reg) >= 0 then
			return true
		end
	end
	return false
end

---@param mode string|string[]
---@param lhs string
---@param rhs any
---@param map_opts table
---@param buf integer
local function set_buf_map(mode, lhs, rhs, map_opts, buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local o = vim.tbl_extend("force", {}, map_opts, { buffer = buf })
	local ok_set, set_err = pcall(vim.keymap.set, mode, lhs, rhs, o)
	if not ok_set then
		vim.notify(
			"Pack.boot:keys: failed to set " .. lhs .. "\n" .. tostring(set_err),
			vim.log.levels.ERROR
		)
	end
end

---@class Pack.BootKeyRule
---@field event string|string[]
---@field pattern string|string[]|nil
---@field mode string|string[]
---@field lhs string
---@field rhs any
---@field map_opts table

--- One-pass backfill for all event-gated key rules (avoids O(rules×bufs) rescans).
---@param rules Pack.BootKeyRule[]
local function backfill_all(rules)
	if #rules == 0 then
		return
	end

	local ft_rules, lsp_rules, read_rules, enter_rules, enter_ui_rules, color_rules =
		{}, {}, {}, {}, {}, {}

	for _, rule in ipairs(rules) do
		local events = type(rule.event) == "string" and { rule.event } or rule.event
		if type(events) == "table" then
			for _, ev in ipairs(events) do
				if ev == "FileType" then
					ft_rules[#ft_rules + 1] = rule
				elseif ev == "LspAttach" then
					lsp_rules[#lsp_rules + 1] = rule
				elseif ev == "BufRead" or ev == "BufReadPost" or ev == "BufNewFile" then
					read_rules[#read_rules + 1] = rule
				elseif ev == "BufEnter" or ev == "BufWinEnter" or ev == "BufAdd" then
					enter_rules[#enter_rules + 1] = rule
				elseif ev == "VimEnter" or ev == "UIEnter" then
					enter_ui_rules[#enter_ui_rules + 1] = rule
				elseif ev == "ColorScheme" or ev == "ColorSchemePre" then
					color_rules[#color_rules + 1] = rule
				end
			end
		end
	end

	local ui_ready = vim.v.vim_did_enter == 1 or #vim.api.nvim_list_uis() > 0
	local bufs = vim.api.nvim_list_bufs()

	for _, buf in ipairs(bufs) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local ft = vim.bo[buf].filetype
			local name = vim.api.nvim_buf_get_name(buf)
			local filelike = name ~= "" and vim.bo[buf].buftype == ""

			for _, rule in ipairs(ft_rules) do
				if filetype_matches(rule.pattern, ft) then
					set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, buf)
				end
			end

			if filelike then
				for _, rule in ipairs(read_rules) do
					if name_matches(rule.pattern, name) then
						set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, buf)
					end
				end
				for _, rule in ipairs(enter_rules) do
					if name_matches(rule.pattern, name) then
						set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, buf)
					end
				end
			end

			if ui_ready then
				for _, rule in ipairs(enter_ui_rules) do
					if name_matches(rule.pattern, name) then
						set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, buf)
					end
				end
			end
		end
	end

	if #lsp_rules > 0 and vim.lsp and vim.lsp.get_clients then
		local seen = {}
		for _, client in ipairs(vim.lsp.get_clients()) do
			for _, buf in ipairs(vim.lsp.get_buffers_by_client_id(client.id) or {}) do
				if not seen[buf] and vim.api.nvim_buf_is_valid(buf) then
					seen[buf] = true
					local ft = vim.bo[buf].filetype
					for _, rule in ipairs(lsp_rules) do
						-- LspAttach autocmd pattern matches filetype.
						if filetype_matches(rule.pattern, ft) then
							set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, buf)
						end
					end
				end
			end
		end
	end

	if #color_rules > 0 and type(vim.g.colors_name) == "string" and vim.g.colors_name ~= "" then
		local cur = vim.api.nvim_get_current_buf()
		for _, rule in ipairs(color_rules) do
			local ok_pat = true
			if rule.pattern ~= nil then
				ok_pat = false
				local pats = type(rule.pattern) == "string" and { rule.pattern } or rule.pattern
				if type(pats) == "table" then
					for _, pat in ipairs(pats) do
						if pat == "*" or pat == vim.g.colors_name then
							ok_pat = true
							break
						end
					end
				end
			end
			if ok_pat then
				-- Align with a single ColorScheme fire: bind current buffer only.
				set_buf_map(rule.mode, rule.lhs, rule.rhs, rule.map_opts, cur)
			end
		end
	end
end

---@param entries table|string
function M.keys(entries)
	entries = resolve(entries, "keys")
	if not entries then
		return
	end

	local group = vim.api.nvim_create_augroup("PackBootKeys", { clear = true })
	---@type Pack.BootKeyRule[]
	local pending = {}

	for _, entry in ipairs(entries) do
		local mode, lhs, rhs, opts = entry[1], entry[2], entry[3], entry[4]
		if mode == nil or type(lhs) ~= "string" or rhs == nil then
			vim.notify("Pack.boot:keys: each entry must be { mode, lhs, rhs, opts? }", vim.log.levels.ERROR)
		else
			opts = type(opts) == "table" and vim.tbl_extend("force", {}, opts) or {}
			local event = opts.event
			local pattern = opts.pattern
			local once = opts.once
			local nested = opts.nested
			opts.event = nil
			opts.pattern = nil
			opts.once = nil
			opts.nested = nil

			if event == nil then
				vim.keymap.set(mode, lhs, rhs, opts)
			else
				local map_opts = opts
				local ok_au, au_err = pcall(vim.api.nvim_create_autocmd, event, {
					group = group,
					pattern = pattern,
					once = once,
					nested = nested,
					desc = map_opts.desc and ("Pack.boot:keys: " .. tostring(map_opts.desc))
						or ("Pack.boot:keys: " .. lhs),
					callback = function(ev)
						set_buf_map(mode, lhs, rhs, map_opts, ev.buf)
					end,
				})
				if not ok_au then
					vim.notify(
						"Pack.boot:keys: invalid event for " .. lhs .. "\n" .. tostring(au_err),
						vim.log.levels.ERROR
					)
				else
					pending[#pending + 1] = {
						event = event,
						pattern = pattern,
						mode = mode,
						lhs = lhs,
						rhs = rhs,
						map_opts = map_opts,
					}
				end
			end
		end
	end

	backfill_all(pending)
end

---@param groups table|string
function M.commands(groups)
	groups = resolve(groups, "commands")
	if not groups then
		return
	end
	for name, definitions in pairs(groups) do
		local entries = definitions.event and { definitions } or definitions
		if type(entries) ~= "table" then
			vim.notify("Pack.boot:commands: group " .. name .. " must contain autocmd definitions", vim.log.levels.ERROR)
		else
			local group = vim.api.nvim_create_augroup(name, { clear = true })
			for _, definition in ipairs(entries) do
				local event = definition.event
				if event == nil then
					vim.notify("Pack.boot:commands: group " .. name .. " is missing event", vim.log.levels.ERROR)
				else
					local opts = vim.tbl_extend("force", {}, definition, { group = group })
					opts.event = nil
					vim.api.nvim_create_autocmd(event, opts)
				end
			end
		end
	end
end

---@param values table|string
function M.options(values)
	values = resolve(values, "options")
	if not values then
		return
	end
	if values.g ~= nil then
		if type(values.g) ~= "table" then
			vim.notify("Pack.boot:options: g must be a table", vim.log.levels.ERROR)
		else
			for name, value in pairs(values.g) do
				vim.g[name] = value
			end
		end
	end
	if values.opt ~= nil then
		if type(values.opt) ~= "table" then
			vim.notify("Pack.boot:options: opt must be a table", vim.log.levels.ERROR)
		else
			for name, value in pairs(values.opt) do
				vim.opt[name] = value
			end
		end
	end
	if values.diagnostic ~= nil then
		if type(values.diagnostic) ~= "table" then
			vim.notify("Pack.boot:options: diagnostic must be a table", vim.log.levels.ERROR)
		else
			vim.diagnostic.config(values.diagnostic)
		end
	end
end

---@param enable? table|string
---@param disable? string[]|string
function M.lsp(enable, disable)
	local lsp = require("automic.lsp.api")
	if type(enable) == "string" then
		local config = resolve(enable, "lsp")
		if not config then
			return
		end
		if type(config.enable) ~= "table" or type(config.disable) ~= "table" then
			vim.notify(
				"Pack.boot:lsp: module "
					.. enable
					.. " must return { enable = {...}, disable = {...} }",
				vim.log.levels.ERROR
			)
			return
		end
		enable = config.enable
		disable = config.disable
	end
	if type(enable) == "table" and (enable.enable ~= nil or enable.disable ~= nil) and disable == nil then
		disable = enable.disable
		enable = enable.enable
	end
	if enable ~= nil then
		if type(enable) ~= "table" then
			vim.notify("Pack.boot:lsp: enable must be a filetype-to-server mapping", vim.log.levels.ERROR)
			return
		end
		lsp.enable(enable)
	end
	if disable == nil then
		return
	end
	if type(disable) == "string" then
		disable = { disable }
	end
	if type(disable) ~= "table" then
		vim.notify("Pack.boot:lsp: disable must be a server-name list", vim.log.levels.ERROR)
		return
	end
	for _, name in ipairs(disable) do
		if type(name) == "string" then
			lsp.disable(name)
		end
	end
end

return M
