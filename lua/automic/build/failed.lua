--- Persist failed builds for :PackReBuild (atomic write vs multi-instance clobber)
---
--- Record shape: { [name]: { fp: string?, rev: string?, err: string, ts: number } }
--- fp/rev identify the build fingerprint + package HEAD the failure belongs to;
--- legacy array-of-names files are still readable.
local path = require("automic.util.platform").state_path("pack-hooks-build-failed.json")

local M = {}
--- Session-local cache prevents concurrent builds from losing updates during read-modify-write.
local cache = nil

---@return table<string, any>
local function read()
	if cache then
		return cache
	end
	if vim.fn.filereadable(path) == 0 then
		cache = {}
		return cache
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(decoded) ~= "table" then
		cache = {}
		return cache
	end
	-- Normalize legacy array format (["a","b"]) into map format.
	if decoded[1] ~= nil then
		local set = {}
		for _, name in ipairs(decoded) do
			if type(name) == "string" and name ~= "" then
				set[name] = { err = "build failed" }
			end
		end
		cache = set
		return cache
	end
	local normalized = {}
	for name, v in pairs(decoded) do
		if v and type(name) == "string" and name ~= "" then
			if type(v) == "table" then
				normalized[name] = v
			else
				normalized[name] = { err = "build failed" }
			end
		end
	end
	cache = normalized
	return cache
end

---@param set table<string, any>
local function write(set)
	cache = set
	local tmp = path .. ".tmp." .. tostring(vim.uv.os_getpid())
	vim.fn.writefile({ vim.json.encode(set) }, tmp)
	vim.uv.fs_rename(tmp, path)
end

---@return string[]
function M.list()
	local set = read()
	local list = {}
	for name in pairs(set) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

---@param name string
---@return { fp: string?, rev: string?, err: string, ts: number }?
function M.get(name)
	return read()[name]
end

--- True when a recorded failure belongs to the same build fingerprint + package HEAD,
--- i.e. re-running the build now would deterministically fail again.
---@param name string
---@param fp string build fingerprint (stamp.fingerprint)
---@param rev string package HEAD (stamp.package_rev); empty string = unknown HEAD
---@return boolean
function M.matches(name, fp, rev)
	local entry = read()[name]
	if not entry or type(entry) ~= "table" then
		return false
	end
	return entry.fp == fp and entry.rev == rev
end

---@param name string
---@param err? any error text to persist for diagnostics
---@param fp? string build fingerprint at failure time
---@param rev? string package HEAD at failure time
function M.add(name, err, fp, rev)
	local set = read()
	local msg = err == nil and "build failed" or tostring(err)
	-- Keep single-line diagnostics; full output goes to :messages at failure time.
	msg = (msg:gsub("[\r\n]+", " "))
	if #msg > 400 then
		msg = msg:sub(1, 400) .. "…"
	end
	set[name] = { fp = fp, rev = rev, err = msg, ts = os.time() }
	write(set)
end

---@param name string
function M.remove(name)
	local set = read()
	if set[name] then
		set[name] = nil
		write(set)
	end
end

return M
