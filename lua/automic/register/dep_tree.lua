local notify_once = require("automic.util.notify_once")
local norm = require("automic.deps.norm")
local track = require("automic.deps.track")
local listen = require("automic.build.listen")

local register_dep_tree

register_dep_tree = function(dep, consumer_name, disabled, ensure_spec)
	local Pack = _G.Pack
	local ok, item = pcall(norm, dep)
	if not ok then
		notify_once(
			"register:dep:" .. tostring(dep),
			"register dependency resolution failed (" .. consumer_name .. "): " .. tostring(item),
			vim.log.levels.ERROR
		)
		return
	end

	local parent = Pack.profile.plugins[consumer_name]
	Pack.profile.track_dependency(item, consumer_name, parent and parent.source)
	track(dep, consumer_name)

	if disabled then
		if item.dependencies then
			for _, nested in ipairs(item.dependencies) do
				register_dep_tree(nested, consumer_name, disabled, ensure_spec)
			end
		end
		return
	end

	if item.spec then
		ensure_spec(Pack.active, item.spec)
	end
	if item.build then
		listen(item.name, item.build)
	end
	if item.dependencies then
		for _, nested in ipairs(item.dependencies) do
			register_dep_tree(nested, consumer_name, disabled, ensure_spec)
		end
	end
end

return register_dep_tree
