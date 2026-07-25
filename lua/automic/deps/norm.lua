--- Dep note: utils inject into this dep config only (not merged with main :load utils/var)
---
--- Supports:
---   "https://..."                          -- bare URL (packadd only; no module)
---   { "https://...", module = "...", config = fn, utils = { x = "mod.x" } }
---   { src = "https://...", ... }           -- explicit src
---   { spec = { src = "..." }, ... }        -- spec must be a table
---   utils: dep-local extra requires, injected into this dep config only
---   utils: dep-local extra requires, injected into this dep config only
---@param dep any
---@return table
return function(dep)
	local Pack = _G.Pack
	if type(dep) == "string" then
		local name = Pack.parse(dep)
		return {
			spec = { src = dep },
			name = name,
		}
	end

	if type(dep) ~= "table" then
		error("dep must be string or table: " .. vim.inspect(dep))
	end

	if dep.setup ~= nil then
		error("dep.setup was renamed to config: " .. vim.inspect(dep))
	end
	if dep.immediately ~= nil then
		error("dep.immediately was removed (dependencies load with the main plugin): " .. vim.inspect(dep))
	end

	-- String at [1] → src
	local src = dep.src
	local spec = dep.spec
	if type(dep[1]) == "string" then
		if src or spec then
			error("dep: use either [1] URL or src/spec, not both: " .. vim.inspect(dep))
		end
		src = dep[1]
	end

	if type(spec) == "string" then
		error('dep.spec must be a table like { src = "..." }, not a string')
	end
	if type(spec) == "table" then
		-- ok
	elseif type(src) == "string" and src ~= "" then
		spec = { src = src, name = dep.name, version = dep.version }
	else
		error("dep table must have [1] URL, src, or spec={src=...}: " .. vim.inspect(dep))
	end

	local name = dep.name and Pack.parse(dep.name) or Pack.parse(spec)
	local module = dep.module
	if dep.config ~= nil then
		if type(module) ~= "string" or module == "" then
			error("dep with config requires module (string): " .. name)
		end
	elseif module ~= nil and (type(module) ~= "string" or module == "") then
		error("dep.module must be a non-empty string: " .. name)
	end

	local utils = dep.utils
	if utils ~= nil then
		if dep.config == nil then
			error("dep with utils requires config: " .. name)
		end
		if type(utils) ~= "table" then
			error("dep.utils must be a table (name → require path): " .. name)
		end
		for key, path in pairs(utils) do
			if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") or type(path) ~= "string" or path == "" then
				error("dep.utils keys must be identifiers, values non-empty require paths: " .. name)
			end
			if key == "vim" or key == "Pack" or key == "_G" or key == "require" then
				error("dep.utils key `" .. key .. "` is reserved: " .. name)
			end
		end
	end

	return {
		spec = spec,
		name = name,
		module = module,
		config = dep.config,
		utils = utils,
		build = dep.build,
		dependencies = dep.dependencies,
	}
end
