-- 分屏分割线（WinSeparator）改成蓝色（2026-11-15）
--
-- 现象：tokyonight 的 WinSeparator 前景色是 #1b1d2b，和透明背景（transparent.lua 把 Normal
-- 的 bg 清成 none）几乎同色，背景图一透上来，两个窗口之间的竖线/横线就基本看不见了。
--
-- 为什么这么写：
--  * tokyonight 没有「分屏线颜色」的 opts（styles / transparent 里都没有这一项），只能在主题
--    定义完之后覆写高亮，所以照 transparent.lua 的做法挂 autocmd；
--  * 必须同时等 User VeryLazy：LazyVim 自己的 UI 高亮在 VeryLazy 之后才落定，会在 ColorScheme
--    之后把 WinSeparator 改回主题色，只在 ColorScheme 里设会被覆盖；
--  * 另加 LazyLoad：tokyonight 若被延迟加载（非启动配色时），加载完会重新定义高亮；
--  * VertSplit 是 WinSeparator 的旧名，某些插件仍读它，一并设成同色，免得两处颜色不一致。
return {
  {
    "LazyVim/LazyVim",
    init = function()
      local blue = "#7aa2f7" -- tokyonight moon 的 blue（当前配色 tokyonight-moon 的蓝）

      local function paint()
        vim.api.nvim_set_hl(0, "WinSeparator", { fg = blue })
        vim.api.nvim_set_hl(0, "VertSplit", { fg = blue })
      end

      local aug = vim.api.nvim_create_augroup("user.win_separator", { clear = true })
      vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter", "UIEnter" }, {
        group = aug,
        callback = paint,
      })
      vim.api.nvim_create_autocmd("User", {
        group = aug,
        pattern = "VeryLazy",
        callback = paint,
      })
      vim.api.nvim_create_autocmd("User", {
        group = aug,
        pattern = "LazyLoad",
        callback = paint,
      })
    end,
  },
}
