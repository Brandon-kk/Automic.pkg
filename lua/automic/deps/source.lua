--- Resolve a repository source into a full clone URL.
---
--- GitHub shorthand ("owner/repo") is expanded with `method`:
---   method = "git" (default) -> git@github.com:owner/repo.git   (SSH)
---   method = "http"         -> https://github.com/owner/repo
---
--- Full URLs already containing a scheme (https://, http://, ssh://, git://)
--- or scp-like SSH URLs (git@host:…) pass through unchanged.
local M = {}

---@param src string
---@return string owner
---@return string repo
local function github_shorthand(src)
	return src:match("^([%w%._-]+)/([%w%._-]+)$")
end

---@param src string
---@return boolean
local function is_full_url(src)
	return src:find("://", 1, true) ~= nil or src:match("^[%w._-]+@") ~= nil
end

---@param src string
---@param method? string "git" (default) or "http"
---@return string url
function M.expand(src, method)
	if type(src) ~= "string" or src == "" then
		error("source must be a non-empty string")
	end
	method = method or "git"
	if method ~= "git" and method ~= "http" then
		error('source method must be "git" or "http", got: ' .. tostring(method))
	end
	if is_full_url(src) then
		return src
	end
	local owner, repo = github_shorthand(src)
	if not owner then
		error("invalid source (expected \"owner/repo\" or a full URL): " .. src)
	end
	if method == "http" then
		return "https://github.com/" .. owner .. "/" .. repo
	end
	return "git@github.com:" .. owner .. "/" .. repo .. ".git"
end

return M
