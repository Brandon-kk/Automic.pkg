.PHONY: test
# Portable: only needs `nvim` on PATH (macOS / Linux / Windows).
test:
	nvim --headless -u NONE -c "luafile tests/run.lua"
