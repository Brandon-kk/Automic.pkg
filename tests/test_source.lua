--- GitHub shorthand source expansion: source module, dep norm, Pack.boot method, Pack.register
local H = require("tests.harness")
local source = require("automic.deps.source")
local norm = require("automic.deps.norm")
local Handle = require("automic.boot.handle")
local Pack = _G.Pack

return function()
	H.suite("source.expand shorthand")

	H.eq(
		source.expand("saghen/blink.cmp"),
		"git@github.com:saghen/blink.cmp.git",
		"default method is git SSH"
	)
	H.eq(
		source.expand("saghen/blink.cmp", "git"),
		"git@github.com:saghen/blink.cmp.git",
		"explicit git method"
	)
	H.eq(
		source.expand("saghen/blink.cmp", "http"),
		"https://github.com/saghen/blink.cmp",
		"http method is HTTPS"
	)
	H.eq(
		source.expand("https://github.com/a/b.nvim"),
		"https://github.com/a/b.nvim",
		"https URL passes through"
	)
	H.eq(
		source.expand("https://github.com/a/b.nvim", "git"),
		"https://github.com/a/b.nvim",
		"full URL ignores method"
	)
	H.eq(
		source.expand("git@github.com:a/b.nvim.git"),
		"git@github.com:a/b.nvim.git",
		"scp-like SSH URL passes through"
	)
	H.eq(
		source.expand("ssh://git@example.com/a/b"),
		"ssh://git@example.com/a/b",
		"ssh:// URL passes through"
	)

	local function fails(fn, label)
		local ok = pcall(fn)
		H.falsy(ok, label)
	end
	fails(function() source.expand("no-slash") end, "single segment rejected")
	fails(function() source.expand("a/b/c") end, "multiple slashes rejected")
	fails(function() source.expand("a/b", "svn") end, "bad method rejected")
	fails(function() source.expand("") end, "empty source rejected")

	H.suite("Pack.boot method option")

	H.eq(Pack.source_method, "git", "global default method is git")
	Handle.new("nonexistent.config.prefix", { method = "http" })
	H.eq(Pack.source_method, "http", "boot opts switches global method to http")
	Handle.new("nonexistent.config.prefix", { method = "git" })
	H.eq(Pack.source_method, "git", "boot opts switches global method back to git")

	local release = H.capture_notify()
	H.truthy(Handle.new("x", { method = "svn" }), "invalid method still returns handle")
	release()
	H.eq(Pack.source_method, "git", "invalid method leaves global unchanged")
	H.truthy(#H.notifies() > 0, "invalid boot method notifies")
	H.reset_notifies()

	release = H.capture_notify()
	H.truthy(Handle.new("x", "nope"), "non-table opts still returns handle")
	release()
	H.truthy(#H.notifies() > 0, "non-table boot opts notifies")
	H.reset_notifies()

	H.suite("source via dep norm (boot method)")

	Pack.source_method = "git"
	local dep = norm("saghen/blink.lib")
	H.eq(dep.spec.src, "git@github.com:saghen/blink.lib.git", "bare dep string expands to SSH")
	H.eq(dep.name, "blink.lib", "dep name derived from expanded URL")

	Pack.source_method = "http"
	local dep_http = norm({ "rafamadriz/friendly-snippets" })
	H.eq(dep_http.spec.src, "https://github.com/rafamadriz/friendly-snippets", "dep [1] under http boot method")
	H.eq(dep_http.name, "friendly-snippets", "dep http name")

	Pack.source_method = "git"
	local dep_src = norm({ src = "onsails/lspkind.nvim" })
	H.eq(dep_src.spec.src, "git@github.com:onsails/lspkind.nvim.git", "dep src shorthand defaults to SSH")

	local dep_full = norm("https://github.com/x/y.nvim")
	H.eq(dep_full.spec.src, "https://github.com/x/y.nvim", "dep full URL unchanged")

	local ok_dep_nested, dep_nested = pcall(norm, {
		"a/b",
		dependencies = { "c/d", { "e/f" } },
	})
	H.truthy(ok_dep_nested, "nested deps without method accepted")
	H.eq(dep_nested.dependencies[1], "c/d", "nested dep spec passes through untouched")

	local bad_dep_ok = pcall(norm, { "a/b", method = "http" })
	H.falsy(bad_dep_ok, "dep.method rejected")

	H.suite("source via Pack.register (boot method)")

	Pack.source_method = "git"
	local h1 = Pack.register({ "saghen/blink.cmp", module = "src_test_blink" })
	H.truthy(h1, "register shorthand accepted")
	H.eq(
		Pack.registry["blink.cmp"].spec.src,
		"git@github.com:saghen/blink.cmp.git",
		"registry src expanded to SSH"
	)
	H.falsy(rawget(Pack.registry["blink.cmp"], "method") ~= nil, "no method field in registry")

	Pack.source_method = "http"
	local h2 = Pack.register({ "owner/http-plug", module = "src_test_http" })
	H.truthy(h2, "register shorthand under http boot method")
	H.eq(
		Pack.registry["http-plug"].spec.src,
		"https://github.com/owner/http-plug",
		"registry src expanded to HTTPS"
	)

	Pack.source_method = "git"
	local h3 = Pack.register({
		spec = { src = "owner/spec-plug", name = "spec-plug" },
		module = "src_test_spec",
	})
	H.truthy(h3, "register spec.src shorthand accepted")
	H.eq(
		Pack.registry["spec-plug"].spec.src,
		"git@github.com:owner/spec-plug.git",
		"spec.src shorthand expanded"
	)

	local h4 = Pack.register({ "https://example.com/full-url", module = "src_test_full" })
	H.truthy(h4, "register full URL accepted")
	H.eq(
		Pack.registry["full-url"].spec.src,
		"https://example.com/full-url",
		"full URL untouched"
	)

	H.falsy(
		Pack.register({ "bad-source", module = "src_test_bad" }),
		"invalid shorthand rejected"
	)
	H.falsy(
		Pack.register({ "a/b", method = "http", module = "src_test_badmethod" }),
		"per-register method rejected"
	)

	Pack.source_method = "http"
	local h5 = Pack.register({
		"xzbdmw/colorful-menu.nvim",
		module = "src_test_cm",
		dependencies = { "nvim-tree/nvim-web-devicons", { "onsails/lspkind.nvim" } },
	})
	H.truthy(h5, "register with shorthand dependencies accepted under http method")
	Pack.source_method = "git"

	H.clear_pack("blink.cmp", "src_test_blink")
	H.clear_pack("http-plug", "src_test_http")
	H.clear_pack("spec-plug", "src_test_spec")
	H.clear_pack("full-url", "src_test_full")
	H.clear_pack("colorful-menu.nvim", "src_test_cm")
end
