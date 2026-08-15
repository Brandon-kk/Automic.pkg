--- Headless entry: nvim --headless -u NONE -c "luafile tests/run.lua" -c "qa!"
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

-- Fresh load of Automic (plugin/ may not run under -u NONE).
package.loaded.automic = nil
vim.g.loaded_automic_pkg = nil
require("automic")

local H = require("tests.harness")
print("Automic.pkg tests")
print("-----------------")

local suites = {
	"tests.test_triggers",
	"tests.test_event_replay",
	"tests.test_colorscheme",
	"tests.test_ensure",
	"tests.test_load_rules",
	"tests.test_autosave",
	"tests.test_boot_keys",
	"tests.test_smoke_matrix",
	"tests.test_local_health",
	"tests.test_build_fresh",
	"tests.test_build_env",
}

for _, mod in ipairs(suites) do
	package.loaded[mod] = nil
	local ok, fn_or_err = pcall(require, mod)
	if not ok then
		H.failed = H.failed + 1
		io.stderr:write("FAIL load " .. mod .. ": " .. tostring(fn_or_err) .. "\n")
	else
		local ran, err = pcall(fn_or_err)
		if not ran then
			H.failed = H.failed + 1
			io.stderr:write("FAIL suite " .. mod .. ": " .. tostring(err) .. "\n")
		end
	end
end

print(string.format("-----------------\n%d passed, %d failed", H.passed, H.failed))
if H.failed > 0 then
	os.exit(1)
end
os.exit(0)
