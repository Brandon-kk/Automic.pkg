--- Interpret a function-build's return values.
---
--- Success:
---   - no return / any non-false value
---   - returned Task-like `{ wait = function }` → waited; throw = failure
---   - returned Task-like `{ pwait = function }` → false = failure
--- Failure:
---   - pcall error (including `:wait()` throw)
---   - first return `false` (common `:pwait()` style used by plugin managers)
local M = {}

---@param r1 any first return (or pcall error when ok=false)
---@param r2 any second return
---@param timeout_ms? integer wait budget for Task-like returns (extra args are ignored by plain wait())
---@return boolean success
---@return any err
function M.from_returns(r1, r2, timeout_ms)
	if r1 == false then
		return false, r2 or "build returned false"
	end
	if type(r1) == "table" and type(r1.wait) == "function" then
		local wok, werr = pcall(r1.wait, r1, timeout_ms)
		if not wok then
			return false, werr
		end
		return true
	end
	if type(r1) == "table" and type(r1.pwait) == "function" then
		local pok, perr = r1.pwait(r1, timeout_ms)
		if pok == false then
			return false, perr or "build pwait failed"
		end
	end
	return true
end

---@param ok boolean pcall status
---@param r1 any
---@param r2 any
---@param timeout_ms? integer wait budget for Task-like returns
---@return boolean success
---@return any err
function M.from_pcall(ok, r1, r2, timeout_ms)
	if not ok then
		return false, r1
	end
	return M.from_returns(r1, r2, timeout_ms)
end

return M
