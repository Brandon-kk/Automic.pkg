--- deps submodule barrel (internal require; not mounted on Pack wholesale)
return {
	norm = require("automic.deps.norm"),
	depname = require("automic.deps.depname"),
	walk = require("automic.deps.walk"),
	track = require("automic.deps.track"),
	needed = require("automic.deps.needed"),
	protect = require("automic.deps.protect").protect,
	users = require("automic.deps.protect").users,
}
