--- Autosave: nested sync write on InsertLeave; debounced TextChanged.
return function()
	local H = require("tests.harness")
	H.suite("autosave.nested write + BufWritePre")

	local autosave = require("automic.autosave")
	autosave.setup(false)

	local tmp = vim.fn.tempname() .. "_automic_autosave.txt"
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, tmp)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
	vim.bo[buf].modified = true

	local write_pre = 0
	local write_pre_group = vim.api.nvim_create_augroup("PackAutosaveTestWritePre", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = write_pre_group,
		buffer = buf,
		callback = function()
			write_pre = write_pre + 1
		end,
	})

	autosave.setup(true)

	-- InsertLeave with nested write must fire BufWritePre synchronously.
	vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
	H.truthy(write_pre >= 1, "BufWritePre runs immediately on autosave write")
	H.falsy(vim.bo[buf].modified, "buffer unmodified after autosave")

	-- Exclusion by filetype (InsertLeave is sync; TextChanged is debounced)
	autosave.setup({ ft = { "text" } })
	vim.bo[buf].filetype = "text"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "again" })
	vim.bo[buf].modified = true
	local before = write_pre
	vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
	H.eq(write_pre, before, "excluded ft does not write")
	H.truthy(vim.bo[buf].modified, "excluded ft stays modified")

	-- Re-entrancy: writing guard stops loops when BufWritePre mutates the buffer
	autosave.setup(true)
	vim.bo[buf].filetype = ""
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "loop" })
	vim.bo[buf].modified = true
	local nested_writes = 0
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = write_pre_group,
		buffer = buf,
		callback = function()
			nested_writes = nested_writes + 1
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "loop-formatted" })
		end,
	})
	vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
	H.truthy(nested_writes >= 1 and nested_writes <= 2, "format-on-save style BufWritePre does not loop")
	H.falsy(vim.bo[buf].modified, "buffer clean after guarded nested write")

	-- TextChanged is debounced (~200ms), not immediate
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "debounced" })
	vim.bo[buf].modified = true
	local before_tc = write_pre
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	H.eq(write_pre, before_tc, "TextChanged does not write synchronously")
	H.truthy(vim.bo[buf].modified, "still modified before debounce fires")
	local waited = vim.wait(500, function()
		return not vim.bo[buf].modified
	end, 20)
	H.truthy(waited, "debounced TextChanged write eventually runs")
	H.truthy(write_pre > before_tc, "BufWritePre runs after TextChanged debounce")

	autosave.setup(false)
	pcall(vim.api.nvim_buf_delete, buf, { force = true })
	pcall(vim.fn.delete, tmp)
	vim.api.nvim_del_augroup_by_id(write_pre_group)
end
