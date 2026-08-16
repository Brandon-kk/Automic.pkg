--- Function builds: :pwait() false must not stamp; ready() blocks before config.
local H = require("tests.harness")

return function()
	H.suite("build.pwait + ready")

	local Pack = _G.Pack
	local run = require("automic.build.run")
	local ready = require("automic.build.ready")
	local cmds = require("automic.build.cmds")
	local stamp = require("automic.build.stamp")
	local restore_notify = H.capture_notify()
	H.reset_notifies()

	local name, mod = "pwait_demo", "pwait_demo_mod"
	H.clear_pack(name, mod)

	local dir = vim.fn.tempname() .. "_pwait_pack"
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

	-- :pwait()-style failure must clear stamp / report failure
	local fail_fn = function()
		return false, "simulated pwait failure"
	end
	cmds.set(name, fail_fn)

	local done, ok_result, err_result = false, nil, nil
	run(name, fail_fn, function(ok, err)
		ok_result = ok
		err_result = err
		done = true
	end, { no_retry = true, sync = true })

	H.truthy(done, "sync pwait-fail finished immediately")
	H.falsy(ok_result, "pwait false → build failure")
	H.eq(tostring(err_result), "simulated pwait failure", "pwait err propagated")
	H.falsy(stamp.current(dir, fail_fn), "no stamp after pwait failure")

	-- Success path + ready()
	local ok_fn = function()
		return true, "ok"
	end
	cmds.set(name, ok_fn)
	done, ok_result = false, nil
	run(name, ok_fn, function(ok)
		ok_result = ok
		done = true
	end, { no_retry = true, sync = true })
	H.truthy(done and ok_result, "pwait true → success")
	H.truthy(stamp.current(dir, ok_fn), "stamp after success")
	H.truthy(ready(name, ok_fn), "ready when stamp current")

	-- Task-like return is waited
	local waited = false
	local task_fn = function()
		return {
			wait = function()
				waited = true
			end,
		}
	end
	stamp.clear(dir)
	cmds.set(name, task_fn)
	done, ok_result = false, nil
	run(name, task_fn, function(ok)
		ok_result = ok
		done = true
	end, { no_retry = true, sync = true })
	H.truthy(done and ok_result and waited, "returned Task is waited")

	-- ready() runs missing builds synchronously
	stamp.clear(dir)
	local built = false
	local build_fn = function()
		built = true
	end
	cmds.set(name, build_fn)
	H.truthy(ready(name, build_fn), "ready builds when stamp missing")
	H.truthy(built, "ready invoked build fn")
	H.truthy(stamp.current(dir, build_fn), "ready left stamp current")

	cmds.set(name, nil)
	stamp.clear(dir)
	Pack.path = real_path
	H.clear_pack(name, mod)
	vim.fn.delete(dir, "rf")
	restore_notify()
end
