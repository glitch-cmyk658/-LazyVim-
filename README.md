# 我的 Neovim 配置（LazyVim）

基于 [LazyVim](https://www.lazyvim.org/) v14 的个人配置，平时写 C/C++、Python 和一点脚本。这份配置主要给我自己在换机器时恢复环境用，不是通用模板，别人拷过去不一定顺手。

## 环境

- Neovim 0.12+
- WSL Ubuntu（终端里跑 tmux，文件管理器用 yazi）
- 主题 tokyonight-moon，背景透明

## 结构

- `lua/config/`：`lazy.lua`（LazyVim 加载与 extras）、`options.lua`、`keymaps.lua`，以及自定义模块 `duibi.lua`（程序对拍）。
- `lua/plugins/`：按插件分文件，主要的几个在下面的表里。
- `after/ftplugin/`：按文件类型的小调整（C/C++ 模板相关）。
- `lazy-lock.json`：插件版本锁。

## 自定义功能

| 功能 | 用法 |
|---|---|
| 分屏分割线改成蓝色 | 自动生效（`win-separator.lua` 在 ColorScheme/VeryLazy 等时机重设 `WinSeparator` 高亮） |
| 文件末尾也能滚出空白 | 自动生效（`scrollEOF.nvim`，`insert_mode = true`） |
| 注释里不弹补全 | 自动生效（`blink.lua` 里 `enabled` 判注释 + 进注释主动 `hide()`） |
| C/C++ 断点调试 | `空格 d b` 打断点，`:DapRun -r tests/simple.txt` 启动，停住后 `空格 d c` 下一步、`空格 d u` 看变量和程序输出 |
| 程序对拍 | `空格 r r` 选输入对拍、`空格 r f` 随机 20 组、`空格 r v` 进 yazi 用 `i`/`e` 标记输入和多个程序；命令行形式 `:Test -e ./a ./b -g 5 ./gen.py` |
| 透明背景 / 浮窗底色 | `transparent.lua` + tokyonight `transparent = true` |

## 安装

```bash
git clone git@github.com:glitch-cmyk658/-LazyVim-.git ~/.config/nvim
nvim
```

首次启动会自动安装插件，需要能访问 GitHub。

## 说明

- 对拍工具和调试配置是按「目录里有 Makefile / `*_soln` 变体」这类约定写的，换项目要按需改。
- 探针和验证脚本没有放进这个仓库。
