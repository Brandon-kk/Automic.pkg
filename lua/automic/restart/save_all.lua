--- Prepare buffers for a prompt-free `:restart`.
--- 1) Silently write named modifiable file buffers.
--- 2) Drop the modified flag on anything still dirty so `:restart` will not block.
---@return integer saved number of buffers written
return function()
	local saved = 0
	local confirm = vim.o.confirm
	vim.o.confirm = false
	pcall(function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local bo = vim.bo[buf]
				local name = vim.api.nvim_buf_get_name(buf)
				if bo.modifiable and bo.modified and not bo.readonly and bo.buftype == "" and name ~= "" then
					local wrote = pcall(vim.api.nvim_buf_call, buf, function()
						vim.cmd("silent! update")
					end)
					if wrote and not vim.bo[buf].modified then
						saved = saved + 1
					end
				end
				-- Unnamed / failed writes / special buffers: abandon so `:restart` stays quiet.
				if vim.bo[buf].modified then
					vim.bo[buf].modified = false
				end
			end
		end
	end)
	vim.o.confirm = confirm
	return saved
end
