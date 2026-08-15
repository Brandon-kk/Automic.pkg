<div align="center">
  <img src="assets/automic-logo.png" width="128" style="border-radius: 50%;" alt="Automic.pkg logo">
  <h1>Automic.pkg</h1>
  <p>Package declaration and load orchestration for Neovim on <code>vim.pack</code></p>
  <p>
    <a href="https://neovim.io"><img src="https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white" alt="Neovim 0.12+"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License"></a>
  </p>
  <p><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>
</div>

---

Authoritative reference: `:help automic.pkg`

## Requirements

- Neovim 0.12 or later
- `git` available on `PATH`
- Identical configuration on macOS, Linux, and Windows

## Installation

Execute once inside Neovim:

```lua
local dest = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt", "Automic.pkg")
vim.fn.mkdir(vim.fs.dirname(dest), "p")
if vim.fn.isdirectory(dest) == 0 then
  vim.fn.system({
    "git", "clone", "https://github.com/Brandon-kk/Automic.pkg", dest,
  })
end
```

In `init.lua`:

```lua
vim.cmd.packadd("Automic.pkg")

Pack.boot("packages.configs")
  :options("core.options")
  :keys("core.keymaps", " ")
  :commands("core.commands")
  :lsp("core.lsp")
  :autosave()
  :run()
```

Do not call `Pack.register()` for Automic.pkg.

---

## Boot (`Pack.boot`)

| Call | Purpose |
| ---- | ------- |
| `Pack.boot("packages.configs")` | Load all declaration modules under `lua/packages/configs/` |
| `:options(...)` | Apply global settings (`g` / `opt` / diagnostics / highlights / plugin globals) |
| `:keys(..., " ")` | Define keymaps; optional second argument sets `mapleader` |
| `:commands(...)` | Define autocmd groups |
| `:lsp(...)` | Associate filetypes with language servers |
| `:autosave()` | Enable autosave |
| `:run()` | Complete the boot sequence (required once per session) |

Arguments may be module names that return a table, or tables supplied inline.

---

## Registration (`Pack.register`)

```lua
Pack.register({
  "https://github.com/user/plugin.nvim",
  module = "plugin",
}):load({
  config = function(plugin)
    plugin.setup({})
  end,
})
```

| Field | Purpose |
| ----- | ------- |
| `"https://…"` or `spec.src` | Repository URL for installation |
| `spec.name` | Installation directory name |
| `spec.version` | Pin to a branch, tag, commit, or version range |
| `module` | Lua module used by `config` and `require()` (required) |
| `path` | Local package root; skips remote installation |
| `dev = true` | Resolve local root as `vim.g.automic_dev_path/<name>` |
| `dependencies` | Dependent packages |
| `cond` | When `false` (or a function returning `false`), skip installation and load |
| `build` | Command, argument list, or function executed after install or update |
| `lock = true` | Exclude this package and its dependency tree from `:PackUpdate` |

Local package:

```lua
Pack.register({
  path = vim.fn.expand("~/code/my-plugin.nvim"),
  module = "my-plugin",
}):load({ config = function(p) p.setup({}) end })
```

Development root:

```lua
vim.g.automic_dev_path = vim.fn.expand("~/code")
Pack.register({
  dev = true,
  spec = { name = "my-plugin.nvim" },
  module = "my-plugin",
}):lazy({ config = function(p) p.setup({}) end })
```

`lock = true` excludes the tree from Automic updates. Remote revision pins may still be recorded in `nvim-pack-lock.json` by `vim.pack`.

---

## Load policy (`:load` / `:lazy`)

**`:load`** — load immediately, or upon a single trigger:

```lua
:load({
  event = "BufReadPost",
  utils = { menu = "plugin.menu" },
  var = {
    opts = { enabled = true },
    apply = function(plugin)
      plugin.setup(opts)
    end,
  },
  config = function(plugin)
    apply(plugin)
  end,
})
```

| Field | Purpose |
| ----- | ------- |
| *(no trigger)* | Load immediately |
| `event` | Load on the specified autocmd |
| `keys` | Load on the specified key |
| `cmd` | Load on the specified user command |
| `ft` | Load for the specified filetypes |
| `colorscheme` | Load on `:colorscheme` (`true` uses the package name) |
| `defer` | With `event = "UIEnter"` only: defer load by one `vim.schedule` turn |
| `config` | Invoke `plugin.setup(...)`, or pass a table to `setup` |
| `utils` | Additional modules available to `var` functions |
| `var` | Environment for `config`; `{ use = true, callback = … }` runs once after successful setup |

At most one successful `:load` or `:lazy` is permitted per package per session.

**`:lazy`** — load after the UI is ready (triggers are not accepted):

```lua
:lazy({
  config = function(plugin)
    plugin.setup({})
  end,
})
```

Only `config`, `utils`, and `var` are valid. Use `:load` for event, key, command, filetype, or colorscheme triggers.

`require("module")` loads the package registered under that `module`.

---

## Commands

| Command | Purpose |
| ------- | ------- |
| `:PackUpdate[!] [name…]` | Update packages (`!` skips confirmation) |
| `:PackStatus [name…]` | Report available updates without downloading |
| `:PackReBuild[!] [name…]` | Re-run `build` (`!` forces) |
| `:PackLoadProfile` | Display load timing |
| `:PackHealth [name…]` | Open the health report (`q` closes) |
| `:PackClean[!]` | Remove packages absent from the current declarations |

After installation, update, cleanup, or a successful rebuild, the session may restart (named buffers are saved first).

---

## Helpers

| Call | Purpose |
| ---- | ------- |
| `Pack.root({ ".git", "package.json" })` | Project-root callback for LSP `root_dir` |
| `Pack.path("name")` | On-disk path of a package |
| `Pack.available("name")` | Whether a package is installed |

---

## Example configuration

https://github.com/Brandon-kk/Automic.nvim

## License

[MIT License](LICENSE)
