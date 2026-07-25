--- Parse and validate plugin directory name from vim.pack spec
---
--- Reject path traversal and glob metacharacters

---@param name string
---@return string
local function validate_name(name)
	if type(name) ~= "string" or name == "" then
		error("invalid pack name: empty")
	end
	name = name:gsub("%.git$", "")
	if name == "." or name == ".." then
		error("invalid pack name: " .. name)
	end
	-- No path separators / globs; allow typical plugin name chars
	if name:find("[/\\]") or name:find("[%*?%[%]]") then
		error("invalid pack name (path/glob chars): " .. name)
	end
	if not name:match("^[%w][%w%._%-]*$") then
		error("invalid pack name (charset): " .. name)
	end
	return name
end

local function parse(spec)
	local name
	if type(spec) == "table" then
		if spec.name then
			name = spec.name
		else
			spec = spec.src or spec[1]
		end
	end
	if not name then
		if type(spec) ~= "string" or spec == "" then
			error("invalid pack spec: " .. vim.inspect(spec))
		end
		name = spec:match("([^/]+)$")
		if not name then
			error("cannot parse plugin name from spec: " .. spec)
		end
	end
	return validate_name(name)
end

return parse
