# Automic.pkg

基于 `vim.pack` 的 Neovim 包编排层



[English](README.md) · **简体中文**

---

## 范围


| 层           | 职责                              |
| ----------- | ------------------------------- |
| `vim.pack`  | 克隆、更新、删除、锁文件、会话登记               |
| Automic.pkg | 声明、依赖图、装载策略、配置、启动链、构建、健康检查、装载剖析 |


权威说明见 `:help automic.pkg`（`doc/automic.pkg.txt`）。

生命周期：

```text
boot → declare → install/sync → load → observe
```



## 目录

- [环境](#环境)
- [安装](#安装)
- [启动链](#启动链)
- [登记](#登记)
- [装载](#装载)
- [懒加载](#懒加载)
- [激活路径](#激活路径)
- [命令](#命令)
- [会话重启](#会话重启)
- [参考配置](#参考配置)
- [许可证](#许可证)

---



## 环境

- Neovim 0.12+
- `PATH` 中可用的 `git`（Unix `$PATH` / Windows `Path`）
- 可用的 `:packadd`

支持 **macOS、Linux、Windows**（官方 Neovim 构建）。同一套声明在三端完整支持——不按系统拆配置，也没有降级模式。

---



## 安装

**任意系统**（在 Neovim 里执行一次）：

```lua
local dest = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt", "Automic.pkg")
vim.fn.mkdir(vim.fs.dirname(dest), "p")
if vim.fn.isdirectory(dest) == 0 then
  vim.fn.system({
    "git", "clone", "https://github.com/Brandon-kk/Automic.pkg", dest,
  })
end
```

然后在 `init.lua`：

```lua
vim.cmd.packadd("Automic.pkg")
```

Shell / PowerShell 克隆只是同一目标路径的可选写法：`stdpath("data")/site/pack/core/opt/Automic.pkg`。

Automic.pkg 会自行写入 `Pack.registry`。勿对 Automic.pkg 再次调用 `Pack.register()`。

本地 / `dev` 包在三端都会链入该目录（Unix 目录符号链接；Windows junction）。Shell 形式的 `build` 在三端均经 `vim.system` 按 argv 执行——用 `build = { "cmd", "arg" }`、`:Ex` 或 Lua 函数，保证同一声明到处有效。

测试：在仓库根目录执行 `make test`，或 `nvim --headless -u NONE -c "luafile tests/run.lua"`（只需 Neovim）。

---



## 启动链

```lua
Pack.boot("packages.configs")
  :options("core.options")
  :keys("core.keymaps", " ")
  :commands("core.commands")
  :lsp("core.lsp")
  :autosave()
  :run()
```


| 调用 | 参数 | 类型 | 作用 |
| --- | --- | --- | --- |
| `Pack.boot` | `module` | `string?` | `stdpath("config")/lua` 下的声明模块目录 |
| `:options` | `values` | `table` / `string` | 仅全局：`g` / `opt` / `diagnostic` / `hl`；`plugins` 为函数（或函数表），写第三方全局配置 API（不限于 `vim.g`）；拒绝 `wo`/`bo` |
| `:keys` | `entries` [, `mapleader`] | `table` / `string` [, `string`] | 键位；可选第二参设置 `vim.g.mapleader`；条目可带 `event` 回填 |
| `:commands` | `groups` | `table` / `string` | 具名 augroup |
| `:lsp` | `enable` [, `disable`] | 见帮助 | filetype → server |
| `:autosave` | `opts` | `boolean` / `table?` | 可选自动保存 |
| `:run` | — | — | 每会话必须调用一次 |


声明布局：`Pack.boot("packages.configs")` 按字母序 `require` `…/lua/packages/configs/` 下全部 `*.lua`。

未知链式方法发出警告并返回 `self`，`:run()` 仍会执行。

声明装载失败时跳过安装同步。

---



## 登记

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


| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `[1]` | `string` | 仓库 URL；与 `spec` 互斥 |
| `spec.src` | `string` | 仓库 URL |
| `spec.name` | `string` | 安装目录名 |
| `spec.version` | `string` / `vim.VersionRange` | 钉选修订：分支名、标签、提交哈希，或 `vim.version.range(...)`；转发给 `vim.pack` |
| `module` | `string` | 必填；`config` 与 `require()` 所用模块 |
| `path` | `string` | 本地根目录；三端均链入 packpath；不经 `vim.pack.add` |
| `dev` | `boolean` | 省略 `path` 时解析为 `vim.g.automic_dev_path/<name>` |
| `dependencies` | 列表 | URL 字符串或依赖表；可嵌套；拒绝环 |
| `cond` | `boolean` / `fun(): boolean` | 仅在登记时求值。`false` 或函数返回 `false`（或函数报错）→ idle（不进入 active、不装载）；`true` → 参与安装与装载 |
| `build` | `string` / `string[]` / `fun(name, path)` | 安装或更新后的构建；字符串可为 shell 或 Ex 命令（如 `:TSUpdate`） |
| `lock` | `boolean` | 为 `true` 时该包及其依赖树跳过 `:PackUpdate`；`path`/`dev` 默认 `true` |


本地包：

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


| 机制                    | 归属         | 作用                   |
| --------------------- | ---------- | -------------------- |
| `lock = true`         | Automic    | `:PackUpdate` 排除该依赖树 |
| `nvim-pack-lock.json` | `vim.pack` | 远程安装的已解析修订           |


若 pack 路径上已存在非链接的真实目录，不予覆盖。

成功返回 `Pack.Handle`；校验失败返回 `nil`。`Pack.register({})` 为无操作句柄。

---



## 装载

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

| 规则 | 契约 |
| --- | --- |
| 无触发器 | 立即装载 |
| 触发器 | `event` / `keys` / `cmd` / `ft` / `colorscheme` 至多其一 |
| 占用 | 每包每会话至多一次成功的 `:load()` 或 `:lazy()` |
| 共享 `keys` / `cmd` | 首次使用时装载全部声明方 |

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `event` | `string` / `string[]` | 装载触发用的 autocmd 事件；与其它触发器互斥。禁止 `"Lazy"`（改用 `:lazy()`）。可附带 `once` / `pattern` / `group` / `desc` / `nested` / `buffer`（无 `event` 时这些键被忽略） |
| `keys` | `string` / `table` | 按键触发（可多包共享）。形式：`"lhs"`，或 `{ mode, lhs, rhs?, opts? }`，或 `{ lhs = …, mode = …, … }`。函数形式的 `rhs` 首参为插件模块 |
| `cmd` | `string` / `string[]` | 用户命令名触发（可多包共享） |
| `ft` | `string` / `string[]` | `FileType` 模式触发 |
| `colorscheme` | `string` / `string[]` / `true` | `:colorscheme` 触发；`true` 表示使用包名（若与 `module` 不同则两者皆可） |
| `defer` | `boolean` | 仅当 `event = "UIEnter"` 时生效：延后一个 `vim.schedule` 再装载 |
| `config` | `fun(plugin)` / `table` | 只能 `plugin.setup(...)`（传入的 `plugin` 为仅含 `setup` 的代理）；或直接给 `setup` 的表。可读 `var`，**不能**读 `utils` |
| `utils` | `table<string, string>` | 标识符 → 模块路径；装载时 `require`，仅注入 `var` 函数环境，不进入 `config` 环境 |
| `var` | `table` | 供 `config` 与 `var` 内函数使用。返回值为表的函数仍可调用（`name()`），也可直接取字段，含嵌套（`name.field`、`name.a.b.c`）。条目 `{ use = true, callback = fun(plugin) }` 在 setup 成功后执行一次。插件的 `vim.g` 全局项请写在 `:options`，不要写在 `config` |

触发装载成功后，将重放激活事件，使装载期间注册的 autocmd 能够观测到该事件（`FileType` → `BufReadPost` → `BufReadPre`）。无 augroup 的 `BufRead*` 不会被选择性重放。

---



## 懒加载

```lua
:lazy({
  config = function(plugin) plugin.setup({}) end,
})
```


| 字段       | 类型         |
| -------- | ---------- |
| `config` | `function` |
| `utils`  | `table`    |
| `var`    | `table`    |


UI 就绪后统一装载。适用于非首屏关键、且无需 `event` / `keys` / `cmd` / `ft` / `colorscheme` 触发的包。仅接受上表字段；触发器须使用 `:load()`。与 `:load()` 共享每会话一次占用规则。

---



## 激活路径


| 路径                | 行为                                |
| ----------------- | --------------------------------- |
| `:load` / `:lazy` | 见上                                |
| `require(module)` | 经 `Pack.modules` 解析并执行已调度的 runner |
| 共享 `keys` / `cmd` | 全部声明方                             |


`Pack.root(markers)` → 供 LSP `root_dir` 使用的 `fun(bufnr, on_dir)`（始终追加 `.git`）。

内省：`Pack.parse`、`Pack.path`、`Pack.available`。

---



## 命令


| 命令                        | 行为                         |
| ------------------------- | -------------------------- |
| `:PackUpdate[!] [name…]`  | 经 `vim.pack` 更新；`!` 跳过确认缓冲 |
| `:PackStatus [name…]`     | 离线检查可用更新                   |
| `:PackReBuild[!] [name…]` | 执行 `build`；`!` 强制          |
| `:PackLoadProfile`        | 装载剖析界面                     |
| `:PackHealth [name…]`     | 本地健康检查全屏页（`q` 关闭）          |
| `:PackClean[!]`           | 清理孤儿包；`!` 允许空 registry     |


`:PackHealth` 检查项：Neovim ≥ 0.12、`git`、启动状态、`vim.g.automic_dev_path`、`nvim-pack-lock.json`，以及各包的安装 / `path` / `lock` / `version` / 缺失占用 / 重复 `module` / 过期构建戳。

---



## 会话重启

在安装、移除、已确认更新（含构建）或成功的 `:PackReBuild` 之后：

1. 静默保存已命名缓冲区
2. 执行 `:restart`

构建失败则取消重启。在 `--headless`、`-es` 或设置了 `vim.g.vscode` 时不自动重启。

---



## 参考配置

完整可用的 Neovim 配置示例（基于 Automic.pkg）：

https://github.com/Brandon-kk/Automic.nvim

---



## 许可证

[MIT License](LICENSE)