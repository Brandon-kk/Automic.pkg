--- Minimal assertion harness for headless Neovim (no plenary/busted).
local M = {
	failed = 0,
	passed = 0,
	current = "?",
}

local notifies = {}

function M.reset_notifies()
	notifies = {}
end

function M.notifies()
	return notifies
end

function M.capture_notify()
	local orig = vim.notify
	vim.notify = function(msg, level, opts)
		notifies[#notifies + 1] = {
			msg = tostring(msg),
			level = level or vim.log.levels.INFO,
			opts = opts,
		}
		-- Keep silence in headless runs; still allow debugging via :messages if needed.
	end
	return function()
		vim.notify = orig
	end
end

---@param name string
function M.suite(name)
	M.current = name
	print("  " .. name)
end

---@param cond any
---@param msg string
function M.assert(cond, msg)
	if cond then
		M.passed = M.passed + 1
		return
	end
	M.failed = M.failed + 1
	io.stderr:write(string.format("FAIL [%s] %s\n", M.current, msg))
end

function M.eq(a, b, msg)
	local ok = vim.deep_equal(a, b)
	M.assert(ok, (msg or "equality") .. string.format("\n  left:  %s\n  right: %s", vim.inspect(a), vim.inspect(b)))
end

function M.truthy(v, msg)
	M.assert(v and true or false, msg or "expected truthy")
end

function M.falsy(v, msg)
	M.assert(not v, msg or "expected falsy")
end

--- Register a stub pack with a fake runner (no real packadd).
---@param name string
---@param module string
---@return Pack.Handle|nil
function M.register_stub(name, module)
	local Pack = _G.Pack
	package.preload[module] = package.preload[module]
		or function()
			return {
				setup = function() end,
				_name = module,
			}
		end

	local handle = Pack.register({
		spec = {
			src = "https://example.com/test/" .. name,
			name = name,
		},
		module = module,
	})
	M.truthy(handle, "register " .. name)
	return handle
end

--- Install a no-op runner that marks the pack ready (bypasses packadd).
---@param name string
---@param config_fn? fun()
function M.stub_runner(name, config_fn)
	local Pack = _G.Pack
	Pack._runners = Pack._runners or {}
	Pack._runners[name] = function()
		if Pack.loading[name] then
			return
		end
		Pack.loading[name] = true
		Pack.loaded[name] = true
		if config_fn then
			config_fn()
		end
		Pack.inited[name] = true
		Pack.loading[name] = nil
	end
end

function M.clear_pack(name, module)
	local Pack = _G.Pack
	local P = Pack.registry[name]
	if P then
		P._load_claimed = nil
	end
	Pack.registry[name] = nil
	Pack.loaded[name] = nil
	Pack.inited[name] = nil
	Pack.loading[name] = nil
	Pack.disabled[name] = nil
	if Pack._runners then
		Pack._runners[name] = nil
	end
	if module and Pack.modules then
		if Pack.modules[module] == name then
			Pack.modules[module] = nil
		end
	end
	if Pack._shared_cmds then
		for cmd, slot in pairs(Pack._shared_cmds) do
			if slot.names then
				local next_names = {}
				for _, n in ipairs(slot.names) do
					if n ~= name then
						next_names[#next_names + 1] = n
					end
				end
				slot.names = next_names
			end
		end
	end
	package.loaded[module] = nil
end

return M
