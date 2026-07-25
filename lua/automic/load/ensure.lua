--- Internal: ensure a scheduled package has been packadd'd and configured.
--- Used by module loader, shared triggers, and colorscheme — not a public Pack API.
---@param name string
---@param force_sync? boolean default true (triggers need sync before replay)
---@return boolean ready
return function(name, force_sync)
	local Pack = _G.Pack
	if type(name) ~= "string" or name == "" then
		return false
	end
	if Pack.disabled[name] then
		return false
	end
	if Pack.inited[name] == true and Pack.loaded[name] == true then
		return true
	end
	-- Nested ensure during an in-flight :load (e.g. config → require): do not re-enter.
	-- packadd may already have succeeded; treat rtp as usable for the outer load.
	if Pack.loading[name] then
		return Pack.loaded[name] == true
	end
	local runner = Pack._runners and Pack._runners[name]
	if type(runner) ~= "function" then
		return false
	end
	if force_sync == nil then
		force_sync = true
	end
	runner(force_sync)
	return Pack.inited[name] == true and Pack.loaded[name] == true
end
