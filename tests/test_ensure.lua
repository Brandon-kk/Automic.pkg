local H = require("tests.harness")
local ensure = require("automic.load.ensure")

return function()
	H.suite("load.ensure + module mapping")

	local Pack = _G.Pack
	local name, mod = "ensure_demo", "ensure_demo_mod"
	H.clear_pack(name, mod)

	local handle = H.register_stub(name, mod)
	H.eq(Pack.modules[mod], name, "register indexes module")

	-- No runner yet → ensure false
	H.falsy(ensure(name), "ensure without runner fails")

	H.stub_runner(name)
	H.truthy(ensure(name), "ensure with stub runner succeeds")
	H.truthy(Pack.inited[name] and Pack.loaded[name], "inited+loaded after ensure")

	-- Nested ensure while loading
	Pack.inited[name] = nil
	Pack.loaded[name] = true
	Pack.loading[name] = true
	H.truthy(ensure(name), "nested ensure during loading uses loaded flag")
	Pack.loading[name] = nil

	-- require auto-load: preload is checked before our loader, so only expose
	-- the module from inside the runner (simulates packadd putting files on rtp).
	Pack.inited[name] = nil
	Pack.loaded[name] = nil
	package.loaded[mod] = nil
	package.preload[mod] = nil
	H.stub_runner(name, function()
		package.preload[mod] = function()
			return { setup = function() end, _name = mod }
		end
	end)
	local ok, plugin = pcall(require, mod)
	H.truthy(ok, "require triggers module loader: " .. tostring(plugin))
	H.truthy(plugin and plugin._name == mod, "required module table")
	H.truthy(Pack.inited[name], "require path inited the pack")

	-- Submodule prefix: require("mod.sub") resolves via parent "mod" without scanning all packs
	Pack.inited[name] = nil
	Pack.loaded[name] = nil
	package.loaded[mod] = nil
	package.loaded[mod .. ".child"] = nil
	package.preload[mod] = nil
	package.preload[mod .. ".child"] = nil
	H.stub_runner(name, function()
		package.preload[mod .. ".child"] = function()
			return { kind = "child" }
		end
	end)
	local ok_child, child = pcall(require, mod .. ".child")
	H.truthy(ok_child, "require submodule triggers parent pack: " .. tostring(child))
	H.eq(child and child.kind, "child", "submodule table returned")
	H.truthy(Pack.inited[name], "submodule require inited the pack")

	-- Second :load rejected after claim via real schedule
	H.clear_pack(name, mod)
	handle = H.register_stub(name, mod)
	H.reset_notifies()
	local restore = H.capture_notify()
	handle:load({
		config = function() end,
	})
	-- Immediate load may fail packadd; claim still set if validation passed.
	-- Force claim like a successful schedule:
	local P = Pack.registry[name]
	P._load_claimed = "load"
	handle:load({ config = function() end })
	restore()
	local msgs = H.notifies()
	local rejected = false
	for _, n in ipairs(msgs) do
		if n.msg:find("rejected", 1, true) then
			rejected = true
			break
		end
	end
	H.truthy(rejected, "second :load rejected while claimed")

	H.clear_pack(name, mod)
end
