--- Whether vim.pack plugin dir has a complete git repo (clone ok, HEAD usable)
local cache = {}

local function invalidate(path)
	if path then
		cache[path] = nil
	else
		cache = {}
	end
end

local function listen()
	local Pack = _G.Pack
	if not Pack then
		return
	end
	Pack._listeners = Pack._listeners or {}
	if Pack._listeners.healthy then
		return
	end
	Pack._listeners.healthy = true

	vim.api.nvim_create_autocmd("PackChanged", {
		group = vim.api.nvim_create_augroup("PackHealthyCache", { clear = true }),
		callback = function(ev)
			if ev.data and ev.data.path then
				invalidate(ev.data.path)
			else
				invalidate()
			end
		end,
	})
end

--- Resolve .git directory (normal repo or worktree gitfile).
---@param dir string
---@return string|nil
local function git_dir(dir)
	local git = dir .. "/.git"
	if vim.fn.isdirectory(git) == 1 then
		return git
	end
	if vim.fn.filereadable(git) ~= 1 then
		return nil
	end
	local line = vim.fn.readfile(git)[1] or ""
	local gitdir = line:match("^gitdir:%s*(.+)$")
	if not gitdir then
		return nil
	end
	if not vim.startswith(gitdir, "/") then
		gitdir = dir .. "/" .. gitdir
	end
	gitdir = vim.fs.normalize(gitdir)
	if vim.fn.isdirectory(gitdir) == 1 then
		return gitdir
	end
	return nil
end

--- HEAD is readable and (for symbolic refs) the ref file exists — no git subprocess.
---@param git string
---@return boolean
local function head_usable(git)
	local head = git .. "/HEAD"
	if vim.fn.filereadable(head) ~= 1 then
		return false
	end
	local ref = vim.fn.readfile(head)[1] or ""
	local branch = ref:match("^ref:%s*(.+)$")
	if branch then
		return vim.fn.filereadable(git .. "/" .. branch) == 1
	end
	return ref:match("^%x+") ~= nil
end

local function healthy(dir)
	listen()
	if not dir or vim.fn.isdirectory(dir) ~= 1 then
		return false
	end

	local cached = cache[dir]
	if cached ~= nil then
		return cached
	end

	local git = git_dir(dir)
	if not git then
		local git_path = dir .. "/.git"
		if vim.fn.filereadable(git_path) == 1 then
			-- Broken worktree pointer
			cache[dir] = false
			return false
		end
		-- Non-git dir: non-empty is healthy; empty dir is incomplete
		for _ in vim.fs.dir(dir) do
			cache[dir] = true
			return true
		end
		cache[dir] = false
		return false
	end

	local ok = head_usable(git)
	cache[dir] = ok
	return ok
end

return setmetatable({
	healthy = healthy,
	invalidate = invalidate,
}, {
	__call = function(_, dir)
		return healthy(dir)
	end,
})
