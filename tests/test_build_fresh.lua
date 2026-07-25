--- Post-update function builds must drop cached Lua modules (stale git HEAD, etc.).
local H = require("tests.harness")

return function()
	H.suite("build.fresh + unload")

	local Pack = _G.Pack
	local fresh = require("automic.build.fresh")
	local unload = require("automic.build.unload")
	local run = require("automic.build.run")
	local cmds = require("automic.build.cmds")
	local stamp = require("automic.build.stamp")

	local name, mod = "fresh_demo", "fresh_demo_mod"
	H.clear_pack(name, mod)

	-- Isolated pack dir with a tiny lua module that freezes a token at require time.
	local dir = vim.fn.tempname() .. "_fresh_pack"
	vim.fn.mkdir(dir .. "/lua/" .. mod, "p")
	local modfile = dir .. "/lua/" .. mod .. "/init.lua"
	vim.fn.writefile({
		"return { token = assert(rawget(_G, '_FRESH_TOKEN'), 'missing token') }",
	}, modfile)

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

	package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
	_G._FRESH_TOKEN = "old"
	package.loaded[mod] = nil
	local first = require(mod)
	H.eq(first.token, "old", "initial require sees old token")

	-- Simulate PackChanged update: mark fresh, then build must re-require.
	fresh.mark(name)
	_G._FRESH_TOKEN = "new"
	-- Keep stale package.loaded[mod] on purpose — unload should clear it.
	H.eq(package.loaded[mod].token, "old", "stale cache still old before build")

	H.truthy(fresh.pending(name), "fresh pending after mark")
	H.truthy(fresh.consume(name), "consume once")
	H.falsy(fresh.pending(name), "consume clears mark")
	unload.modules(name, dir)
	H.eq(package.loaded[mod], nil, "unload drops cached module")
	-- Pack.loaded / Pack.inited must stay put so module_loader does not cold-load
	-- during build; restart after build resets session state.

	local rebuilt = require(mod)
	H.eq(rebuilt.token, "new", "re-require after unload sees new token")

	-- Force-rebuild path: fresh.mark + run() should unload before the callback.
	fresh.mark(name)
	_G._FRESH_TOKEN = "newer"
	package.loaded[mod] = { token = "stale-again" }
	Pack.loaded[name] = true
	Pack.inited[name] = true

	local seen = {}
	local build_fn = function()
		local m = require(mod)
		seen.via_run = m.token
	end
	cmds.set(name, build_fn)

	local done, ok_result = false, nil
	run(name, build_fn, function(ok)
		ok_result = ok
		done = true
	end, { no_retry = true })

	vim.wait(2000, function()
		return done
	end, 20)
	H.truthy(done, "function build finished")
	H.truthy(ok_result, "function build ok")
	H.eq(seen.via_run, "newer", "run()+fresh unloads before build callback")
	H.truthy(stamp.current(dir, build_fn), "stamp written after success")

	-- cleanup
	cmds.set(name, nil)
	stamp.clear(dir)
	Pack.path = real_path
	H.clear_pack(name, mod)
	package.loaded[mod] = nil
	_G._FRESH_TOKEN = nil
	vim.fn.delete(dir, "rf")
end
