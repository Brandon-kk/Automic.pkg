<div align="center">
  <img src="assets/automic-logo.png" width="128" style="border-radius: 50%;" alt="Automic.pkg logo">
  <h1>Automic.pkg</h1>
  <p>Orchestration layer for Neovim packages on <code>vim.pack</code></p>
  <p>
    <a href="https://neovim.io"><img src="https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white" alt="Neovim 0.12+"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License"></a>
  </p>
  <p><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>
</div>

---

## Scope

| Layer | Responsibility |
| ----- | -------------- |
| `vim.pack` | Clone, update, delete, lockfile, session registration |
| Automic.pkg | Declaration, dependency graph, load policy, setup, boot, builds, health, profile |

Authoritative reference: `:help automic.pkg` (`doc/automic.pkg.txt`).

Lifecycle:

```text
boot → declare → install/sync → load → observe
```

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Boot](#boot)
- [Register](#register)
- [Load](#load)
- [Lazy load](#lazy-load)
- [Activation](#activation)
- [Commands](#commands)
- [Restart](#restart)
- [Example config](#example-config)
- [License](#license)

---

## Requirements

- Neovim 0.12+
- `git` on `PATH` (Unix `$PATH` / Windows `Path`)
- `:packadd` available

Supported environments: **macOS, Linux, and Windows** (official Neovim builds). One declaration set — full support on every OS; no OS-specific config and no degraded modes.

---

## Installation

**Any OS** (run once inside Neovim):

```lua
local dest = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt", "Automic.pkg")
vim.fn.mkdir(vim.fs.dirname(dest), "p")
if vim.fn.isdirectory(dest) == 0 then
  vim.fn.system({
    "git", "clone", "https://github.com/Brandon-kk/Automic.pkg", dest,
  })
end
```

Then in `init.lua`:

```lua
vim.cmd.packadd("Automic.pkg")
```

Shell / PowerShell clones are optional equivalents of the same `git clone` into `stdpath("data")/site/pack/core/opt/Automic.pkg`.

Automic.pkg registers itself into `Pack.registry`. Do not call `Pack.register()` for Automic.pkg again.

Local / `dev` packs are linked into that tree on every OS (directory symlink on Unix; junction on Windows). Shell `build` runs as argv via `vim.system` on every OS — use `build = { "cmd", "arg" }`, an `:Ex` command, or a Lua function so the same declaration is valid everywhere.

Tests: `make test` or `nvim --headless -u NONE -c "luafile tests/run.lua"` from the repo root (Neovim only).

---

## Boot

```lua
Pack.boot("packages.configs")
  :options("core.options")
  :keys("core.keymaps", " ")
  :commands("core.commands")
  :lsp("core.lsp")
  :autosave()
  :run()
```

| Call | Argument | Type | Role |
| ---- | -------- | ---- | ---- |
| `Pack.boot` | `module` | `string?` | Directory of declaration modules under `stdpath("config")/lua` |
| `:options` | `values` | `table` / `string` | Global only: `g` / `opt` / `diagnostic` / `hl`; `plugins` is a function (or map of functions) for third-party global config APIs (not limited to `vim.g`); `wo`/`bo` rejected |
| `:keys` | `entries` [, `mapleader`] | `table` / `string` [, `string`] | Keymaps; optional 2nd arg sets `vim.g.mapleader`; optional `event` backfill |
| `:commands` | `groups` | `table` / `string` | Named augroups |
| `:lsp` | `enable` [, `disable`] | see help | Filetype → server mapping |
| `:autosave` | `opts` | `boolean` / `table?` | Opt-in autosave |
| `:run` | — | — | Required once |

Declaration layout: `Pack.boot("packages.configs")` requires every `*.lua` under `…/lua/packages/configs/` in alphabetical order.

Unknown chain methods warn and return `self`; `:run()` still executes.

If declaration loading fails, install is skipped.

---

## Register

```lua
Pack.register({
  "https://example.com/user/plugin.nvim",
  module = "plugin",
  dependencies = { … },
  cond = true,
  build = ":Cmd",
  lock = false,
}):load({ … })
```

| Field | Type | Notes |
| ----- | ---- | ----- |
| `[1]` | `string` | Repository URL; exclusive with `spec` |
| `spec.src` | `string` | Repository URL |
| `spec.name` | `string` | Install directory name |
| `spec.version` | `string` / `vim.VersionRange` | Pin: branch, tag, commit, or `vim.version.range(...)`; forwarded to `vim.pack` |
| `module` | `string` | Required; module for `config` and `require()` |
| `path` | `string` | Local root; linked into packpath on every OS; skips `vim.pack.add` |
| `dev` | `boolean` | When `path` is omitted, resolve `vim.g.automic_dev_path/<name>` |
| `dependencies` | list of URL string or dep table | Nested trees; cycles rejected |
| `cond` | `boolean` / `fun(): boolean` | Evaluated only at register time. `false`, a function returning `false`, or a throwing function → idle (not active, not loaded); `true` → install and load |
| `build` | `string` / `string[]` / `fun(name, path)` | Post-install / post-update build; string may be shell or Ex (e.g. `:TSUpdate`) |
| `lock` | `boolean` | When `true`, skip this package and its tree on `:PackUpdate`; default `true` for `path`/`dev` |

Local packs:

```lua
Pack.register({
  path = vim.fn.expand("~/code/my-plugin.nvim"),
  module = "my-plugin",
}):load({ config = function(p) p.setup({}) end })
```

```lua
vim.g.automic_dev_path = vim.fn.expand("~/code")
Pack.register({
  dev = true,
  spec = { name = "my-plugin.nvim" },
  module = "my-plugin",
}):lazy({ config = function(p) p.setup({}) end })
```

| Mechanism | Owner | Role |
| --------- | ----- | ---- |
| `lock = true` | Automic | Exclude tree from `:PackUpdate` |
| `nvim-pack-lock.json` | `vim.pack` | Resolved git revisions |

A real (non-link) directory already at the pack path is not overwritten.

Returns `Pack.Handle`, or `nil` on validation failure. `Pack.register({})` is a no-op handle.

---

## Load

```lua
:load({
  event = "BufReadPost",
  once = true,
  utils = { menu = "plugin.menu" },
  var = {
    opts = { enabled = true },
    apply = function(plugin)
      plugin.setup(opts)
    end,
    hook = {
      use = true,
      callback = function(plugin)
        plugin.refresh()
      end,
    },
  },
  config = function(plugin)
    apply(plugin)
  end,
})
```

| Rule | Contract |
| ---- | -------- |
| No trigger | Immediate load |
| Triggers | At most one of `event` / `keys` / `cmd` / `ft` / `colorscheme` |
| Claim | One successful `:load()` or `:lazy()` per package per session |
| Shared `keys` / `cmd` | Every claiming package loads on first use |

| Field | Type | Notes |
| ----- | ---- | ----- |
| `event` | `string` / `string[]` | Autocmd event(s) that trigger load; exclusive with other triggers. `"Lazy"` is rejected (use `:lazy()`). May carry `once` / `pattern` / `group` / `desc` / `nested` / `buffer` (ignored when `event` is absent) |
| `keys` | `string` / `table` | Key trigger (shared). Forms: `"lhs"`, `{ mode, lhs, rhs?, opts? }`, or `{ lhs = …, mode = …, … }`. Function `rhs` receives the plugin module first |
| `cmd` | `string` / `string[]` | User-command name(s) (shared) |
| `ft` | `string` / `string[]` | `FileType` pattern(s) |
| `colorscheme` | `string` / `string[]` / `true` | Trigger on `:colorscheme`; `true` uses the pack name (and `module` when distinct) |
| `defer` | `boolean` | Only with `event = "UIEnter"`: load on the next `vim.schedule` turn |
| `config` | `fun(plugin)` / `table` | Setup-only: call `plugin.setup(...)` on a setup-only proxy, or pass a table to `setup`. May read `var` via `setfenv`; does **not** see `utils` |
| `utils` | `table<string, string>` | Identifier → module path; required at load; injected into the `var` environment only |
| `var` | `table` | Environment for `config` and `var` functions. A function that returns a table stays callable (`name()`) and can be indexed, including nested fields (`name.field`, `name.a.b.c`). Entry `{ use = true, callback = fun(plugin) }` runs once after successful setup |

After trigger load, the activating event is re-executed so autocmds registered during load observe it (`FileType` → `BufReadPost` → `BufReadPre`). Group-less `BufRead*` handlers are not selectively re-fired.

---

## Lazy load

```lua
:lazy({
  config = function(plugin) plugin.setup({}) end,
})
```

| Field | Type |
| ----- | ---- |
| `config` | `function` |
| `utils` | `table` |
| `var` | `table` |

Loads once after the UI is ready. Use for packages that are not required for the first screen and do not need `event` / `keys` / `cmd` / `ft` / `colorscheme` triggers. Only the fields above are accepted; triggers belong on `:load()`. Shares the one-claim-per-session rule with `:load()`.

---

## Activation

| Path | Behavior |
| ---- | -------- |
| `:load` / `:lazy` | As above |
| `require(module)` | Resolves `Pack.modules`; runs scheduled runner |
| Shared `keys` / `cmd` | All claimants |

`Pack.root(markers)` → `fun(bufnr, on_dir)` for LSP `root_dir` (`.git` always appended).

Introspection: `Pack.parse`, `Pack.path`, `Pack.available`.

---

## Commands

| Command | Behavior |
| ------- | -------- |
| `:PackUpdate[!] [name…]` | Update via `vim.pack`; `!` skips confirmation buffer |
| `:PackStatus [name…]` | Offline update check |
| `:PackReBuild[!] [name…]` | Run `build`; `!` forces |
| `:PackLoadProfile` | Load-profile UI |
| `:PackHealth [name…]` | Local health tab (`q` closes) |
| `:PackClean[!]` | Prune orphans; `!` allows empty registry |

`:PackHealth` checks Neovim ≥ 0.12, `git`, boot status, `vim.g.automic_dev_path`, `nvim-pack-lock.json`, and per-plugin install / `path` / `lock` / `version` / missing claim / duplicate `module` / stale build.

---

## Restart

After install, removal, confirmed update (including builds), or successful `:PackReBuild`:

1. Silently save named buffers  
2. `:restart`

Failed builds cancel restart. Suppressed under `--headless`, `-es`, and when `vim.g.vscode` is set.

---

## Example config

A full working Neovim config that uses Automic.pkg:

https://github.com/Brandon-kk/Automic.nvim

---

## License

[MIT License](LICENSE)
