--- Pack API types for lua-language-server; no runtime logic

---@class Pack.SpecTable
---@field src string Repository URL
--- Repository URL
---@field name? string Pack directory name (overrides the URL-derived name)
--- Pack directory name (overrides URL-derived name)
---@field version? string|table Version, branch, tag, or version range (vim.pack)
--- Version, branch, tag, or version range (vim.pack)

---@alias Pack.Spec Pack.SpecTable

---@class Pack.Dep
---@field [1]? string Shorthand repository URL (mutually exclusive with src / spec)
--- Shorthand repo URL (mutually exclusive with src / spec)
---@field src? string Dependency repository URL (mutually exclusive with [1] / spec)
--- Dependency repo URL (mutually exclusive with [1] / spec)
---@field spec? Pack.SpecTable Dependency spec table (mutually exclusive with [1] / src)
--- Dependency spec table (mutually exclusive with [1] / src)
---@field name? string Pack directory name
--- Pack directory name
---@field module? string Require path, required when config is set (not inferred from name)
--- Require path; required when config is set (not inferred from name)
---@field config? fun(plugin: any) Callback after dependency packadd (main plugin utils/var are not injected)
--- Post-packadd callback (main plugin utils/var are not injected)
---@field utils? table<string, string> Dependency-local extra requires, injected into its config only
--- Dependency-local extra requires, injected into this dep config only
---@field build? string|string[]|fun(name: string, dir: string) Build: shell, :Vim command, or function
--- Build: shell, :Vim command, or function
---@field dependencies? (string|Pack.Dep)[] Nested dependencies
--- Nested dependencies
---@field version? string|table Version (when using [1]/src shorthand)
--- Version (when using [1]/src shorthand)

---@class Pack.Plugin
---@field [1]? string Shorthand repository URL (mutually exclusive with spec)
--- Shorthand repo URL (mutually exclusive with spec)
---@field spec? Pack.SpecTable Plugin spec table (required unless [1] is a URL or path/dev is set)
--- Plugin spec table (required unless [1] is a URL or path/dev is set)
---@field module string Require path (required; not inferred from name)
--- Require path (required; not inferred from name)
---@field name? string Pack directory name; usually resolved from spec
--- Pack directory name; usually resolved from spec
---@field path? string Local plugin root (expanded). Symlinked into packpath; skips vim.pack add/update
--- Local plugin root (expanded). Symlinked into packpath; skips vim.pack add/update
---@field dev? boolean Resolve path from vim.g.automic_dev_path/<name> when path omitted; implies local workflow
--- Resolve path from vim.g.automic_dev_path/<name> when path omitted; implies local workflow
---@field dependencies? (string|Pack.Dep)[] Dependency list (URL string or Dep table)
--- Dependency list (URL string or Dep table)
---@field cond? boolean|fun(): boolean When false / returns false, register but do not load (evaluated at register)
--- boolean or function(); false keeps the declaration idle
---@field build? string|string[]|fun(name: string, dir: string) Post-install build: shell, ":TSUpdate", or function
--- Post-install build: shell, ":TSUpdate", or function
---@field lock? boolean Skip :PackUpdate for this plugin and its entire dependency tree when true
--- Skip :PackUpdate for this plugin and its entire dependency tree when true
---@field _registered? boolean Internal: already passed through Pack.register
--- Internal: already passed through Pack.register

--- Autocmd event name for nvim_create_autocmd arg 1
---@alias Pack.AutocmdEvent string

--- :load() options. Pack fields below; remaining keys pass through to nvim_create_autocmd arg 2.
--- `event` / `ft` / `cmd` / `keys` / `colorscheme` are mutually exclusive (pick at most one).
---@class Pack.LoadOpts
---@field event? Pack.AutocmdEvent|Pack.AutocmdEvent[] Trigger event; mutually exclusive with other triggers; omit with no triggers for immediate load
---@field defer? boolean Run `UIEnter` loads via vim.schedule when true (default false); ignored for other events
---@field utils? table<string, string> Extra requires injected into var only, not config; values are module paths required at runtime
---@field var? table<string, any> Data or methods; a function that returns a table can be indexed (`name.field`, `name.a.b.c`) and still called (`name()`); `{ use=true, callback=fun(plugin: any): any }` runs once after setup
---@field config? fun(plugin: any, ...: any): any Setup only; may call var but not utils directly
---@field ft? string|string[] Load on FileType; mutually exclusive with other triggers
---@field cmd? string|string[] Load on user command (shared across packs); mutually exclusive with other triggers
---@field keys? string|table Load on keypress (shared across packs). Function `rhs` receives the plugin module first
---@field colorscheme? string|string[]|true Load on `:colorscheme`; `true` uses pack name (+ module if different)
---@field once? boolean Pass-through autocmd option
---@field pattern? string|string[] Pass-through autocmd option
---@field group? integer|string Pass-through autocmd option
---@field desc? string Pass-through autocmd option
---@field nested? boolean Pass-through autocmd option
---@field buffer? integer Pass-through autocmd option

--- :lazy() options. Only config / utils / var; triggers belong on :load().
---@class Pack.LazyOpts
---@field utils? table<string, string> Extra requires injected into var only, not config
---@field var? table<string, any> Values/methods; a function that returns a table can be indexed (`name.field`, `name.a.b.c`) and still called (`name()`); `{ use=true, callback=fun(plugin: any): any }` runs once after setup
---@field config? fun(plugin: any, ...: any): any Setup callback; receives the required Lua module

---@class Pack.Handle
---@field load fun(self: Pack.Handle, opts?: Pack.LoadOpts): Pack.Handle
---@field lazy fun(self: Pack.Handle, opts?: Pack.LazyOpts): Pack.Handle

---@class Pack.BootHandle
---@field _config? string
---@field _ran boolean
---@field keys fun(self: Pack.BootHandle, entries: table|string): Pack.BootHandle Apply keymaps or load a module returning keymap entries
---@field commands fun(self: Pack.BootHandle, groups: table|string): Pack.BootHandle Create named autocmd groups or load them from a module
---@field options fun(self: Pack.BootHandle, values: table|string): Pack.BootHandle Apply g/opt/diagnostic settings or load them from a module
---@field lsp fun(self: Pack.BootHandle, enable?: table|string, disable?: string[]|string): Pack.BootHandle Configure enabled and disabled LSP servers
---@field autosave fun(self: Pack.BootHandle, opts?: boolean|Pack.AutosaveOpts): Pack.BootHandle Opt-in InsertLeave/TextChanged autosave; pass false to disable
---@field run fun(self: Pack.BootHandle): Pack Run package declaration boot immediately

--- Autosave options for Pack.boot():autosave({ ... })
---@class Pack.AutosaveOpts
---@field enable? boolean When false, disable autosave (default true)
---@field ft? string|string[] Filetypes to exclude
---@field buftype? string|string[] Buftypes to exclude (empty buftype is required to save; non-empty is always skipped)
---@field filename? string|string[] Glob patterns matched against buffer name; matches are excluded

--- User-facing Pack API only (internals omitted so Pack. completion stays clean)
---@class Pack
---@field boot fun(config?: string): Pack.BootHandle
---@field register fun(plugin: Pack.Plugin): Pack.Handle|nil
---@field root fun(markers: string|(string|string[])[]): fun(bufnr: integer, on_dir: fun(dir: string))

---@type Pack
Pack = Pack
