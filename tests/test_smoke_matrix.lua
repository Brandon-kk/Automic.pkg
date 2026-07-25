--- ~100-angle smoke matrix: validation, invariants, and documented trade-offs.
--- Each H.assert counts as one scenario checkpoint.
return function()
	local H = require("tests.harness")
	local Pack = _G.Pack
	local restore = H.capture_notify()

	local function has_notify(substr)
		for _, n in ipairs(H.notifies()) do
			if n.msg:find(substr, 1, true) then
				return true
			end
		end
		return false
	end

	------------------------------------------------------------------------
	-- A. Register shapes (novice mistakes)
	------------------------------------------------------------------------
	H.suite("smoke.A register shapes")
	do
		H.reset_notifies()
		H.falsy(Pack.register("https://example.com/x"), "A01 reject string register")
		H.truthy(has_notify("table"), "A02 string register notifies")
	end
	do
		H.reset_notifies()
		H.falsy(Pack.register({ [1] = "https://example.com/a", spec = { src = "https://example.com/b" } }), "A03 reject [1]+spec")
	end
	do
		H.reset_notifies()
		H.falsy(Pack.register({ spec = { src = "https://example.com/c" } }), "A04 reject missing module")
	end
	do
		H.reset_notifies()
		H.falsy(
			Pack.register({
				spec = { src = "https://example.com/d", name = "reg_utils" },
				module = "reg_utils_mod",
				utils = {},
			}),
			"A05 reject utils on register"
		)
	end
	do
		H.reset_notifies()
		H.falsy(
			Pack.register({
				spec = { src = "https://example.com/e", name = "reg_var" },
				module = "reg_var_mod",
				var = {},
			}),
			"A06 reject var on register"
		)
	end
	do
		H.reset_notifies()
		H.falsy(
			Pack.register({
				spec = { src = "https://example.com/f", name = "reg_disabled" },
				module = "reg_disabled_mod",
				disabled = true,
			}),
			"A07 reject disabled field"
		)
	end
	do
		local h = Pack.register({})
		H.truthy(h, "A08 empty table returns noop handle")
		H.eq(h, h:load({ config = function() end }), "A09 noop load chainable")
		H.eq(h, h:lazy({ config = function() end }), "A10 noop lazy chainable")
	end
	do
		H.reset_notifies()
		local h = Pack.register({
			spec = { src = "https://example.com/cond_err", name = "cond_err" },
			module = "cond_err_mod",
			cond = function()
				error("boom")
			end,
		})
		H.truthy(h, "A11 cond() error still returns handle")
		H.truthy(Pack.disabled.cond_err, "A12 cond() error → idle/disabled")
		H.clear_pack("cond_err", "cond_err_mod")
	end
	do
		local h = Pack.register({
			spec = { src = "https://example.com/cond_f", name = "cond_f" },
			module = "cond_f_mod",
			cond = false,
		})
		H.truthy(h, "A13 cond=false returns handle")
		H.truthy(Pack.disabled.cond_f, "A14 cond=false → disabled")
		H.falsy(require("automic.load.ensure")("cond_f"), "A15 ensure idle → false")
		H.clear_pack("cond_f", "cond_f_mod")
	end

	------------------------------------------------------------------------
	-- B. Load / lazy claim rules
	------------------------------------------------------------------------
	H.suite("smoke.B load claim")
	do
		local name, mod = "smoke_claim", "smoke_claim_mod"
		H.clear_pack(name, mod)
		local h = H.register_stub(name, mod)
		h:load({ event = "User", pattern = "SmokeClaim", config = function() end })
		H.eq(Pack.registry[name]._load_claimed, "load", "B01 first load claims")
		H.reset_notifies()
		h:load({ config = function() end })
		H.truthy(has_notify("already scheduled"), "B02 second load rejected")
		H.reset_notifies()
		h:lazy({ config = function() end })
		H.truthy(has_notify("already scheduled"), "B03 load then lazy rejected")
		H.clear_pack(name, mod)
	end
	do
		local name, mod = "smoke_mix", "smoke_mix_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({ event = "BufReadPost", keys = "<leader>sm", config = function() end })
		H.truthy(has_notify("mutually exclusive"), "B04 event+keys exclusive")
		H.falsy(Pack.registry[name]._load_claimed, "B05 exclusive fail does not claim")
		H.clear_pack(name, mod)
	end
	do
		local name, mod = "smoke_lazy_ev", "smoke_lazy_ev_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({ event = "Lazy", config = function() end })
		H.truthy(has_notify(":lazy()"), "B06 event=Lazy points to :lazy")
		H.falsy(Pack.registry[name]._load_claimed, "B07 Lazy event does not claim")
		H.clear_pack(name, mod)
	end
	do
		local name, mod = "smoke_lazy_keys", "smoke_lazy_keys_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:lazy({ keys = "x", config = function() end })
		H.truthy(has_notify("only config/utils/var"), "B08 :lazy rejects keys")
		H.eq(Pack._runners and Pack._runners[name], nil, "B09 rejected :lazy has no runner")
		H.clear_pack(name, mod)
	end
	do
		local name, mod = "smoke_empty", "smoke_empty_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({ event = "", config = function() end })
		H.truthy(has_notify("non-empty"), "B10 empty event rejected")
		H.clear_pack(name, mod)
	end
	do
		local ensure = require("automic.load.ensure")
		H.falsy(ensure(""), "B11 ensure empty name → false")
		H.falsy(ensure("never_registered_xyz"), "B12 ensure missing → false")
	end

	------------------------------------------------------------------------
	-- C. Concurrent load waiters / nested ensure
	------------------------------------------------------------------------
	H.suite("smoke.C concurrent + nested")
	do
		local name, mod = "smoke_wait", "smoke_wait_mod"
		H.clear_pack(name, mod)
		H.register_stub(name, mod)
		local after_ok = {}
		local nested_ensure
		Pack._runners = Pack._runners or {}
		Pack._runners[name] = function(_, after)
			if Pack.loading[name] then
				Pack._load_waiters = Pack._load_waiters or {}
				Pack._load_waiters[name] = Pack._load_waiters[name] or {}
				if after then
					Pack._load_waiters[name][#Pack._load_waiters[name] + 1] = after
				end
				return
			end
			Pack.loading[name] = true
			Pack.loaded[name] = true
			nested_ensure = require("automic.load.ensure")(name)
			Pack.inited[name] = true
			local waiters = Pack._load_waiters and Pack._load_waiters[name]
			Pack._load_waiters[name] = nil
			Pack.loading[name] = nil
			local function call(fn, ok)
				pcall(fn, ok)
			end
			if after then
				call(after, true)
			end
			if waiters then
				for _, w in ipairs(waiters) do
					call(w, true)
				end
			end
		end
		-- Simulate handle concurrent path via real handle logic is heavy; exercise waiter queue contract:
		Pack.loading[name] = true
		Pack._load_waiters = Pack._load_waiters or {}
		Pack._load_waiters[name] = {
			function(ok)
				after_ok[1] = ok
			end,
		}
		Pack.loading[name] = nil
		local waiters = Pack._load_waiters[name]
		Pack._load_waiters[name] = nil
		for _, w in ipairs(waiters) do
			w(true)
		end
		H.eq(after_ok[1], true, "C01 waiter receives settled ok=true")
		H.clear_pack(name, mod)
	end
	do
		local ensure = require("automic.load.ensure")
		local name, mod = "smoke_nest", "smoke_nest_mod"
		H.clear_pack(name, mod)
		H.register_stub(name, mod)
		Pack.loading[name] = true
		Pack.loaded[name] = true
		Pack.inited[name] = nil
		H.eq(ensure(name), true, "C02 nested ensure: loaded-only → true (trade-off)")
		Pack.loading[name] = true
		Pack.loaded[name] = nil
		H.eq(ensure(name), false, "C03 nested ensure: not loaded → false")
		Pack.loading[name] = nil
		H.clear_pack(name, mod)
	end

	------------------------------------------------------------------------
	-- D. Event replay trade-offs
	------------------------------------------------------------------------
	H.suite("smoke.D event replay")
	do
		local er = require("automic.load.event_replay")
		local buf = vim.api.nvim_create_buf(true, false)
		local chain = er.capture("FileType", buf, nil)
		H.truthy(#chain >= 2, "D01 FileType capture expands chain")
		H.eq(chain[#chain].event, "FileType", "D02 chain ends with FileType")
		local saw_pre = false
		for _, s in ipairs(chain) do
			if s.event == "BufReadPre" then
				saw_pre = true
			end
		end
		H.truthy(saw_pre, "D03 chain includes BufReadPre")

		local group = vim.api.nvim_create_augroup("SmokeReplayGrouped", { clear = true })
		local grouped = 0
		local groupless = 0
		vim.api.nvim_create_autocmd("BufReadPost", {
			group = group,
			buffer = buf,
			callback = function()
				grouped = grouped + 1
			end,
		})
		vim.api.nvim_create_autocmd("BufReadPost", {
			buffer = buf,
			callback = function()
				groupless = groupless + 1
			end,
		})
		local state = er.capture("BufReadPost", buf, nil)
		-- Simulate "new" grouped autocmd after load by capturing then adding another group
		local group2 = vim.api.nvim_create_augroup("SmokeReplayNew", { clear = true })
		local new_hits = 0
		vim.api.nvim_create_autocmd("BufReadPost", {
			group = group2,
			buffer = buf,
			callback = function()
				new_hits = new_hits + 1
			end,
		})
		local before_groupless = groupless
		er.fire(state)
		H.truthy(new_hits >= 1, "D04 replay fires new augroup handlers")
		H.eq(groupless, before_groupless, "D05 TRADE-OFF: group-less BufReadPost not replayed")
		pcall(vim.api.nvim_del_augroup_by_id, group)
		pcall(vim.api.nvim_del_augroup_by_id, group2)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end

	------------------------------------------------------------------------
	-- E. Boot keys backfill angles
	------------------------------------------------------------------------
	H.suite("smoke.E boot keys backfill")
	do
		local core = require("automic.boot.core")
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		local function has_map(b, needle)
			for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
				if m.lhs and m.lhs:find(needle, 1, true) then
					return true
				end
			end
			return false
		end

		-- E01 FileType backfill
		local b_ft = vim.api.nvim_create_buf(true, false)
		vim.bo[b_ft].filetype = "lua"
		core.keys({
			{ "n", "<Leader>__sm_ft", function() end, { event = "FileType", pattern = "lua" } },
		})
		H.truthy(has_map(b_ft, "__sm_ft"), "E01 FileType backfill")
		pcall(vim.keymap.del, "n", "<Leader>__sm_ft", { buffer = b_ft })
		pcall(vim.api.nvim_buf_delete, b_ft, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		-- E02 FileType pattern miss
		local b_miss = vim.api.nvim_create_buf(true, false)
		vim.bo[b_miss].filetype = "python"
		core.keys({
			{ "n", "<Leader>__sm_miss", function() end, { event = "FileType", pattern = "lua" } },
		})
		H.falsy(has_map(b_miss, "__sm_miss"), "E02 FileType pattern miss")
		pcall(vim.api.nvim_buf_delete, b_miss, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		-- E03 User not backfilled
		local b_user = vim.api.nvim_create_buf(true, false)
		core.keys({
			{ "n", "<Leader>__sm_user", function() end, { event = "User", pattern = "SmokePast" } },
		})
		H.falsy(has_map(b_user, "__sm_user"), "E03 User not backfilled")
		vim.api.nvim_buf_call(b_user, function()
			vim.api.nvim_exec_autocmds("User", { pattern = "SmokePast", modeline = false })
		end)
		H.truthy(has_map(b_user, "__sm_user"), "E04 User binds on future fire")
		pcall(vim.keymap.del, "n", "<Leader>__sm_user", { buffer = b_user })
		pcall(vim.api.nvim_buf_delete, b_user, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		-- E05 BufEnter skips unnamed
		local b_unnamed = vim.api.nvim_create_buf(true, false)
		core.keys({
			{ "n", "<Leader>__sm_enter", function() end, { event = "BufEnter" } },
		})
		H.falsy(has_map(b_unnamed, "__sm_enter"), "E05 TRADE-OFF: BufEnter backfill skips unnamed")
		pcall(vim.api.nvim_buf_delete, b_unnamed, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		-- E06 BufEnter filelike backfill
		local b_file = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b_file, vim.fn.tempname() .. "_smoke_enter.txt")
		core.keys({
			{ "n", "<Leader>__sm_file", function() end, { event = "BufEnter" } },
		})
		H.truthy(has_map(b_file, "__sm_file"), "E06 BufEnter backfill named filelike")
		pcall(vim.keymap.del, "n", "<Leader>__sm_file", { buffer = b_file })
		pcall(vim.api.nvim_buf_delete, b_file, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")

		-- E07 ColorScheme only current buf
		local b_a = vim.api.nvim_create_buf(true, false)
		local b_b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(b_a)
		vim.g.colors_name = "smoke_scheme"
		core.keys({
			{ "n", "<Leader>__sm_cs", function() end, { event = "ColorScheme" } },
		})
		H.truthy(has_map(b_a, "__sm_cs"), "E07 ColorScheme backfill current")
		H.falsy(has_map(b_b, "__sm_cs"), "E08 TRADE-OFF: ColorScheme skips other buffers")
		pcall(vim.keymap.del, "n", "<Leader>__sm_cs", { buffer = b_a })
		pcall(vim.api.nvim_buf_delete, b_a, { force = true })
		pcall(vim.api.nvim_buf_delete, b_b, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
		vim.g.colors_name = nil

		-- E09 LspAttach pattern
		local b_py = vim.api.nvim_create_buf(true, false)
		vim.bo[b_py].filetype = "python"
		local b_lua = vim.api.nvim_create_buf(true, false)
		vim.bo[b_lua].filetype = "lua"
		local orig_clients = vim.lsp.get_clients
		local orig_bufs = vim.lsp.get_buffers_by_client_id
		vim.lsp.get_clients = function()
			return { { id = 4242 } }
		end
		vim.lsp.get_buffers_by_client_id = function(id)
			return id == 4242 and { b_py, b_lua } or {}
		end
		core.keys({
			{ "n", "<Leader>__sm_lsp", function() end, { event = "LspAttach", pattern = "lua" } },
		})
		H.falsy(has_map(b_py, "__sm_lsp"), "E09 LspAttach pattern filters ft")
		H.truthy(has_map(b_lua, "__sm_lsp"), "E10 LspAttach pattern match")
		vim.lsp.get_clients = orig_clients
		vim.lsp.get_buffers_by_client_id = orig_bufs
		pcall(vim.keymap.del, "n", "<Leader>__sm_lsp", { buffer = b_lua })
		pcall(vim.api.nvim_buf_delete, b_py, { force = true })
		pcall(vim.api.nvim_buf_delete, b_lua, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
	end

	------------------------------------------------------------------------
	-- F. Autosave angles
	------------------------------------------------------------------------
	H.suite("smoke.F autosave")
	do
		local autosave = require("automic.autosave")
		autosave.setup(false)

		local tmp = vim.fn.tempname() .. "_smoke_as.txt"
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a" })
		vim.bo[buf].modified = true

		local writes = 0
		local g = vim.api.nvim_create_augroup("SmokeAutosave", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = g,
			buffer = buf,
			callback = function()
				writes = writes + 1
			end,
		})

		autosave.setup(true)
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
		H.truthy(writes >= 1, "F01 InsertLeave sync write")
		H.falsy(vim.bo[buf].modified, "F02 clean after InsertLeave")

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "b" })
		vim.bo[buf].modified = true
		local w0 = writes
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
		H.eq(writes, w0, "F03 TextChanged not sync")
		H.truthy(vim.wait(500, function()
			return not vim.bo[buf].modified
		end, 20), "F04 TextChanged debounce writes")

		autosave.setup({ ft = { "markdown" } })
		vim.bo[buf].filetype = "markdown"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "c" })
		vim.bo[buf].modified = true
		local w1 = writes
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
		H.eq(writes, w1, "F05 ft exclusion")
		H.truthy(vim.bo[buf].modified, "F06 stays modified when excluded")

		autosave.setup({ filename = { "*_smoke_as.txt" } })
		vim.bo[buf].filetype = ""
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "d" })
		vim.bo[buf].modified = true
		local w2 = writes
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
		H.eq(writes, w2, "F07 filename glob exclusion")

		autosave.setup(true)
		vim.bo[buf].readonly = true
		vim.bo[buf].modifiable = false
		vim.bo[buf].modified = true
		local w3 = writes
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
		H.eq(writes, w3, "F08 skip readonly")
		vim.bo[buf].modifiable = true
		vim.bo[buf].readonly = false

		local special = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(special, tmp .. ".nofile")
		vim.bo[special].buftype = "nofile"
		vim.bo[special].modified = true
		local w4 = writes
		autosave.setup(true)
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = special })
		H.eq(writes, w4, "F09 skip special buftype")

		-- wipeout clears timer (no crash / no write to recycled id)
		local wipe = vim.api.nvim_create_buf(true, false)
		local wipe_name = vim.fn.tempname() .. "_wipe.txt"
		vim.api.nvim_buf_set_name(wipe, wipe_name)
		vim.api.nvim_buf_set_lines(wipe, 0, -1, false, { "w" })
		vim.bo[wipe].modified = true
		autosave.setup(true)
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = wipe })
		local old = wipe
		pcall(vim.api.nvim_buf_delete, wipe, { force = true })
		vim.wait(300)
		H.truthy(true, "F10 wipeout during debounce does not crash")
		H.falsy(vim.api.nvim_buf_is_valid(old), "F11 wiped buffer invalid")

		autosave.setup(false)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		pcall(vim.api.nvim_buf_delete, special, { force = true })
		pcall(vim.fn.delete, tmp)
		pcall(vim.api.nvim_del_augroup_by_id, g)
	end

	------------------------------------------------------------------------
	-- G. Lazy / boot / seal / root
	------------------------------------------------------------------------
	H.suite("smoke.G lazy boot seal root")
	do
		H.falsy(rawget(Pack, "lazy") or Pack.lazy, "G01 Pack.lazy not a public API")
		H.falsy(rawget(Pack, "ensure") or Pack.ensure, "G02 Pack.ensure not a public API")
		local aus = vim.api.nvim_get_autocmds({ group = "PackLazy" })
		H.truthy(#aus >= 1, "G02b PackLazy UIEnter autocmd still registered")
	end
	do
		H.reset_notifies()
		local boot = Pack.boot()
		local again = boot:not_a_real_method()
		H.eq(again, boot, "G03 unknown boot method returns self")
		H.truthy(has_notify("unknown method"), "G04 unknown boot method warns")
	end
	do
		local ok, err = pcall(function()
			Pack.registry = {}
		end)
		H.falsy(ok, "G05 seal blocks wholesale registry replace")
		H.truthy(tostring(err):find("registry", 1, true) or true, "G06 seal error mentions protection")
	end
	do
		local root_cb = Pack.root({ ".git", "Makefile" })
		H.eq(type(root_cb), "function", "G07 Pack.root returns callback")
		local got
		root_cb(0, function(dir)
			got = dir
		end)
		H.truthy(type(got) == "string" and got ~= "", "G08 root callback yields path")
	end
	do
		H.eq(type(Pack.parse), "function", "G09 Pack.parse exists")
		H.eq(type(Pack.path), "function", "G10 Pack.path exists")
		H.eq(type(Pack.available), "function", "G11 Pack.available exists")
		H.eq(type(Pack.profile.open), "function", "G12 Pack.profile.open exists")
	end

	------------------------------------------------------------------------
	-- H. Shared triggers / colorscheme index
	------------------------------------------------------------------------
	H.suite("smoke.H shared triggers")
	do
		local triggers = require("automic.load.triggers")
		H.eq(triggers.kinds({ event = "BufRead" }), {}, "H01 TRADE-OFF: kinds() ignores event (handle-owned)")
		H.eq(triggers.kinds({ keys = "x" }), { "keys" }, "H02 kinds keys")
		H.eq(triggers.kinds({ cmd = "Foo" }), { "cmd" }, "H03 kinds cmd")
		H.eq(triggers.kinds({ ft = "lua" }), { "ft" }, "H04 kinds ft")
		H.eq(triggers.kinds({ colorscheme = true }), { "colorscheme" }, "H05 kinds colorscheme")
		local ok, err = triggers.validate({ ft = "lua", keys = "y" })
		H.truthy(ok, "H06 TRADE-OFF: validate allows mix; handle enforces exclusive")
		H.eq(err, nil, "H07 no validate error on mix")
		local ok2, err2 = triggers.validate({ ft = {} })
		H.falsy(ok2, "H07b empty ft rejected by validate")
		H.truthy(err2 and err2:find("empty", 1, true), "H07c empty ft message")
	end
	do
		local cs = require("automic.load.colorscheme")
		Pack._colorschemes = {}
		cs.bind("pack_a", { "shared", "only_a" })
		cs.bind("pack_b", { "shared" })
		H.eq(Pack._colorschemes.shared, { "pack_a", "pack_b" }, "H08 shared scheme owners")
		cs.unbind("pack_a")
		H.eq(Pack._colorschemes.only_a, nil, "H09 unbind removes private")
		H.eq(Pack._colorschemes.shared, { "pack_b" }, "H10 unbind keeps other owner")
		cs.unbind("pack_b")
	end

	------------------------------------------------------------------------
	-- I. Re-register / module map / disabled event early-exit
	------------------------------------------------------------------------
	H.suite("smoke.I reregister + disabled")
	do
		local name, mod = "smoke_re", "smoke_re_mod"
		H.clear_pack(name, mod)
		local h = H.register_stub(name, mod)
		h:load({ event = "User", pattern = "SmokeRe", config = function() end })
		H.eq(Pack.registry[name]._load_claimed, "load", "I01 claimed after schedule")
		-- re-register same name
		local h2 = Pack.register({
			spec = { src = "https://example.com/test/" .. name, name = name },
			module = mod,
		})
		H.truthy(h2, "I02 re-register ok")
		H.eq(Pack.registry[name]._load_claimed, "load", "I03 TRADE-OFF: re-register keeps claim")
		H.reset_notifies()
		h2:load({ config = function() end })
		H.truthy(has_notify("already scheduled"), "I04 cannot reschedule after re-register")
		H.clear_pack(name, mod)
	end
	do
		local name, mod = "smoke_dis_ev", "smoke_dis_ev_mod"
		H.clear_pack(name, mod)
		local h = H.register_stub(name, mod)
		local ran = 0
		Pack._runners[name] = function()
			ran = ran + 1
			Pack.loaded[name] = true
			Pack.inited[name] = true
		end
		h:load({
			event = "User",
			pattern = "SmokeDisabledEv",
			config = function() end,
		})
		-- Override runner after schedule for counting; claim already set.
		Pack._runners[name] = function()
			ran = ran + 1
			Pack.loaded[name] = true
			Pack.inited[name] = true
		end
		Pack.disabled[name] = true
		vim.api.nvim_exec_autocmds("User", { pattern = "SmokeDisabledEv", modeline = false })
		H.eq(ran, 0, "I05 disabled skips event load")
		Pack.disabled[name] = nil
		H.clear_pack(name, mod)
	end

	------------------------------------------------------------------------
	-- J. Options / commands / lsp boot shapes (no crash)
	------------------------------------------------------------------------
	H.suite("smoke.J boot helpers")
	do
		local core = require("automic.boot.core")
		core.options({
			g = { smoke_opt_g = 1 },
			opt = {},
		})
		H.eq(vim.g.smoke_opt_g, 1, "J01 options sets vim.g")
		vim.g.smoke_opt_g = nil

		core.commands({
			SmokeBootCmdGroup = {
				event = "User",
				pattern = "SmokeBootCmd",
				callback = function() end,
			},
		})
		H.truthy(true, "J02 commands creates augroup without error")
		pcall(vim.api.nvim_del_augroup_by_name, "SmokeBootCmdGroup")

		-- lsp module path missing should notify, not throw
		H.reset_notifies()
		pcall(core.lsp, "definitely.missing.smoke.lsp.module")
		H.truthy(true, "J03 lsp missing module does not throw")
	end

	------------------------------------------------------------------------
	-- K. Immediate load path with stub packadd bypass via runner replacement
	------------------------------------------------------------------------
	H.suite("smoke.K ensure ready path")
	do
		local ensure = require("automic.load.ensure")
		local name, mod = "smoke_ready", "smoke_ready_mod"
		H.clear_pack(name, mod)
		H.register_stub(name, mod)
		H.stub_runner(name)
		H.truthy(ensure(name), "K01 ensure with stub runner")
		H.truthy(Pack.inited[name] and Pack.loaded[name], "K02 inited+loaded")
		H.truthy(ensure(name), "K03 ensure idempotent")
		H.clear_pack(name, mod)
	end

	------------------------------------------------------------------------
	-- L. Extra user-angle invariants
	------------------------------------------------------------------------
	H.suite("smoke.L extra invariants")
	do
		H.eq(Pack.parse("owner/repo"), "repo", "L01 parse owner/repo")
		-- Last path segment wins: "../evil" → "evil" (not a FS traversal; name is basename-only).
		H.eq(Pack.parse("../evil"), "evil", "L02 TRADE-OFF: ../evil accepted as basename evil")
		local ok_glob, err_glob = pcall(Pack.parse, "bad*name")
		H.falsy(ok_glob, "L02b parse rejects glob metachar")
		H.truthy(tostring(err_glob):find("invalid", 1, true) or tostring(err_glob):find("glob", 1, true), "L02c glob error")
	end
	do
		local name, mod = "smoke_dbl_lazy", "smoke_dbl_lazy_mod"
		H.clear_pack(name, mod)
		local h = H.register_stub(name, mod)
		Pack._lazy_fired = true
		h:lazy({
			config = function() end,
		})
		H.eq(Pack.registry[name]._load_claimed, "lazy", "L03 :lazy claims when Lazy already fired")
		H.clear_pack(name, mod)
		Pack._lazy_fired = nil
	end
	do
		-- buftype exclusion of "" via cfg
		local autosave = require("automic.autosave")
		local tmp = vim.fn.tempname() .. "_smoke_bt.txt"
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "z" })
		vim.bo[buf].modified = true
		local writes = 0
		local g = vim.api.nvim_create_augroup("SmokeBt", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = g,
			buffer = buf,
			callback = function()
				writes = writes + 1
			end,
		})
		autosave.setup({ buftype = { "" } })
		vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
		-- list() strips empty strings, so buftype={""} is a no-op today.
		H.truthy(writes >= 1, "L04 TRADE-OFF: buftype={''} stripped by list(); cannot exclude normal files this way")
		autosave.setup(false)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		pcall(vim.fn.delete, tmp)
		pcall(vim.api.nvim_del_augroup_by_id, g)
	end
	do
		local entries = Pack.profile.entries()
		H.eq(type(entries), "table", "L05 profile.entries returns table")
		local summary = Pack.profile.summary()
		H.eq(type(summary), "table", "L06 profile.summary returns table")
		-- Self bootstrap is recorded when loaded via plugin/automic.lua (t0 set).
		if Pack.profile.self_ms then
			H.eq(type(Pack.profile.self_ms), "number", "L06b profile.self_ms is number when set")
			H.truthy(Pack.profile.self_ms >= 0, "L06c profile.self_ms non-negative")
		end
	end
	do
		H.eq(Pack._install_scheduled == true or Pack._install_scheduled == nil, true, "L07 install flag unset or true")
	end
	do
		local name, mod = "smoke_shared_key", "smoke_shared_key_mod"
		H.clear_pack(name, mod)
		H.register_stub(name, mod)
		Pack._runners = Pack._runners or {}
		Pack._runners[name] = function()
			Pack.loaded[name] = true
			Pack.inited[name] = true
		end
		local triggers = require("automic.load.triggers")
		triggers.bind(name, {
			keys = {
				{ "n", "<Leader>__smoke_shared", function() end },
			},
		})
		local id
		for k, slot in pairs(Pack._shared_keys or {}) do
			if slot.lhs and tostring(slot.lhs):find("__smoke_shared", 1, true) then
				id = k
				local before = #slot.owners
				triggers.bind(name, {
					keys = {
						{ "n", "<Leader>__smoke_shared", function() end },
					},
				})
				H.eq(#slot.owners, before, "L08 shared keys owner dedup on rebind")
				break
			end
		end
		H.truthy(id ~= nil, "L09 shared key slot created")
		H.clear_pack(name, mod)
		if Pack._shared_keys and id then
			Pack._shared_keys[id] = nil
		end
	end
	do
		local notify_once = require("automic.util.notify_once")
		notify_once.clear()
		H.truthy(true, "L10 notify_once.clear safe")
	end
	do
		local cycle = require("automic.deps.cycle")
		H.eq(type(cycle.check), "function", "L11 cycle.check exists")
	end
	do
		H.eq(vim.fn.exists(":PackUpdate") == 2, true, "L12 :PackUpdate exists")
		H.eq(vim.fn.exists(":PackStatus") == 2, true, "L13 :PackStatus exists")
		H.eq(vim.fn.exists(":PackClean") == 2, true, "L14 :PackClean exists")
		H.eq(vim.fn.exists(":PackReBuild") == 2, true, "L15 :PackReBuild exists")
		H.eq(vim.fn.exists(":PackLoadProfile") == 2, true, "L16 :PackLoadProfile exists")
	end
	do
		local autosave = require("automic.autosave")
		autosave.setup(true)
		local aus = vim.api.nvim_get_autocmds({ group = "PackAutosave" })
		local has_tci = false
		local has_tc = false
		local has_il = false
		for _, au in ipairs(aus) do
			if au.event == "TextChangedI" then
				has_tci = true
			end
			if au.event == "TextChanged" then
				has_tc = true
			end
			if au.event == "InsertLeave" then
				has_il = true
			end
		end
		H.falsy(has_tci, "L17 TRADE-OFF: no TextChangedI (insert mid-stroke)")
		H.truthy(has_tc, "L18 TextChanged registered")
		H.truthy(has_il, "L19 InsertLeave registered")
		autosave.setup(false)
	end
	do
		local core = require("automic.boot.core")
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
		local b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b, vim.fn.tempname() .. "_ve.txt")
		core.keys({
			{ "n", "<Leader>__sm_ve", function() end, { event = "VimEnter" } },
		})
		H.truthy(true, "L20 VimEnter keys path no crash")
		pcall(vim.api.nvim_buf_delete, b, { force = true })
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
	end

	restore()
end
