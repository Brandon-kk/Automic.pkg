local state = require("automic.lsp.state")
local control = require("automic.lsp.control")

---@param ft string
---@return table<string, boolean>
local function wanted_for(ft)
	local want = {}
	for _, name in ipairs(state.filetypes[ft] or {}) do
		want[state.norm(name)] = true
	end
	return want
end

---@param buf integer
---@return table<string, boolean>
local function wanted_for_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return {}
	end
	local bt = vim.bo[buf].buftype
	if bt == "terminal" or bt == "prompt" or bt == "quickfix" then
		return {}
	end
	local ft = vim.bo[buf].filetype
	return ft == "" and {} or wanted_for(ft)
end

---@param name string
local function apply(name)
	if state.disabled[name] then
		return
	end
	if (state.server_refs[name] or 0) > 0 then
		control.activate(name)
	else
		control.deactivate(name)
	end
end

---@param buf integer
---@param wanted table<string, boolean>
local function update_buffer(buf, wanted)
	local previous = state.buffer_servers[buf] or {}
	local changed = false
	for name in pairs(previous) do
		if not wanted[name] then
			changed = true
			break
		end
	end
	if not changed then
		for name in pairs(wanted) do
			if not previous[name] then
				changed = true
				break
			end
		end
	end
	if not changed then
		return
	end
	for name in pairs(previous) do
		if not wanted[name] then
			state.server_refs[name] = math.max(0, (state.server_refs[name] or 1) - 1)
			apply(name)
		end
	end
	for name in pairs(wanted) do
		if not previous[name] then
			state.server_refs[name] = (state.server_refs[name] or 0) + 1
			apply(name)
		end
	end
	if next(wanted) then
		state.buffer_servers[buf] = wanted
	else
		state.buffer_servers[buf] = nil
	end
end

--- Rebuild reference counts once after LSP activation or mapping changes.
local function rebuild()
	local managed = {}
	for _, servers in pairs(state.filetypes) do
		for _, name in ipairs(servers) do
			managed[state.norm(name)] = true
		end
	end
	for name in pairs(state.enabled) do
		managed[name] = true
	end
	state.buffer_servers = {}
	state.buffer_ft = {}
	state.server_refs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		update_buffer(buf, wanted_for_buffer(buf))
		if vim.api.nvim_buf_is_valid(buf) then
			state.buffer_ft[buf] = vim.bo[buf].filetype
		end
	end
	for name in pairs(managed) do
		apply(name)
	end
end

---@param buf? integer
---@param removed? boolean
---@param opts? { event?: string }
return function(buf, removed, opts)
	if not buf then
		rebuild()
		return
	end
	if removed then
		state.buffer_ft[buf] = nil
		update_buffer(buf, {})
		return
	end
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local ft = vim.bo[buf].filetype
	-- BufEnter to an already-synced buffer with unchanged filetype is a no-op.
	local event = opts and opts.event
	if event == "BufEnter" and state.buffer_ft[buf] == ft then
		return
	end
	state.buffer_ft[buf] = ft
	update_buffer(buf, wanted_for_buffer(buf))
end
