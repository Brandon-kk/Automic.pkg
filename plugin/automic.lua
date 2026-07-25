if vim.g.loaded_automic_pkg then
	return
end
vim.g.loaded_automic_pkg = true

-- Wall-clock start for manager bootstrap (shown in :PackLoadProfile).
vim.g._automic_profile_t0 = vim.uv.hrtime()

require("automic")
