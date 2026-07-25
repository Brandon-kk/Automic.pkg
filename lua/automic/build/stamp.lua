--- build fingerprint stamp: kept under state (not in plugin dir; resists forged .build_done)
--- Stamp tracks both the build definition and the package git HEAD so source
--- updates invalidate even when the build callback bytecode is unchanged.
local M = {}

-- Session memo: fingerprint(build) and package_rev(dir) are hot on install fast path.
local fp_memo = {}
local rev_memo = {}

---@param dir string
---@return string
local function stamp_path(dir)
	-- Path hash avoids stamp collisions for same basename under different packs
	local key = vim.fn.sha256(vim.fs.normalize(dir)):sub(1, 16)
	local name = vim.fs.basename(vim.fs.normalize(dir))
	return vim.fn.stdpath("state") .. "/pack-hooks-build/" .. name .. "-" .. key .. ".stamp"
end

--- Best-effort HEAD revision for a pack directory (empty when not a git checkout).
---@param dir string
---@return string
function M.package_rev(dir)
	dir = vim.fs.normalize(dir)
	local cached = rev_memo[dir]
	if cached ~= nil then
		return cached
	end

	local git = dir .. "/.git"
	local rev = ""
	if vim.fn.isdirectory(git) ~= 1 then
		if vim.fn.filereadable(git) ~= 1 then
			rev_memo[dir] = ""
			return ""
		end
		local line = vim.fn.readfile(git)[1] or ""
		local gitdir = line:match("^gitdir:%s*(.+)$")
		if not gitdir then
			rev_memo[dir] = ""
			return ""
		end
		if not vim.startswith(gitdir, "/") then
			gitdir = dir .. "/" .. gitdir
		end
		git = vim.fs.normalize(gitdir)
		if vim.fn.isdirectory(git) ~= 1 then
			rev_memo[dir] = ""
			return ""
		end
	end

	local head = git .. "/HEAD"
	if vim.fn.filereadable(head) ~= 1 then
		rev_memo[dir] = ""
		return ""
	end
	local ref = vim.fn.readfile(head)[1] or ""
	local branch = ref:match("^ref:%s*(.+)$")
	if branch then
		local ref_path = git .. "/" .. branch
		if vim.fn.filereadable(ref_path) ~= 1 then
			rev_memo[dir] = ""
			return ""
		end
		rev = (vim.fn.readfile(ref_path)[1] or ""):match("^%x+") or ""
	else
		rev = ref:match("^%x+") or ""
	end
	rev_memo[dir] = rev
	return rev
end

---@param build_cmd string|string[]|function
---@return string
function M.fingerprint(build_cmd)
	local hit = fp_memo[build_cmd]
	if hit then
		return hit
	end

	local base
	if type(build_cmd) == "function" then
		local ok, dumped = pcall(string.dump, build_cmd)
		if ok and type(dumped) == "string" then
			base = "fn:" .. vim.fn.sha256(dumped)
		else
			local info = debug.getinfo(build_cmd, "S")
			base = ("fn:%s:%s:%s"):format(info.source or "?", info.linedefined or "?", info.lastlinedefined or "?")
		end
	elseif type(build_cmd) == "table" then
		local parts = {}
		for i, v in ipairs(build_cmd) do
			if type(v) ~= "string" then
				error("build argv[" .. i .. "] must be string")
			end
			parts[i] = v
		end
		base = table.concat(parts, "\0")
	else
		base = tostring(build_cmd)
	end
	local fp = vim.fn.sha256(base)
	fp_memo[build_cmd] = fp
	return fp
end

---@param path string
---@param fp string
---@param rev string
---@return boolean
local function matches(path, fp, rev)
	if vim.fn.filereadable(path) == 0 then
		return false
	end
	local lines = vim.fn.readfile(path)
	if lines[1] ~= fp then
		return false
	end
	-- Legacy one-line stamps (no rev) are treated as stale so rebuilds refresh
	-- commit-bound native artifacts (e.g. blink.cmp fuzzy libs).
	return lines[2] == rev
end

---@param dir string
---@param build_cmd string|string[]|function
function M.current(dir, build_cmd)
	if not dir or vim.fn.isdirectory(dir) ~= 1 then
		return false
	end
	local fp = M.fingerprint(build_cmd)
	local rev = M.package_rev(dir)
	return matches(stamp_path(dir), fp, rev)
end

---@param dir string
---@param build_cmd string|string[]|function
function M.write(dir, build_cmd)
	dir = vim.fs.normalize(dir)
	rev_memo[dir] = nil
	local path = stamp_path(dir)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local fp = M.fingerprint(build_cmd)
	local rev = M.package_rev(dir)
	local tmp = path .. ".tmp." .. tostring(vim.uv.os_getpid())
	vim.fn.writefile({ fp, rev }, tmp)
	vim.uv.fs_rename(tmp, path)
end

function M.clear(dir)
	dir = vim.fs.normalize(dir)
	rev_memo[dir] = nil
	pcall(vim.fn.delete, stamp_path(dir))
end

return M
