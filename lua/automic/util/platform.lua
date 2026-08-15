--- Cross-platform helpers (macOS / Linux / Windows).
--- Used to implement one correct path/link strategy per OS — not fallbacks.
local M = {}

---@return boolean
function M.is_windows()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

--- Absolute path suitable for uv.fs_symlink / junctions (trailing slash stripped).
---@param path string
---@return string
function M.abspath(path)
	path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	-- Windows junctions / comparisons are happier without a trailing slash.
	if #path > 1 and (path:sub(-1) == "/" or path:sub(-1) == "\\") then
		path = path:sub(1, -2)
	end
	return path
end

--- Compare two paths after absolute normalize (case-insensitive on Windows).
---@param a string
---@param b string
---@return boolean
function M.same_path(a, b)
	a, b = M.abspath(a), M.abspath(b)
	if M.is_windows() then
		return a:lower() == b:lower()
	end
	return a == b
end

---@param path string
---@return boolean
function M.is_absolute(path)
	if type(path) ~= "string" or path == "" then
		return false
	end
	if M.is_windows() then
		return path:match("^%a:[/\\]") ~= nil or path:match("^\\\\") ~= nil
	end
	return path:sub(1, 1) == "/"
end

--- Join under stdpath("data")/site/pack/...
---@param ... string
---@return string
function M.data_pack(...)
	return vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", ...)
end

--- Join under stdpath("state")/...
---@param ... string
---@return string
function M.state_path(...)
	return vim.fs.joinpath(vim.fn.stdpath("state"), ...)
end

--- Join under stdpath("config")/...
---@param ... string
---@return string
function M.config_path(...)
	return vim.fs.joinpath(vim.fn.stdpath("config"), ...)
end

return M
