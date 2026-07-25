--- Register keys / cmd / ft load triggers for Pack.handle:load().
---
--- First trigger in a session loads the package once; later uses hit the real
--- commands/maps. Stub hooks are restored if that first load fails.
--- Shared keys/cmd: multiple packs may claim the same lhs or command name.
local M = {}

local ensure = require("automic.load.ensure")

---@param value string|string[]|nil
---@return string[]
local function list(value)
	if type(value) == "string" then
		return value ~= "" and { value } or {}
	end
	if type(value) ~= "table" then
		return {}
	end
	local out = {}
	for _, item in ipairs(value) do
		if type(item) == "string" and item ~= "" then
			out[#out + 1] = item
		end
	end
	return out
end

---@param opts Pack.LoadOpts
---@return boolean
local function has_keys(opts)
	if type(opts.keys) == "string" then
		return opts.keys ~= ""
	end
	if type(opts.keys) ~= "table" then
		return false
	end
	for _, entry in ipairs(opts.keys) do
		if type(entry) == "string" and entry ~= "" then
			return true
		end
		if type(entry) == "table" then
			if type(entry.lhs) == "string" and entry.lhs ~= "" then
				return true
			end
			if type(entry[2]) == "string" and entry[2] ~= "" then
				return true
			end
			if type(entry[1]) == "string" and entry[1] ~= "" and type(entry[2]) ~= "string" then
				return true
			end
		end
	end
	return false
end

---@param opts Pack.LoadOpts
---@return boolean
local function has_colorscheme(opts)
	if opts.colorscheme == true then
		return true
	end
	if type(opts.colorscheme) == "string" then
		return opts.colorscheme ~= ""
	end
	if type(opts.colorscheme) ~= "table" then
		return false
	end
	for _, item in ipairs(opts.colorscheme) do
		if type(item) == "string" and item ~= "" then
			return true
		end
	end
	return false
end

---@param opts Pack.LoadOpts
---@return boolean
function M.has(opts)
	return #list(opts.ft) > 0
		or #list(opts.cmd) > 0
		or has_keys(opts)
		or has_colorscheme(opts)
end

--- Active first-class trigger kinds (non-empty only).
---@param opts Pack.LoadOpts
---@return string[]
function M.kinds(opts)
	local kinds = {}
	if #list(opts.ft) > 0 then
		kinds[#kinds + 1] = "ft"
	end
	if #list(opts.cmd) > 0 then
		kinds[#kinds + 1] = "cmd"
	end
	if has_keys(opts) then
		kinds[#kinds + 1] = "keys"
	end
	if has_colorscheme(opts) then
		kinds[#kinds + 1] = "colorscheme"
	end
	return kinds
end

--- Reject present-but-empty / wrong-type trigger fields before scheduling.
---@param opts Pack.LoadOpts
---@return boolean ok
---@return string|nil err
function M.validate(opts)
	if opts.ft ~= nil then
		if type(opts.ft) ~= "string" and type(opts.ft) ~= "table" then
			return false, "ft must be a string or list of strings"
		end
		if #list(opts.ft) == 0 then
			return false, "ft is empty (provide at least one filetype)"
		end
	end
	if opts.cmd ~= nil then
		if type(opts.cmd) ~= "string" and type(opts.cmd) ~= "table" then
			return false, "cmd must be a string or list of strings"
		end
		if #list(opts.cmd) == 0 then
			return false, "cmd is empty (provide at least one command name)"
		end
	end
	if opts.keys ~= nil then
		if type(opts.keys) ~= "string" and type(opts.keys) ~= "table" then
			return false, "keys must be a string or list of key entries"
		end
		if not has_keys(opts) then
			return false, "keys is empty (provide at least one key entry)"
		end
	end
	if opts.colorscheme ~= nil then
		if opts.colorscheme ~= true and type(opts.colorscheme) ~= "string" and type(opts.colorscheme) ~= "table" then
			return false, "colorscheme must be true, a string, or a list of strings"
		end
		if not has_colorscheme(opts) then
			return false, "colorscheme is empty (provide at least one scheme name, or true)"
		end
	end
	return true
end

--- Normalize for profile display.
---@param opts Pack.LoadOpts
---@return string[]|nil ft
---@return string[]|nil cmd
---@return string[]|nil keys
---@return string[]|nil colorscheme
function M.summary(opts)
	local ft = list(opts.ft)
	local cmd = list(opts.cmd)
	local keys = {}
	if type(opts.keys) == "string" then
		if opts.keys ~= "" then
			keys[1] = opts.keys
		end
	elseif type(opts.keys) == "table" then
		for _, entry in ipairs(opts.keys) do
			if type(entry) == "string" then
				keys[#keys + 1] = entry
			elseif type(entry) == "table" and type(entry.lhs) == "string" then
				local mode = entry.mode or "n"
				local mode_s = type(mode) == "table" and table.concat(mode, ",") or tostring(mode)
				keys[#keys + 1] = mode_s .. " " .. entry.lhs
			elseif type(entry) == "table" and type(entry[2]) == "string" then
				local mode = entry[1]
				local mode_s = type(mode) == "table" and table.concat(mode, ",") or tostring(mode or "n")
				keys[#keys + 1] = mode_s .. " " .. entry[2]
			elseif type(entry) == "table" and type(entry[1]) == "string" then
				keys[#keys + 1] = entry[1]
			end
		end
	end
	local colorscheme
	if opts.colorscheme == true then
		colorscheme = { "(pack name)" }
	elseif type(opts.colorscheme) == "string" and opts.colorscheme ~= "" then
		colorscheme = { opts.colorscheme }
	elseif type(opts.colorscheme) == "table" then
		colorscheme = list(opts.colorscheme)
		if #colorscheme == 0 then
			colorscheme = nil
		end
	end
	return #ft > 0 and ft or nil,
		#cmd > 0 and cmd or nil,
		#keys > 0 and keys or nil,
		colorscheme
end

---@param mode string|string[]
---@return boolean
local function valid_mode(mode)
	if type(mode) == "string" then
		return mode ~= ""
	end
	if type(mode) ~= "table" then
		return false
	end
	for _, m in ipairs(mode) do
		if type(m) ~= "string" or m == "" then
			return false
		end
	end
	return #mode > 0
end

---@param mode string|string[]
---@param lhs string
---@return string
local function key_id(mode, lhs, buffer)
	local mode_s = type(mode) == "table" and table.concat(mode, ",") or tostring(mode or "n")
	local buf_s = buffer ~= nil and (":b" .. tostring(buffer)) or ""
	return mode_s .. "\0" .. lhs .. buf_s
end

--- Feed lhs after load (lazy.nvim-style: expr stub + Ignore + insert feed).
---@param mode string|string[]
---@param lhs string
local function feed_lhs(mode, lhs)
	local feed = lhs
	if type(mode) == "string" and mode:sub(-1) == "a" then
		feed = lhs .. "<C-]>"
	end
	local keys = vim.api.nvim_replace_termcodes("<Ignore>" .. feed, true, true, true)
	vim.api.nvim_feedkeys(keys, "i", false)
end

---@param names string[]
---@return boolean
local function ensure_all(names)
	local all_ok = true
	for _, name in ipairs(names) do
		if not ensure(name, true) then
			all_ok = false
		end
	end
	return all_ok
end

---@param name string
---@param opts Pack.LoadOpts
function M.bind(name, opts)
	local Pack = _G.Pack
	local event_replay = require("automic.load.event_replay")
	Pack._shared_cmds = Pack._shared_cmds or {}
	Pack._shared_keys = Pack._shared_keys or {}

	-- ft → FileType (per-plugin; FileType patterns rarely need sharing)
	local fts = list(opts.ft)
	if #fts > 0 then
		local function install_ft()
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("PackLoad:" .. name .. ":ft", { clear = true }),
				pattern = fts,
				once = true,
				nested = true,
				desc = "Pack.load ft trigger for " .. name,
				callback = function(ev)
					if Pack.disabled[name] then
						return
					end
					local state = event_replay.capture(ev.event, ev.buf, ev.data)
					if not ensure(name, true) then
						if not Pack.disabled[name] then
							install_ft()
						end
						return
					end
					event_replay.fire(state)
				end,
			})
		end
		install_ft()
	end

	-- colorscheme → ColorSchemePre index
	if has_colorscheme(opts) then
		local cs = require("automic.load.colorscheme")
		local P = Pack.registry[name]
		local schemes = cs.normalize(opts.colorscheme, name, P and P.module)
		cs.bind(name, schemes)
	end

	-- cmd → shared stub (one command may load multiple packs)
	local function bind_cmd(cmd_name)
		local slot = Pack._shared_cmds[cmd_name]
		if not slot then
			slot = { names = {} }
			Pack._shared_cmds[cmd_name] = slot
		end
		if not vim.tbl_contains(slot.names, name) then
			slot.names[#slot.names + 1] = name
		end
		if slot.installed then
			return
		end
		slot.installed = true

		local function install_stub()
			local ok_create, create_err = pcall(vim.api.nvim_create_user_command, cmd_name, function(event)
				pcall(vim.api.nvim_del_user_command, cmd_name)
				slot.installed = false
				if not ensure_all(slot.names) then
					install_stub()
					return
				end

				local command = {
					cmd = cmd_name,
					bang = event.bang or nil,
					mods = event.smods,
					args = event.fargs,
					count = event.count >= 0 and event.range == 0 and event.count or nil,
				}
				if event.range == 1 then
					command.range = { event.line1 }
				elseif event.range == 2 then
					command.range = { event.line1, event.line2 }
				end

				local info = vim.api.nvim_get_commands({})[cmd_name]
					or vim.api.nvim_buf_get_commands(0, {})[cmd_name]
				if not info then
					vim.notify(
						"Pack.load: command :" .. cmd_name .. " not found after loading shared packs",
						vim.log.levels.ERROR
					)
					return
				end
				command.nargs = info.nargs
				if event.args and event.args ~= "" and info.nargs and tostring(info.nargs):find("[1?]") then
					command.args = { event.args }
				end

				local ok, err = pcall(vim.cmd, command)
				if not ok then
					vim.notify(
						"Pack.load: replay of :" .. cmd_name .. " failed\n" .. tostring(err),
						vim.log.levels.ERROR
					)
				end
			end, {
				nargs = "*",
				bang = true,
				range = true,
				desc = "Pack.load shared cmd trigger :" .. cmd_name,
				complete = function(_, line)
					pcall(vim.api.nvim_del_user_command, cmd_name)
					slot.installed = false
					if not ensure_all(slot.names) then
						install_stub()
						return {}
					end
					return vim.fn.getcompletion(line, "cmdline")
				end,
			})
			if not ok_create then
				slot.installed = false
				vim.notify(
					"Pack.load: failed to create cmd trigger :"
						.. cmd_name
						.. "\n"
						.. tostring(create_err),
					vim.log.levels.ERROR
				)
			else
				slot.installed = true
			end
		end
		install_stub()
	end

	for _, cmd_name in ipairs(list(opts.cmd)) do
		bind_cmd(cmd_name)
	end

	-- keys → shared expr stub
	local function bind_key(mode, lhs, rhs, map_opts)
		if type(lhs) ~= "string" or lhs == "" then
			vim.notify(
				"Pack.load: keys entry for " .. name .. " is missing a non-empty lhs; skipped",
				vim.log.levels.WARN
			)
			return
		end
		mode = mode or "n"
		if not valid_mode(mode) then
			vim.notify(
				"Pack.load: keys entry for " .. name .. " has invalid mode for " .. lhs .. "; skipped",
				vim.log.levels.WARN
			)
			return
		end
		map_opts = vim.tbl_extend("force", {}, map_opts or {})
		map_opts.desc = map_opts.desc or ("Pack.load keys trigger for " .. lhs)
		local buffer = map_opts.buffer
		local del_opts = buffer ~= nil and { buffer = buffer } or {}
		local id = key_id(mode, lhs, buffer)

		local slot = Pack._shared_keys[id]
		if not slot then
			slot = {
				mode = mode,
				lhs = lhs,
				map_opts = map_opts,
				del_opts = del_opts,
				owners = {},
			}
			Pack._shared_keys[id] = slot
		end
		local replaced = false
		for i, owner in ipairs(slot.owners) do
			if owner.name == name then
				slot.owners[i] = { name = name, rhs = rhs, map_opts = map_opts }
				replaced = true
				break
			end
		end
		if not replaced then
			slot.owners[#slot.owners + 1] = { name = name, rhs = rhs, map_opts = map_opts }
		end
		-- Keep latest map_opts/desc for the stub.
		slot.map_opts = map_opts
		slot.del_opts = del_opts

		if slot.installed then
			return
		end
		slot.installed = true

		local function require_plugin(pack_name)
			local P = Pack.registry[pack_name]
			if not P or type(P.module) ~= "string" or P.module == "" then
				return false, "missing module for " .. pack_name
			end
			local ok, plugin = pcall(require, P.module)
			if not ok then
				return false, plugin
			end
			return true, plugin
		end

		local function install_map()
			local stub_opts = vim.tbl_extend("force", {}, slot.map_opts, { expr = true })
			local ok_set, set_err = pcall(vim.keymap.set, slot.mode, slot.lhs, function()
				pcall(vim.keymap.del, slot.mode, slot.lhs, slot.del_opts)
				slot.installed = false

				local names = {}
				for _, owner in ipairs(slot.owners) do
					names[#names + 1] = owner.name
				end
				if not ensure_all(names) then
					install_map()
					return nil
				end

				-- Install rhs from owners that declared one (last wins on same lhs).
				local last_rhs, last_opts, last_name
				for _, owner in ipairs(slot.owners) do
					if owner.rhs ~= nil then
						last_rhs, last_opts, last_name = owner.rhs, owner.map_opts, owner.name
					end
				end
				if type(last_rhs) == "function" then
					local ok_req, plugin_or_err = require_plugin(last_name)
					if not ok_req then
						vim.notify(
							"Pack.load: keys rhs for "
								.. last_name
								.. " failed to require module\n"
								.. tostring(plugin_or_err),
							vim.log.levels.ERROR
						)
						install_map()
						return nil
					end
					local plugin = plugin_or_err
					local function bound(...)
						return last_rhs(plugin, ...)
					end
					local ok_rebind, rebind_err = pcall(vim.keymap.set, slot.mode, slot.lhs, bound, last_opts)
					if not ok_rebind then
						vim.notify(
							"Pack.load: failed to rebind keys " .. slot.lhs .. "\n" .. tostring(rebind_err),
							vim.log.levels.ERROR
						)
						install_map()
						return nil
					end
				elseif type(last_rhs) == "string" then
					local ok_rebind, rebind_err = pcall(vim.keymap.set, slot.mode, slot.lhs, last_rhs, last_opts)
					if not ok_rebind then
						vim.notify(
							"Pack.load: failed to rebind keys " .. slot.lhs .. "\n" .. tostring(rebind_err),
							vim.log.levels.ERROR
						)
						install_map()
						return nil
					end
				elseif last_rhs ~= nil then
					vim.notify(
						"Pack.load: keys rhs for " .. slot.lhs .. " must be a function or string; replaying lhs",
						vim.log.levels.WARN
					)
				end

				feed_lhs(slot.mode, slot.lhs)
				return nil
			end, stub_opts)
			if not ok_set then
				slot.installed = false
				vim.notify(
					"Pack.load: failed to create keys trigger " .. slot.lhs .. "\n" .. tostring(set_err),
					vim.log.levels.ERROR
				)
			else
				slot.installed = true
			end
		end

		install_map()
	end

	if type(opts.keys) == "string" then
		bind_key("n", opts.keys, nil, nil)
	elseif type(opts.keys) == "table" then
		for _, entry in ipairs(opts.keys) do
			if type(entry) == "string" then
				bind_key("n", entry, nil, nil)
			elseif type(entry) == "table" then
				if type(entry.lhs) == "string" then
					bind_key(entry.mode or "n", entry.lhs, entry.rhs, entry.opts)
				elseif type(entry[2]) == "string" then
					bind_key(entry[1], entry[2], entry[3], entry[4])
				elseif type(entry[1]) == "string" then
					bind_key("n", entry[1], nil, type(entry[2]) == "table" and entry[2] or nil)
				else
					vim.notify(
						"Pack.load: unrecognized keys entry for " .. name .. "; skipped",
						vim.log.levels.WARN
					)
				end
			else
				vim.notify(
					"Pack.load: unrecognized keys entry for " .. name .. "; skipped",
					vim.log.levels.WARN
				)
			end
		end
	end
end

return M
