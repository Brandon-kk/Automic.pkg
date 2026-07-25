local H = require("tests.harness")

return function()
	H.suite("load trigger rules")

	local Pack = _G.Pack
	local restore = H.capture_notify()

	-- event = Lazy removed
	do
		local name, mod = "rule_lazy", "rule_lazy_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({ event = "Lazy", config = function() end })
		local hit = false
		for _, n in ipairs(H.notifies()) do
			if n.msg:find('event = "Lazy"', 1, true) or n.msg:find(":lazy()", 1, true) then
				hit = true
			end
		end
		H.truthy(hit, "event=Lazy points to :lazy()")
		H.falsy(Pack.registry[name]._load_claimed, "failed Lazy event does not claim")
		H.clear_pack(name, mod)
	end

	-- mutual exclusion
	do
		local name, mod = "rule_mix", "rule_mix_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({
			event = "BufReadPost",
			keys = "<leader>x",
			config = function() end,
		})
		local hit = false
		for _, n in ipairs(H.notifies()) do
			if n.msg:find("mutually exclusive", 1, true) then
				hit = true
			end
		end
		H.truthy(hit, "event+keys rejected")
		H.falsy(Pack.registry[name]._load_claimed, "mixed triggers do not claim")
		H.clear_pack(name, mod)
	end

	-- empty event
	do
		local name, mod = "rule_empty_ev", "rule_empty_ev_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:load({ event = "", config = function() end })
		local hit = false
		for _, n in ipairs(H.notifies()) do
			if n.msg:find("non-empty", 1, true) then
				hit = true
			end
		end
		H.truthy(hit, "empty event rejected")
		H.clear_pack(name, mod)
	end

	-- :lazy rejects keys; does not claim
	do
		local name, mod = "rule_lazy_keys", "rule_lazy_keys_mod"
		H.clear_pack(name, mod)
		H.reset_notifies()
		local h = H.register_stub(name, mod)
		h:lazy({
			keys = "<leader>z",
			config = function() end,
		})
		local rejected = false
		for _, n in ipairs(H.notifies()) do
			if n.level == vim.log.levels.ERROR and n.msg:find("only config/utils/var", 1, true) then
				rejected = true
			end
		end
		H.truthy(rejected, ":lazy rejects keys")
		H.eq(Pack.registry[name]._load_claimed, nil, ":lazy does not claim after reject")
		H.eq(Pack._runners and Pack._runners[name], nil, ":lazy does not register runner after reject")
		H.clear_pack(name, mod)
	end

	restore()
end
