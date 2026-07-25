local state = require("automic.lsp.state")
local sync = require("automic.lsp.sync")

return function()
	if state.listened then
		return
	end
	state.listened = true
	vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "BufDelete", "BufWipeout" }, {
		group = vim.api.nvim_create_augroup("PackLsp", { clear = true }),
		callback = function(args)
			local removed = args.event == "BufDelete" or args.event == "BufWipeout"
			sync(args.buf, removed, { event = args.event })
		end,
	})
end
