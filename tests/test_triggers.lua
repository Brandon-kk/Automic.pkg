local H = require("tests.harness")
local triggers = require("automic.load.triggers")

return function()
	H.suite("triggers.validate / kinds")

	H.eq(triggers.kinds({}), {}, "empty opts → no kinds")
	H.eq(triggers.kinds({ ft = "lua" }), { "ft" }, "ft kind")
	H.eq(triggers.kinds({ cmd = "Foo" }), { "cmd" }, "cmd kind")
	H.eq(triggers.kinds({ keys = "<leader>x" }), { "keys" }, "keys kind")
	H.eq(triggers.kinds({ colorscheme = "theme" }), { "colorscheme" }, "colorscheme kind")
	H.eq(triggers.kinds({ ft = "lua", cmd = "Foo" }), { "ft", "cmd" }, "multiple kinds listed")

	local ok, err = triggers.validate({ ft = {} })
	H.falsy(ok, "empty ft rejected")
	H.truthy(err and err:find("empty"), "empty ft message")

	ok, err = triggers.validate({ keys = {} })
	H.falsy(ok, "empty keys rejected")

	ok, err = triggers.validate({ cmd = "" })
	H.falsy(ok, "empty cmd string rejected")

	ok, err = triggers.validate({ colorscheme = true })
	H.truthy(ok, "colorscheme=true ok")

	ok, err = triggers.validate({ ft = "lua", cmd = "Foo" })
	H.truthy(ok, "validate does not enforce mutual exclusion (handle does)")

	H.falsy(triggers.has({ keys = {} }), "has() false for empty keys")
	H.truthy(triggers.has({ keys = "f" }), "has() true for bare key")
end
