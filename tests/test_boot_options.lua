--- Pack.boot:options global + plugin vim.g keys; keys mapleader; config setup-only.
return function()
	local H = require("tests.harness")
	local core = require("automic.boot.core")
	local call_config = require("automic.load.call_config")

	H.suite("boot.options global + keys mapleader")

	do
		local prev = vim.g.mapleader
		core.keys({
			{ "n", "<Leader>__pack_leader_probe", function() end },
		}, "\\")
		H.eq(vim.g.mapleader, "\\", "K01 keys second arg sets mapleader")
		pcall(vim.keymap.del, "n", "<Leader>__pack_leader_probe")
		vim.g.mapleader = prev
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
	end

	do
		local prev = vim.g.mapleader
		vim.g.mapleader = " "
		core.keys({
			{ "n", "<Leader>__pack_leader_keep", function() end },
		})
		H.eq(vim.g.mapleader, " ", "K02 omitting mapleader leaves leader unchanged")
		pcall(vim.keymap.del, "n", "<Leader>__pack_leader_keep")
		vim.g.mapleader = prev
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootKeys")
	end

	do
		core.options({
			opt = { number = true, showmode = false },
			hl = {
				PackBootHlTest = { fg = "#ff0000", bold = true },
				PackBootHlLink = "Normal",
			},
			plugins = function()
				vim.g.pack_boot_plugin_global = { a = "xxx" }
			end,
		})
		H.eq(vim.o.number, true, "K03 opt sets global number")
		H.eq(vim.o.showmode, false, "K04 opt sets showmode")
		H.eq(vim.g.pack_boot_plugin_global.a, "xxx", "K05 plugins() can set vim.g")
		local hl = vim.api.nvim_get_hl(0, { name = "PackBootHlTest", link = false })
		H.truthy(hl and hl.fg ~= nil, "K06 hl creates highlight")
		local link = vim.api.nvim_get_hl(0, { name = "PackBootHlLink" })
		H.eq(link.link, "Normal", "K07 hl string value links")

		vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
		local hl2 = vim.api.nvim_get_hl(0, { name = "PackBootHlTest", link = false })
		H.truthy(hl2 and hl2.fg ~= nil, "K08 hl re-applied on ColorScheme")

		vim.g.pack_boot_plugin_global = nil
		pcall(vim.api.nvim_del_augroup_by_name, "PackBootHighlights")
		pcall(vim.api.nvim_set_hl, 0, "PackBootHlTest", {})
		pcall(vim.api.nvim_set_hl, 0, "PackBootHlLink", {})
	end

	do
		local marked = false
		core.options({
			plugins = {
				mark = function()
					marked = true
				end,
			},
		})
		H.truthy(marked, "K05b plugins map of functions runs")
	end

	do
		local restore = H.capture_notify()
		H.reset_notifies()
		core.options({
			wo = { number = true },
			bo = { tabstop = 2 },
			random_key = true,
		})
		local hit_wo, hit_bo, hit_unknown = false, false, false
		for _, n in ipairs(H.notifies()) do
			if n.msg:find("`wo`", 1, true) then
				hit_wo = true
			end
			if n.msg:find("`bo`", 1, true) then
				hit_bo = true
			end
			if n.msg:find("`random_key`", 1, true) then
				hit_unknown = true
			end
		end
		H.truthy(hit_wo, "K09 wo rejected")
		H.truthy(hit_bo, "K10 bo rejected")
		H.truthy(hit_unknown, "K11 unknown key rejected (use plugins)")
		restore()
	end

	H.suite("call_config setup-only")

	do
		local got
		local mod = {
			setup = function(opts)
				got = opts
			end,
			other = function() end,
		}
		local ok = call_config(function(plugin)
			plugin.setup({ enabled = true })
		end, mod)
		H.truthy(ok, "C01 setup via proxy ok")
		H.eq(got, { enabled = true }, "C02 setup received opts")
	end

	do
		local got
		local mod = {
			setup = function(opts)
				got = opts
			end,
		}
		local ok = call_config({ answer = 42 }, mod)
		H.truthy(ok, "C03 table config ok")
		H.eq(got, { answer = 42 }, "C04 table passed to setup")
	end

	do
		local mod = {
			setup = function() end,
			refresh = function() end,
		}
		local ok, err = call_config(function(plugin)
			plugin.refresh()
		end, mod)
		H.falsy(ok, "C05 non-setup method rejected")
		H.truthy(tostring(err):find("only plugin.setup", 1, true), "C06 error mentions setup-only")
	end

	do
		local mod = {
			setup = function() end,
		}
		local ok, err = call_config(function(plugin)
			plugin.flag = true
		end, mod)
		H.falsy(ok, "C07 assignment rejected")
		H.truthy(tostring(err):find("cannot assign", 1, true), "C08 error mentions assign")
	end
end
