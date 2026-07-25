--- After install: build all pending plugins in parallel (incl. :Vim cmds; run packadds first)
local cmds = require("automic.build.cmds")
local stamp = require("automic.build.stamp")
local fresh = require("automic.build.fresh")
local run = require("automic.build.run")
local retry = require("automic.build.retry")

---@param names? string[] When provided, build only these names (they still need a build and no valid stamp unless forced).
---@param opts? { force?: boolean }
---@return { name: string, build: string|string[]|function }[]
local function collect_pending(names, opts)
	opts = opts or {}
	local Pack = _G.Pack
	local want = nil
	if names ~= nil then
		want = {}
		for _, n in ipairs(names) do
			want[Pack.parse(n)] = true
		end
	end

	local list = {}
	for name, build in pairs(cmds.all()) do
		local skip = (want and not want[name]) or Pack.disabled[name] or false
		local dir = not skip and Pack.path(name) or nil
		if not skip and not dir then
			skip = true
		end
		if not skip and not opts.force and stamp.current(dir, build) then
			skip = true
		end
		-- Already building: still collect; run returns already building, then wait to merge
		if not skip and retry.pending(name) and not Pack.building[name] then
			skip = true
		end
		if not skip then
			list[#list + 1] = { name = name, build = build }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

--- Wait for in-flight build; classify via stamp
---@param item { name: string, build: string|string[]|function }
---@param on_settled fun(ok: boolean)
local function wait_inflight(item, on_settled)
	local Pack = _G.Pack
	local timer = vim.uv.new_timer()
	if not timer then
		on_settled(false)
		return
	end
	local ticks = 0
	timer:start(
		50,
		50,
		vim.schedule_wrap(function()
			ticks = ticks + 1
			if Pack.building[item.name] and ticks < 6000 then
				return
			end
			timer:stop()
			timer:close()
			local dir = Pack.path(item.name)
			on_settled(dir ~= nil and stamp.current(dir, item.build))
		end)
	)
end

---@class Pack.BuildBatchResult
---@field ran integer
---@field ok_names string[]
---@field fail_names string[]

---@param on_done fun(result: Pack.BuildBatchResult)
---@param names? string[]
---@param opts? { force?: boolean, silent_start?: boolean }
local function batch(on_done, names, opts)
	opts = opts or {}
	local todo = collect_pending(names, opts)
	if #todo == 0 then
		on_done({ ran = 0, ok_names = {}, fail_names = {} })
		return
	end

	if not opts.silent_start then
		vim.notify("Building " .. #todo .. " plugins in parallel...", vim.log.levels.INFO)
	end

	local left = #todo
	local ok_names, fail_names = {}, {}

	local function one_done()
		left = left - 1
		if left > 0 then
			return
		end
		if #fail_names == 0 and #ok_names > 0 then
			vim.notify("Build success", vim.log.levels.INFO)
		end
		on_done({
			ran = #ok_names + #fail_names,
			ok_names = ok_names,
			fail_names = fail_names,
		})
	end

	local function settle(name, ok)
		if ok then
			ok_names[#ok_names + 1] = name
		else
			fail_names[#fail_names + 1] = name
		end
		one_done()
	end

	for _, item in ipairs(todo) do
		retry.reset(item.name)
		if opts.force then
			local dir = require("automic.deps.path")(item.name)
			if dir then
				stamp.clear(dir)
			end
			-- Force rebuild must also re-require modules (stale checkout caches, etc.).
			fresh.mark(item.name)
		end
		run(item.name, item.build, function(ok, err)
			if ok then
				settle(item.name, true)
			elseif err == "already building" then
				wait_inflight(item, function(built_ok)
					settle(item.name, built_ok)
				end)
			else
				settle(item.name, false)
			end
		end, { quiet = true, no_retry = true })
	end
end

return batch
