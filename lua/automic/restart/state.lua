return {
	installed = {},
	---@type string[]
	built = {},
	---@type string[]
	updated = {},
	---@type string[]
	removed = {},
	---@type uv.uv_timer_t|nil
	update_restart_timer = nil,
}
