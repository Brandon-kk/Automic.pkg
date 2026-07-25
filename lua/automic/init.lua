--- Public plugin-manager API mounted on global Pack
---
--- Configs: register / boot / root (updates via :PackUpdate)
require("automic.pack_types")

local profile = require("automic.profile")
local path_mod = require("automic.deps.path")

---@type Pack
_G.Pack = vim.tbl_extend("force", _G.Pack or {
	building = {},
	inited = {},
	loaded = {},
	loading = {},
	disabled = {},
	var_used = {},
	active = {},
	idle = {},
	registry = {},
	refs = {},
	-- Session maps grow with registrations; re-register updates in place.
	-- Full teardown is a Neovim restart (no Pack.reset API by design).
	_listeners = {},
}, {
	parse = require("automic.deps.parse"),
	path = function(name)
		return path_mod(name)
	end,
	available = require("automic.deps.available"),
	norm = require("automic.deps.norm"),
	register = require("automic.register"),
	boot = require("automic.boot"),
	profile = profile,
	root = require("automic.util.root"),
})

_G.Pack = require("automic.util.seal_pack")(_G.Pack)

require("automic.lazy").setup()
profile.setup()
require("automic.load.module_loader").setup()
require("automic.load.colorscheme").setup()
require("automic.commands")()

-- Register the manager itself so full :PackUpdate includes Automic.pkg.
_G.Pack.register({
	spec = {
		src = "https://github.com/Brandon-kk/Automic.pkg",
		name = "Automic.pkg",
	},
	module = "automic",
})
profile.finish_self()

return _G.Pack
