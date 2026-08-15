--- Local path / PackHealth smoke checks.
return function()
	local H = require("tests.harness")
	H.suite("local path + PackHealth")

	local Pack = _G.Pack
	local restore = H.capture_notify()
	local local_install = require("automic.install.local")
	local health = require("automic.health")

	-- Fake plugin root
	local root = vim.fn.tempname() .. "_automic_local_plug"
	vim.fn.mkdir(root, "p")
	vim.fn.writefile({ "return {}" }, root .. "/lua_placeholder.txt")
	-- Minimal rtp-ish layout not required for link itself
	vim.fn.mkdir(root .. "/lua", "p")
	vim.fn.writefile({ "return { ok = true }" }, root .. "/lua/local_smoke_mod.lua")

	do
		H.reset_notifies()
		local name, mod = "local_smoke", "local_smoke_mod"
		H.clear_pack(name, mod)
		local h = Pack.register({
			path = root,
			spec = { name = name },
			module = mod,
		})
		H.truthy(h, "register local path")
		H.eq(Pack.registry[name].path, vim.fs.normalize(root), "path normalized")
		H.eq(Pack.registry[name].lock, true, "local packs default lock=true")
		H.truthy(local_install.is_local_spec(Pack.registry[name].spec), "spec marked local")

		local ok, err = local_install.link(name, Pack.registry[name].path)
		H.truthy(ok, "link ok: " .. tostring(err))
		H.truthy(Pack.path(name), "Pack.path finds linked pack")
		H.truthy(Pack.available(name), "local link is available")

		-- Partition drops locals from remote list
		local remote = local_install.partition({ Pack.registry[name].spec })
		H.eq(#remote, 0, "local specs excluded from vim.pack.add list")

		H.clear_pack(name, mod)
		-- Best-effort cleanup of pack link
		pcall(local_install.unlink, name)
		pcall(vim.fn.delete, local_install.target(name))
	end

	do
		H.reset_notifies()
		local bad = Pack.register({
			path = root .. "_missing",
			module = "nope",
		})
		H.falsy(bad, "missing path rejected")
	end

	do
		local items = health.collect()
		H.truthy(#items > 0, "health.collect returns items")
		local saw_nvim, saw_symlink_warn = false, false
		for _, item in ipairs(items) do
			if item.name == "neovim" then
				saw_nvim = true
			end
			if item.name == "windows-symlink" then
				saw_symlink_warn = true
			end
		end
		H.truthy(saw_nvim, "health reports neovim")
		H.falsy(saw_symlink_warn, "no OS-degraded health warn")
	end

	pcall(vim.fn.delete, root, "rf")
	restore()
end
