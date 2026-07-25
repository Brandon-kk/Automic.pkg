local H = require("tests.harness")
local cs = require("automic.load.colorscheme")

return function()
	H.suite("colorscheme.normalize / bind")

	H.eq(cs.normalize("mocha", "catppuccin", "catppuccin"), { "mocha" }, "string scheme")
	H.eq(cs.normalize(true, "catppuccin", "catppuccin"), { "catppuccin" }, "true without distinct module")
	H.eq(cs.normalize(true, "theme.nvim", "theme"), { "theme.nvim", "theme" }, "true with distinct module")
	H.eq(cs.normalize({ "a", "", "b" }, "p", "m"), { "a", "b" }, "list filters empties")
	H.eq(cs.normalize("", "p", "m"), {}, "empty string → empty")

	local Pack = _G.Pack
	Pack._colorschemes = {}
	cs.bind("plug_a", { "shared", "only_a" })
	cs.bind("plug_b", { "shared" })
	H.eq(Pack._colorschemes.shared, { "plug_a", "plug_b" }, "shared scheme lists both packs")
	H.eq(Pack._colorschemes.only_a, { "plug_a" }, "private scheme")

	cs.bind("plug_a", { "retargeted" })
	H.eq(Pack._colorschemes.only_a, nil, "unbind removed old private scheme")
	H.eq(Pack._colorschemes.shared, { "plug_b" }, "unbind removed pack from shared")
	H.eq(Pack._colorschemes.retargeted, { "plug_a" }, "new scheme bound")

	------------------------------------------------------------------------
	-- event loads always nested so :colorscheme inside load fires Pre
	------------------------------------------------------------------------
	H.suite("colorscheme.event nested")
	local restore = H.capture_notify()
	local local_install = require("automic.install.local")

	local function make_pack(name, mod)
		local root = vim.fn.tempname() .. "_" .. name
		vim.fn.mkdir(root .. "/lua", "p")
		vim.fn.writefile({ "return { setup = function() end }" }, root .. "/lua/" .. mod .. ".lua")
		return root
	end

	local function cleanup(name, mod, root)
		H.clear_pack(name, mod)
		cs.unbind(name)
		pcall(vim.fn.delete, local_install.target(name))
		if root then
			pcall(vim.fn.delete, root, "rf")
		end
	end

	do
		local theme, theme_mod = "nest_cs_theme", "nest_cs_theme_mod"
		local follow, follow_mod = "nest_cs_follow", "nest_cs_follow_mod"
		cleanup(theme, theme_mod)
		cleanup(follow, follow_mod)

		local theme_root = make_pack(theme, theme_mod)
		local follow_root = make_pack(follow, follow_mod)
		local th = Pack.register({
			path = theme_root,
			spec = { name = theme },
			module = theme_mod,
		})
		local fh = Pack.register({
			path = follow_root,
			spec = { name = follow },
			module = follow_mod,
		})
		H.truthy(select(1, local_install.link(theme, theme_root)), "link theme pack")
		H.truthy(select(1, local_install.link(follow, follow_root)), "link follow pack")

		th:load({
			event = "User",
			pattern = "AutomicNestCsLoad",
			once = true,
			config = function() end,
			var = {
				colorscheme = {
					use = true,
					callback = function()
						vim.cmd.colorscheme("habamax")
					end,
				},
			},
		})
		fh:load({
			colorscheme = "habamax",
			config = function() end,
		})

		vim.api.nvim_exec_autocmds("User", { pattern = "AutomicNestCsLoad", modeline = false })
		H.eq(Pack.inited[theme], true, "theme pack inited from User event")
		H.eq(Pack.inited[follow], true, "colorscheme pack loads via nested ColorSchemePre")

		cleanup(theme, theme_mod, theme_root)
		cleanup(follow, follow_mod, follow_root)
		pcall(vim.api.nvim_del_augroup_by_name, "PackLoad:" .. theme .. ":User:AutomicNestCsLoad")
	end

	restore()
end
