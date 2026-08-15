--- var env: functions that return a table can be indexed and still called.
return function()
	local H = require("tests.harness")
	local build_env = require("automic.load.build_env")

	H.suite("build_env var result index")

	do
		local _, config_env, _, err = build_env.build({}, {
			palette = function()
				return { text = "#cdd6f4", overlay0 = "#6c7086" }
			end,
		})
		H.falsy(err, "E01 build succeeds")
		H.eq(type(config_env.palette), "function", "E02 palette stays a function")
		H.eq(config_env.palette.text, "#cdd6f4", "E03 index reads returned table")
		H.eq(config_env.palette().overlay0, "#6c7086", "E04 call still returns the table")
	end

	do
		local _, config_env = build_env.build({}, {
			palette = function()
				return { text = "#cdd6f4" }
			end,
			label = function()
				return { fg = palette.text }
			end,
		})
		H.eq(config_env.label.fg, "#cdd6f4", "E05 var can index another var result")
	end

	do
		local _, config_env = build_env.build({}, {
			add = function(a, b)
				return a + b
			end,
		})
		H.eq(config_env.add(1, 2), 3, "E06 arity functions still call")
		H.eq(config_env.add.x, nil, "E07 indexing a non-table result is nil")
	end

	do
		local _, config_env = build_env.build({}, {
			opts = { enabled = true },
			name = function()
				return "plain"
			end,
		})
		H.eq(config_env.opts.enabled, true, "E08 plain table var unchanged")
		H.eq(config_env.name(), "plain", "E09 non-table return still callable")
		H.eq(config_env.name.len, nil, "E10 non-table return has no fields")
	end

	do
		local _, config_env = build_env.build({}, {
			tree = function()
				return { a = { b = { c = 1 } } }
			end,
		})
		H.eq(config_env.tree.a.b.c, 1, "E11 deep index walks nested tables")
		H.eq(config_env.tree.a.b, { c = 1 }, "E12 intermediate nested table")
		H.eq(config_env.tree().a.b.c, 1, "E13 call then deep index")
	end
end
