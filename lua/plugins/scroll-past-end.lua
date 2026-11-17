-- 让 scrolloff 在文件末尾也生效（scroll past end）。
-- 现象（2026-11-15）：光标到文件最后几行时，视窗停在最后一行为屏幕底，scrolloff=10
-- 不再生效，最后一行永远贴着状态栏，视觉上"到屏幕底了视图不动"。
-- 原因：nvim 原生到 EOF 会把最后一行钉在窗口底部，scrolloff 只统计光标下方"真实存在"的行；
-- 原生没有 scrolloffpad 之类的选项（`set scrolloffpad?` → E518 Unknown option）。
-- 方案：用 scrollEOF.nvim（Aasim-A/scrollEOF.nvim）主动 winrestview 把视窗下移，
-- 让最后一行下方也留出 scrolloff 行空白；自己写 autocmd 容易和 nvim 滚动逻辑打架，故用现成插件。
-- 注意：opts.insert_mode = true 是必须的——用户是在 INSERT 里往下打字时观察到这个问题的。
return {
  "Aasim-A/scrollEOF.nvim",
  event = { "CursorMoved", "WinScrolled" },
  opts = {
    insert_mode = true,
    disabled_filetypes = { "terminal", "snacks_terminal", "lazygit", "lazydocker" },
  },
}
