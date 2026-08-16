--- Universal build contract: function / shell / :Vim all behave correctly.
local H = require("tests.harness")

return function()
	H.suite("build.contract (all kinds)")

	local Pack = _G.Pack
	local run = require("automic.build.run")
	local ready = require("automic.build.ready")
	local ensure = require("automic.build.ensure")
	local cmds = require("automic.build.cmds")
	local stamp = require("automic.build.stamp")
	local kind = require("automic.build.kind")
	local restore_notify = H.capture_notify()
	H.reset_notifies()

	local name, mod = "contract_demo", "contract_demo_mod"
	H.clear_pack(name, mod)

	local dir = vim.fn.tempname() .. "_contract_pack"
	vim.fn.mkdir(dir, "p")

	Pack.registry[name] = {
		name = name,
		module = mod,
		build = true,
	}
	local real_path = Pack.path
	Pack.path = function(n)
		if Pack.parse(n) == name then
			return dir
		end
		return real_path(n)
	end

	local function sync_run(build_fn)
		local done, ok_result, err_result = false, nil, nil
		run(name, build_fn, function(ok, err)
			ok_result = ok
			err_result = err
			done = true
		end, { no_retry = true, sync = true })
		return done, ok_result, err_result
	end

	------------------------------------------------------------------------
	-- kind helpers
	------------------------------------------------------------------------
	H.truthy(kind.is_preconfig(function() end), "function is preconfig")
	H.truthy(kind.is_preconfig("make"), "shell string is preconfig")
	H.truthy(kind.is_preconfig({ "make", "install" }), "shell argv is preconfig")
	H.falsy(kind.is_preconfig(":TSUpdate"), ":Vim is not preconfig")
	H.truthy(kind.is_vim_cmd(":TSUpdate"), ":Vim detected")
	H.truthy(kind.is_vim_cmd({ ":TSUpdate" }), ":Vim argv detected")

	------------------------------------------------------------------------
	-- function: pwait-style false
	------------------------------------------------------------------------
	local fail_fn = function()
		return false, "pwait-style failure"
	end
	cmds.set(name, fail_fn)
	local done, ok_result, err_result = sync_run(fail_fn)
	H.truthy(done, "fn fail finished")
	H.falsy(ok_result, "fn false → failure")
	H.eq(tostring(err_result), "pwait-style failure", "fn err message")
	H.falsy(stamp.current(dir, fail_fn), "fn fail clears stamp")

	------------------------------------------------------------------------
	-- function: throw
	------------------------------------------------------------------------
	local throw_fn = function()
		error("boom")
	end
	cmds.set(name, throw_fn)
	done, ok_result, err_result = sync_run(throw_fn)
	H.falsy(ok_result, "fn throw → failure")
	H.truthy(tostring(err_result):find("boom", 1, true), "fn throw message")
	H.falsy(stamp.current(dir, throw_fn), "fn throw clears stamp")

	------------------------------------------------------------------------
	-- function: success + ready
	------------------------------------------------------------------------
	local ok_fn = function() end
	cmds.set(name, ok_fn)
	done, ok_result = sync_run(ok_fn)
	H.truthy(done and ok_result, "fn success")
	H.truthy(stamp.current(dir, ok_fn), "fn success stamps")
	H.truthy(ready(name, ok_fn), "ready when stamped")

	------------------------------------------------------------------------
	-- function: returned Task
	------------------------------------------------------------------------
	stamp.clear(dir)
	local waited = false
	local task_fn = function()
		return {
			wait = function()
				waited = true
			end,
		}
	end
	cmds.set(name, task_fn)
	done, ok_result = sync_run(task_fn)
	H.truthy(done and ok_result and waited, "Task:wait auto-run")

	stamp.clear(dir)
	local task_fail = function()
		return {
			wait = function()
				error("task failed")
			end,
		}
	end
	cmds.set(name, task_fail)
	done, ok_result, err_result = sync_run(task_fail)
	H.falsy(ok_result, "Task:wait throw → failure")
	H.truthy(tostring(err_result):find("task failed", 1, true), "Task err message")

	------------------------------------------------------------------------
	-- shell: success / failure
	------------------------------------------------------------------------
	stamp.clear(dir)
	local shell_ok = { "true" }
	cmds.set(name, shell_ok)
	done, ok_result = sync_run(shell_ok)
	H.truthy(done and ok_result, "shell true succeeds")
	H.truthy(stamp.current(dir, shell_ok), "shell success stamps")
	H.truthy(ready(name, shell_ok), "ready for shell stamp")

	stamp.clear(dir)
	local shell_fail = { "false" }
	cmds.set(name, shell_fail)
	done, ok_result = sync_run(shell_fail)
	H.falsy(ok_result, "shell false fails")
	H.falsy(stamp.current(dir, shell_fail), "shell fail clears stamp")
	H.falsy(ready(name, shell_fail), "ready false when shell cannot succeed")

	------------------------------------------------------------------------
	-- :Vim: ready skips; ensure waits for inited
	------------------------------------------------------------------------
	stamp.clear(dir)
	local vim_build = ":lua vim.g._automic_build_vim = true"
	cmds.set(name, vim_build)
	H.truthy(ready(name, vim_build), "ready skips :Vim")
	H.falsy(stamp.current(dir, vim_build), ":Vim not stamped by ready")

	Pack.inited[name] = false
	ensure(name, vim_build)
	H.falsy(Pack.building[name], "ensure skips :Vim before inited")
	H.falsy(stamp.current(dir, vim_build), "no stamp before inited")

	Pack.inited[name] = true
	done, ok_result = false, nil
	run(name, vim_build, function(ok)
		ok_result = ok
		done = true
	end, { no_retry = true, sync = true })
	H.truthy(done and ok_result, ":Vim runs after inited")
	H.truthy(vim.g._automic_build_vim, ":Vim command executed")
	H.truthy(stamp.current(dir, vim_build), ":Vim stamps after success")
	vim.g._automic_build_vim = nil

	------------------------------------------------------------------------
	-- ready builds missing preconfig sync
	------------------------------------------------------------------------
	stamp.clear(dir)
	local built = false
	local build_fn = function()
		built = true
	end
	cmds.set(name, build_fn)
	H.truthy(ready(name, build_fn), "ready builds missing fn")
	H.truthy(built, "ready invoked fn")
	H.truthy(stamp.current(dir, build_fn), "ready left stamp")

	cmds.set(name, nil)
	stamp.clear(dir)
	Pack.path = real_path
	Pack.inited[name] = nil
	H.clear_pack(name, mod)
	vim.fn.delete(dir, "rf")
	restore_notify()
end
