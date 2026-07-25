--- Re-fire autocmd events after a package loads (aligned with lazy.nvim's event handler).
---
--- Plugins that register FileType/BufRead* handlers in config would otherwise miss the
--- event that triggered the load.
local M = {}

-- Event chain: after loading on FileType, also re-fire BufReadPost → BufReadPre.
local TRIGGERS = {
	FileType = "BufReadPost",
	BufReadPost = "BufReadPre",
}

---@param event string
---@return table<string, boolean> set of augroup names
local function augroup_set(event)
	local set = {}
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
		local g = autocmd.group_name
		if g then
			set[g] = true
		end
	end
	return set
end

---@class Pack.EventReplayState
---@field event string
---@field exclude_set? table<string, boolean>
---@field buffer? integer
---@field data? any

--- Capture event state before load so post-load fire can skip pre-existing groups.
---@param event string
---@param buf? integer
---@param data? any
---@return Pack.EventReplayState[]
function M.capture(event, buf, data)
	local state = {}
	local current = event
	local payload = data
	while current do
		table.insert(state, 1, {
			event = current,
			-- FileType: fire all groups (plugin often registers here).
			-- Others: skip groups that already existed so only new handlers run.
			exclude_set = current ~= "FileType" and augroup_set(current) or nil,
			buffer = buf,
			data = payload,
		})
		payload = nil
		current = TRIGGERS[current]
	end
	return state
end

---@param opts Pack.EventReplayState
local function trigger_one(opts)
	if opts.group or opts.exclude_set == nil then
		-- No exclude (e.g. FileType): fire the whole event, including group-less handlers.
		pcall(vim.api.nvim_exec_autocmds, opts.event, {
			buffer = opts.buffer,
			group = opts.group,
			modeline = false,
			data = opts.data,
		})
		return
	end
	-- Diff unique augroup names after load; fire only groups that are new.
	-- One get_autocmds pass → unique set, then O(new groups) exec (not O(all autocmds)).
	local exclude_set = opts.exclude_set
	local after = augroup_set(opts.event)
	for gname in pairs(after) do
		if not exclude_set[gname] then
			pcall(vim.api.nvim_exec_autocmds, opts.event, {
				buffer = opts.buffer,
				group = gname,
				modeline = false,
				data = opts.data,
			})
		end
	end
end

--- Fire captured states after a successful load.
---@param states Pack.EventReplayState[]
function M.fire(states)
	for _, s in ipairs(states) do
		trigger_one(s)
	end
end

return M
