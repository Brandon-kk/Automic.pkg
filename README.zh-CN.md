# Automic.pkg

基于 `vim.pack` 的 Neovim 包声明与装载编排。

[English](README.md) · **简体中文**

---

权威说明见 `:help automic.pkg`。

## 环境要求

- Neovim 0.12 或更高版本
- `PATH` 中可用的 `git`
- 同一配置适用于 macOS、Linux 与 Windows

## 安装

在 Neovim 中执行一次：

```lua
local dest = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt", "Automic.pkg")
vim.fn.mkdir(vim.fs.dirname(dest), "p")
if vim.fn.isdirectory(dest) == 0 then
  vim.fn.system({
    "git", "clone", "https://github.com/Brandon-kk/Automic.pkg", dest,
  })
end
```

在 `init.lua` 中：

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

请勿对 Automic.pkg 再次调用 `Pack.register()`。

---

## 启动链（`Pack.boot`）

| 调用 | 作用 |
| ---- | ---- |
| `Pack.boot("packages.configs")` | 装载 `lua/packages/configs/` 下的全部声明模块 |
| `:options(...)` | 应用全局设置（`g` / `opt` / 诊断 / 高亮 / 插件全局项） |
| `:keys(..., " ")` | 定义键位映射；可选第二参数设置 `mapleader` |
| `:commands(...)` | 定义 autocmd 组 |
| `:lsp(...)` | 按文件类型关联语言服务器 |
| `:autosave()` | 启用自动保存 |
| `:run()` | 完成启动链（每会话须调用一次） |

参数可为返回表的模块名，或内联表。

---

## 登记（`Pack.register`）

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

| 字段 | 作用 |
| ---- | ---- |
| `"https://…"` 或 `spec.src` | 安装用的仓库地址 |
| `spec.name` | 安装目录名 |
| `spec.version` | 钉选分支、标签、提交或版本范围 |
| `module` | `config` 与 `require()` 所用的 Lua 模块（必填） |
| `path` | 本地包根目录；跳过远程安装 |
| `dev = true` | 将本地根解析为 `vim.g.automic_dev_path/<name>` |
| `dependencies` | 依赖包列表 |
| `cond` | 为 `false`（或函数返回 `false`）时跳过安装与装载 |
| `build` | 安装/更新后执行；function/shell 在 `config` 前同步完成且仅成功才盖章；`:Vim` 在 init 后执行 |
| `lock = true` | `:PackUpdate` 时排除该包及其依赖树 |

本地包：

```lua
Pack.register({
  path = vim.fn.expand("~/code/my-plugin.nvim"),
  module = "my-plugin",
}):load({ config = function(p) p.setup({}) end })
```

开发根目录：

```lua
vim.g.automic_dev_path = vim.fn.expand("~/code")
Pack.register({
  dev = true,
  spec = { name = "my-plugin.nvim" },
  module = "my-plugin",
}):lazy({ config = function(p) p.setup({}) end })
```

`lock = true` 表示 Automic 不更新该依赖树。远程包的修订记录仍可由 `vim.pack` 写入 `nvim-pack-lock.json`。

---

## 装载策略（`:load` / `:lazy`）

**`:load`** — 立即装载，或在单一触发条件下装载：

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

| 字段 | 作用 |
| ---- | ---- |
| *无触发器* | 立即装载 |
| `event` | 在指定 autocmd 时装载 |
| `keys` | 在指定按键时装载 |
| `cmd` | 在指定用户命令时装载 |
| `ft` | 在指定文件类型时装载 |
| `colorscheme` | 在 `:colorscheme` 时装载（`true` 表示使用包名） |
| `defer` | 仅当 `event = "UIEnter"` 时：延后一个 `vim.schedule` 周期装载 |
| `config` | 调用 `plugin.setup(...)`，或向 `setup` 传入表 |
| `utils` | 供 `var` 函数使用的附加模块 |
| `var` | `config` 的环境；`{ use = true, callback = … }` 在 setup 成功后执行一次 |

每个包在每会话中至多允许一次成功的 `:load` 或 `:lazy`。

**`:lazy`** — UI 就绪后装载（不接受触发器）：

```lua
:lazy({
  config = function(plugin)
    plugin.setup({})
  end,
})
```

仅允许 `config`、`utils`、`var`。事件、按键、命令、文件类型或配色触发须使用 `:load`。

`require("module")` 将装载以该 `module` 登记的包。

---

## 命令

| 命令 | 作用 |
| ---- | ---- |
| `:PackUpdate[!] [name…]` | 更新包（`!` 跳过确认） |
| `:PackStatus [name…]` | 报告可用更新（不下载） |
| `:PackReBuild[!] [name…]` | 再次执行 `build`（`!` 强制） |
| `:PackLoadProfile` | 显示装载耗时 |
| `:PackHealth [name…]` | 打开健康报告（`q` 关闭） |
| `:PackClean[!]` | 移除当前声明中不存在的包 |

安装、更新、清理或重建成功后，会话可能自动重启（先保存已命名缓冲区）。

---

## 辅助接口

| 调用 | 作用 |
| ---- | ---- |
| `Pack.root({ ".git", "package.json" })` | 供 LSP `root_dir` 使用的项目根回调 |
| `Pack.path("name")` | 包的磁盘路径 |
| `Pack.available("name")` | 包是否已安装 |

---

## 参考配置

https://github.com/Brandon-kk/Automic.nvim

## 许可证

[MIT License](LICENSE)
