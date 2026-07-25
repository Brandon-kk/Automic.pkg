local H = require("tests.harness")
local replay = require("automic.load.event_replay")

return function()
	H.suite("event_replay.capture chain")

	local state = replay.capture("FileType", 1, { filetype = "lua" })
	H.eq(#state, 3, "FileType expands to 3 states")
	H.eq(state[1].event, "BufReadPre", "oldest first: BufReadPre")
	H.eq(state[2].event, "BufReadPost", "then BufReadPost")
	H.eq(state[3].event, "FileType", "then FileType")
	H.eq(state[3].data, { filetype = "lua" }, "data only on first captured event")
	H.eq(state[2].data, nil, "chained events drop data")
	H.eq(state[3].exclude_set, nil, "FileType has no exclude_set")
	H.truthy(type(state[2].exclude_set) == "table", "BufReadPost has exclude_set for O(1) skip")

	local only = replay.capture("UIEnter", 0, nil)
	H.eq(#only, 1, "unknown event is single-state")
	H.eq(only[1].event, "UIEnter", "UIEnter preserved")
end
