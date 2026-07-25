--- Pack.boot:keys event-gated buffer maps + immediate backfill.
return function()
	local H = require("tests.harness")
	H.suite("boot.keys event gating")

	local core = require("automic.boot.core")
	pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

	---@param b integer
	---@param needle string
	local function has_map(b, needle)
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
			if m.lhs and m.lhs:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	-- Future event still binds
	core.keys({
		{
			"n",
			"<Leader>__pack_keys_event",
			function() end,
			{ desc = "test event key", event = "User", pattern = "PackKeysEventTest" },
		},
	})

	local buf = vim.api.nvim_create_buf(true, false)
	H.falsy(has_map(buf, "__pack_keys_event"), "map absent before event")

	vim.api.nvim_buf_call(buf, function()
		vim.api.nvim_exec_autocmds("User", { pattern = "PackKeysEventTest", modeline = false })
	end)
	H.truthy(has_map(buf, "__pack_keys_event"), "map present on event buffer after User event")

	pcall(vim.keymap.del, "n", "<Leader>__pack_keys_event", { buffer = buf })
	pcall(vim.api.nvim_buf_delete, buf, { force = true })
	pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

	-- FileType backfill: buffer already has ft before keys() runs
	local buf2 = vim.api.nvim_create_buf(true, false)
	vim.bo[buf2].filetype = "lua"
	core.keys({
		{
			"n",
			"<Leader>__pack_keys_ft",
			function() end,
			{ desc = "ft backfill", event = "FileType", pattern = "lua" },
		},
	})
	H.truthy(has_map(buf2, "__pack_keys_ft"), "FileType map backfilled on existing buffer")

	pcall(vim.keymap.del, "n", "<Leader>__pack_keys_ft", { buffer = buf2 })
	pcall(vim.api.nvim_buf_delete, buf2, { force = true })
	pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

	-- LspAttach backfill respects filetype pattern
	local buf3 = vim.api.nvim_create_buf(true, false)
	vim.bo[buf3].filetype = "python"
	local buf4 = vim.api.nvim_create_buf(true, false)
	vim.bo[buf4].filetype = "lua"
	local orig_get_clients = vim.lsp.get_clients
	local orig_get_bufs = vim.lsp.get_buffers_by_client_id
	vim.lsp.get_clients = function()
		return { { id = 9001 } }
	end
	vim.lsp.get_buffers_by_client_id = function(id)
		if id == 9001 then
			return { buf3, buf4 }
		end
		return {}
	end
	core.keys({
		{
			"n",
			"<Leader>__pack_keys_lsp",
			function() end,
			{ desc = "lsp backfill", event = "LspAttach", pattern = "lua" },
		},
	})
	H.falsy(has_map(buf3, "__pack_keys_lsp"), "LspAttach pattern skips non-matching ft")
	H.truthy(has_map(buf4, "__pack_keys_lsp"), "LspAttach pattern backfills matching ft")
	vim.lsp.get_clients = orig_get_clients
	vim.lsp.get_buffers_by_client_id = orig_get_bufs
	pcall(vim.keymap.del, "n", "<Leader>__pack_keys_lsp", { buffer = buf4 })
	pcall(vim.api.nvim_buf_delete, buf3, { force = true })
	pcall(vim.api.nvim_buf_delete, buf4, { force = true })
	pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
end
