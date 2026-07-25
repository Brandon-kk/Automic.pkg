--- 内置自动保存：InsertLeave / TextChanged 时把改过的命名 buffer 写盘
--- 要开：Pack.boot():autosave() 或 :autosave(opts)
---
--- InsertLeave 立刻写（nested），好让 BufWritePre 跟着跑
--- TextChanged 会防抖，免得宏/大批量编辑狂写磁盘
local cfg = {
	ft = {},
	buftype = {},
	filename = {},
}

local DEBOUNCE_MS = 200
---@type table<integer, uv.uv_timer_t>
local timers = {}

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

---@param items string[]
---@param value string
---@return boolean
local function contains(items, value)
	for _, item in ipairs(items) do
		if item == value then
			return true
		end
	end
	return false
end

--- 文件名按 glob 匹配（规则跟 Pack.boot:keys 一样）
---@param patterns string[]
---@param name string
---@return boolean
local function matches_any(patterns, name)
	for _, pat in ipairs(patterns) do
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

---@param buf integer
---@return boolean
local function should_write(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
		return false
	end
	local buftype = vim.bo[buf].buftype
	-- 特殊 buftype 一律不自动存；cfg.buftype 也可以把普通 "" 排除掉
	if buftype ~= "" or contains(cfg.buftype, buftype) then
		return false
	end
	local ft = vim.bo[buf].filetype
	if ft ~= "" and contains(cfg.ft, ft) then
		return false
	end
	if not vim.bo[buf].modified then
		return false
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return false
	end
	if matches_any(cfg.filename, name) then
		return false
	end
	return true
end

local writing = false

---@param buf integer
local function write_buf(buf)
	if writing or not should_write(buf) then
		return
	end
	writing = true
	local ok, err = pcall(function()
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent! write")
		end)
	end)
	writing = false
	if not ok then
		vim.notify("Pack.autosave: write failed\n" .. tostring(err), vim.log.levels.WARN)
	end
end

---@param buf integer
local function clear_timer(buf)
	local timer = timers[buf]
	if not timer then
		return
	end
	timers[buf] = nil
	pcall(function()
		timer:stop()
		timer:close()
	end)
end

local function clear_timers()
	for buf, _ in pairs(timers) do
		clear_timer(buf)
	end
end

---@param buf integer
local function debounce_write(buf)
	clear_timer(buf)
	local timer = vim.uv.new_timer()
	if not timer then
		write_buf(buf)
		return
	end
	-- 记一下当时的名字，防 bufnr 复用后写到别人头上
	local gen = vim.api.nvim_buf_get_name(buf)
	timers[buf] = timer
	timer:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			if timers[buf] == timer then
				timers[buf] = nil
			end
			pcall(function()
				timer:stop()
				timer:close()
			end)
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			if vim.api.nvim_buf_get_name(buf) ~= gen then
				return
			end
			write_buf(buf)
		end)
	)
end

local M = {}

--- 开/关/配排除项
--- 写法：nil/true | false | { ft?, buftype?, filename?, enable? }
---@param opts? boolean|Pack.AutosaveOpts
function M.setup(opts)
	local enable = true
	local next_cfg = { ft = {}, buftype = {}, filename = {} }

	if opts == nil or opts == true then
		enable = true
	elseif opts == false then
		enable = false
	elseif type(opts) == "table" then
		if opts.enable == false then
			enable = false
		end
		next_cfg.ft = list(opts.ft)
		next_cfg.buftype = list(opts.buftype)
		next_cfg.filename = list(opts.filename)
	else
		vim.notify("Pack.autosave: expected boolean or table", vim.log.levels.ERROR)
		return
	end

	cfg = next_cfg
	clear_timers()
	local group = vim.api.nvim_create_augroup("PackAutosave", { clear = true })
	if not enable then
		return
	end

	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		nested = true,
		desc = "Pack.autosave: 退出插入就写",
		callback = function(ev)
			write_buf(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd("TextChanged", {
		group = group,
		nested = true,
		desc = "Pack.autosave: 改字防抖后写",
		callback = function(ev)
			debounce_write(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		desc = "Pack.autosave: buffer 没了就清定时器",
		callback = function(ev)
			clear_timer(ev.buf)
		end,
	})
end

return M
