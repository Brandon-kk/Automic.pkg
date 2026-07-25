--- Standalone floating UI for `:PackLoadProfile`; does not depend on Snacks.
local M = {}
local namespace = vim.api.nvim_create_namespace("PackLoadProfile")

local function format_ms(ms)
	return ("%7.2f ms"):format(ms or 0)
end

local function trigger(entry)
	local parts = {}
	if entry.event then
		local event = type(entry.event) == "table" and table.concat(entry.event, ", ") or entry.event
		if entry.pattern then
			local pattern = type(entry.pattern) == "table" and table.concat(entry.pattern, ", ") or entry.pattern
			event = event .. " (" .. pattern .. ")"
		end
		if entry.defer then
			event = event .. " · scheduled"
		end
		parts[#parts + 1] = event
	end
	if entry.ft then
		parts[#parts + 1] = "ft:" .. table.concat(entry.ft, ",")
	end
	if entry.cmd then
		parts[#parts + 1] = "cmd:" .. table.concat(entry.cmd, ",")
	end
	if entry.keys then
		parts[#parts + 1] = "keys:" .. table.concat(entry.keys, ", ")
	end
	if entry.colorscheme then
		parts[#parts + 1] = "colorscheme:" .. table.concat(entry.colorscheme, ",")
	end
	if #parts == 0 then
		return "Immediate"
	end
	return table.concat(parts, " · ")
end

local function scratch()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	return buf
end

local function float(buf, config)
	config.relative = "editor"
	config.style = "minimal"
	config.zindex = 60
	return vim.api.nvim_open_win(buf, false, config)
end

---@param profile table
function M.open(profile)
	if M._close then
		M._close()
	end
	vim.api.nvim_set_hl(0, "PackLoadProfilePath", { fg = "#cba6f7" })
	-- The four bordered blocks compose one 60% × 60% Profile surface.
	local outer_width = math.max(4, math.floor(vim.o.columns * 0.6))
	local outer_height = math.max(10, math.floor(vim.o.lines * 0.6))
	local width = outer_width - 2
	local panel_height = outer_height - 2
	-- input (3) + list (body + 2) + summary (3) = outer height
	local body_height = math.max(1, panel_height - 6)
	local row = math.max(1, math.floor((vim.o.lines - outer_height) / 2))
	local col = math.max(2, math.floor((vim.o.columns - outer_width) / 2))
	local left_width = math.floor((width - 2) / 2)
	local right_width = width - left_width - 2

	local input = scratch()
	local list = scratch()
	local detail = scratch()
	local summary = scratch()
	vim.bo[input].buftype = "prompt"
	vim.fn.prompt_setprompt(input, " 󰩉  ")
	vim.api.nvim_buf_add_highlight(input, namespace, "Special", 0, 1, 1 + #"󰩉")
	vim.bo[list].filetype = "packprofile"
	vim.bo[detail].filetype = "packprofile"
	vim.bo[summary].filetype = "packprofile"
	vim.bo[list].modifiable = false
	vim.bo[detail].modifiable = false
	vim.bo[summary].modifiable = false

	local wins = {
		float(input, {
			width = left_width,
			height = 1,
			row = row,
			col = col,
			border = "rounded",
			title = " Pack Load Profile ",
			title_pos = "left",
		}),
		float(list, {
			width = left_width,
			height = body_height,
			row = row + 3,
			col = col,
			border = "rounded",
		}),
		float(summary, {
			width = left_width,
			height = 1,
			row = row + body_height + 5,
			col = col,
			border = "rounded",
		}),
		float(detail, {
			width = right_width,
			height = panel_height,
			row = row,
			col = col + left_width + 2,
			border = "rounded",
			title = " Plugin details ",
			title_pos = "left",
		}),
	}
	vim.wo[wins[2]].cursorline = true
	vim.wo[wins[2]].winhighlight = "CursorLine:Visual"
	vim.wo[wins[3]].wrap = false

	local visible = {}
	local closing = false
	-- Snapshot once: typing only filters; live reload is a separate open.
	local all_entries = profile.entries()
	local stats = profile.summary()
	local refresh_timer ---@type uv.uv_timer_t|nil
	local function close()
		if closing then
			return
		end
		closing = true
		if refresh_timer then
			refresh_timer:stop()
			refresh_timer:close()
			refresh_timer = nil
		end
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		M._close = nil
	end
	M._close = close

	local function set_lines(buf, lines)
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	end

	local function highlight(buf, line, start_col, end_col, group)
		vim.api.nvim_buf_add_highlight(buf, namespace, group, line, start_col, end_col)
	end

	local function highlight_field(buf, line, key, group)
		highlight(buf, line, 0, #key, group or "Identifier")
		highlight(buf, line, #key, -1, "String")
	end

	local function selected()
		local row_index = vim.api.nvim_win_get_cursor(wins[2])[1]
		return visible[row_index]
	end

	local function render_detail()
		local entry = selected()
		if not entry then
			local message = "No matching plugins"
			local lines = {}
			local message_row = math.floor((panel_height - 1) / 2)
			for _ = 1, message_row do
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = string.rep(" ", math.max(0, math.floor((right_width - #message) / 2))) .. message
			for _ = #lines + 1, panel_height do
				lines[#lines + 1] = ""
			end
			vim.api.nvim_win_set_config(wins[4], { title = " Plugin details ", title_pos = "left" })
			set_lines(detail, lines)
			highlight(detail, message_row, 0, -1, "FloatBorder")
			return
		end
		local parents = entry.parents and #entry.parents > 0 and table.concat(entry.parents, ", ") or "—"
		vim.api.nvim_win_set_config(wins[4], { title = " " .. entry.name .. " ", title_pos = "left" })
		local result
		local result_hl
		if entry.ok == false then
			result = "Failed · " .. (entry.reason or "Unknown error")
			result_hl = "DiagnosticError"
		elseif entry.ok == true then
			result = "Success"
			result_hl = "DiagnosticOk"
		else
			result = "Pending"
			result_hl = "DiagnosticWarn"
		end
		set_lines(detail, {
			("Status: %s"):format(entry.inited and "Started" or (entry.loaded and "Loaded, unconfigured" or "Not loaded")),
			("Result: %s"):format(result),
			("Load time: %s"):format(format_ms(entry.load_ms)),
			("Load count: %d"):format(entry.attempts or 0),
			"",
			("Trigger: %s"):format(trigger(entry)),
			("Kind: %s"):format(
				entry.kind == "dependency" and "Dependency" or entry.kind == "manager" and "Manager" or "Plugin"
			),
			("Required by: %s"):format(parents),
			("Module: %s"):format(entry.module or "—"),
			"",
			"Config file:",
			entry.source or "—",
		})
		for _, line in ipairs({ 0, 1, 2, 3, 5, 6, 7, 8, 10 }) do
			highlight_field(detail, line, vim.api.nvim_buf_get_lines(detail, line, line + 1, false)[1]:match("^[^:]+:") or "")
		end
		highlight(detail, 0, #"Status: ", -1, entry.inited and "DiagnosticOk" or "DiagnosticWarn")
		highlight(detail, 1, #"Result: ", -1, result_hl)
		highlight(detail, 2, #"Load time: ", -1, "Number")
		highlight(detail, 11, 0, -1, "PackLoadProfilePath")
	end

	local function refresh()
		local line = vim.api.nvim_buf_get_lines(input, 0, 1, false)[1] or ""
		local prompt = vim.fn.prompt_getprompt(input)
		local query = line:sub(#prompt + 1):lower()
		visible = {}
		for _, entry in ipairs(all_entries) do
			local haystack = (entry.name .. " " .. (entry.module or "") .. " " .. (entry.source or "")):lower()
			if haystack:find(query, 1, true) then
				visible[#visible + 1] = entry
			end
		end
		local lines = {}
		local empty_message_row
		for _, entry in ipairs(visible) do
			local icon = entry.inited and "󰄴" or (entry.loaded and "󰄯" or "󰄰")
			local time = format_ms(entry.load_ms):gsub("^%s+", "")
			local prefix = (" %s  %s"):format(icon, entry.name)
			local gap = math.max(2, left_width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(time) - 1)
			lines[#lines + 1] = prefix .. string.rep(" ", gap) .. time .. " "
		end
		if #visible == 0 then
			local message = "No matching plugins"
			empty_message_row = math.floor((body_height - 1) / 2)
			for _ = 1, empty_message_row do
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = string.rep(" ", math.max(0, math.floor((left_width - #message) / 2))) .. message
			for _ = #lines + 1, body_height do
				lines[#lines + 1] = ""
			end
		end
		set_lines(list, lines)
		for index, entry in ipairs(visible) do
			local icon = entry.inited and "󰄴" or (entry.loaded and "󰄯" or "󰄰")
			local name_start = 1 + #icon + 2
			local time = format_ms(entry.load_ms):gsub("^%s+", "")
			local time_start = #lines[index] - #time - 1
			highlight(list, index - 1, 1, 1 + #icon, entry.inited and "DiagnosticOk" or "DiagnosticWarn")
			highlight(list, index - 1, name_start, time_start - 2, "Identifier")
			highlight(list, index - 1, time_start, time_start + #time, "Number")
		end
		if empty_message_row then
			highlight(list, empty_message_row, 0, -1, "FloatBorder")
		end
		vim.wo[wins[2]].cursorline = #visible > 0
		vim.api.nvim_win_set_cursor(wins[2], { 1, 0 })
		render_detail()

		local padding = 2
		local startup_time = format_ms(stats.startup_ms):gsub("^%s+", "")
		local startup_text = "Startup  " .. startup_time
		local loaded_text = ("Loaded  %d/%d"):format(stats.loaded, stats.total)
		local gap = math.max(2, left_width - (padding * 2) - #startup_text - #loaded_text)
		local summary_text = string.rep(" ", padding)
			.. startup_text
			.. string.rep(" ", gap)
			.. loaded_text
			.. string.rep(" ", padding)
		set_lines(summary, {
			summary_text,
		})
		highlight(summary, 0, padding, padding + #"Startup", "Identifier")
		highlight(summary, 0, padding + #"Startup  ", padding + #startup_text, "Number")
		local loaded_start = padding + #startup_text + gap
		highlight(summary, 0, loaded_start, loaded_start + #"Loaded", "Identifier")
		highlight(summary, 0, loaded_start + #"Loaded  ", loaded_start + #loaded_text, "DiagnosticOk")
	end

	local function move(delta)
		if #visible == 0 then
			return
		end
		local line = vim.api.nvim_win_get_cursor(wins[2])[1]
		local next_line = ((line - 1 + delta) % #visible) + 1
		vim.api.nvim_win_set_cursor(wins[2], { next_line, 0 })
		render_detail()
	end

	for _, buf in ipairs({ input, list, detail, summary }) do
		vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = buf, nowait = true })
		vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
		vim.keymap.set("n", ":", "<Nop>", { buffer = buf, nowait = true })
		vim.keymap.set("n", "<leader>q", "<Nop>", { buffer = buf, nowait = true })
		vim.keymap.set("n", "<Tab>", function()
			move(1)
		end, { buffer = buf, nowait = true })
		vim.keymap.set("n", "<S-Tab>", function()
			move(-1)
		end, { buffer = buf, nowait = true })
		vim.keymap.set("n", "j", function()
			move(1)
		end, { buffer = buf, nowait = true })
		vim.keymap.set("n", "k", function()
			move(-1)
		end, { buffer = buf, nowait = true })
	end
	vim.keymap.set("i", "<Tab>", function()
		move(1)
	end, { buffer = input, nowait = true })
	vim.keymap.set("i", "<S-Tab>", function()
		move(-1)
	end, { buffer = input, nowait = true })
	vim.keymap.set("i", "jk", "<Esc>", { buffer = input, nowait = true })
	vim.keymap.set("x", "j", function()
		move(1)
	end, { buffer = list, nowait = true })
	vim.keymap.set("x", "k", function()
		move(-1)
	end, { buffer = list, nowait = true })
	vim.keymap.set("i", "<C-n>", function()
		move(1)
	end, { buffer = input })
	vim.keymap.set("i", "<C-p>", function()
		move(-1)
	end, { buffer = input })
	vim.keymap.set("i", "<CR>", function()
		vim.api.nvim_set_current_win(wins[2])
	end, { buffer = input })
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = list,
		callback = render_detail,
	})
	vim.api.nvim_buf_attach(input, false, {
		on_lines = function()
			if closing then
				return
			end
			if refresh_timer then
				refresh_timer:stop()
			else
				refresh_timer = vim.uv.new_timer()
			end
			refresh_timer:start(
				40,
				0,
				vim.schedule_wrap(function()
					if not closing then
						refresh()
					end
				end)
			)
		end,
	})

	refresh()
	vim.api.nvim_set_current_win(wins[1])
	vim.cmd.startinsert()
end

return M
