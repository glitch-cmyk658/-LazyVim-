-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- C/C++：struct / class / union / enum 的右花括号后自动补分号（函数体不加）
-- 实现在 lua/util/cpp_semicolon.lua
vim.api.nvim_create_autocmd("InsertLeave", {
  pattern = { "*.c", "*.h", "*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hh", "*.hxx", "*.inl" },
  callback = function()
    local ok, mod = pcall(require, "util.cpp_semicolon")
    if ok then pcall(mod.fix) end
  end,
})

-- markdown 保持源码形状（唯一一处 markdown 专属设置；不想要就删掉这两行）
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "markdown.mdx" },
  callback = function() vim.opt_local.conceallevel = 0 end,
})

-- 补全菜单延迟弹出（blink.cmp）
-- blink 自己没有 debounce：`completion.trigger.show_on_keyword = true` 是一打就弹。
-- 所以那边关掉自动弹（见 lua/plugins/blink.lua），这里用定时器在“手停下来”之后才弹：
--   · 连续打字 → 每次按键都重置定时器，菜单不出现
--   · 停顿 250ms → 弹一次
--   · 至少两个字符才弹（避免刚进插入模式就冒个单字母菜单；`.` `::` 后面除外，字符访问直接弹）
do
  local delay = 250
  local timer = assert(vim.uv.new_timer())

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    callback = function()
      timer:stop()
      timer:start(
        delay,
        0,
        vim.schedule_wrap(function()
          if vim.fn.mode() ~= "i" then return end
          local ok, cmp = pcall(require, "blink.cmp")
          if not ok or cmp.is_visible() then return end
          -- 光标在插入模式下停在上一个字符之后，<cword> 此刻是空的，
          -- 所以取光标前的整段文字再截末尾的词。
          local line = vim.api.nvim_get_current_line()
          local col = vim.api.nvim_win_get_cursor(0)[2]
          local prefix = line:sub(1, col)
          local word = prefix:match("[%w_]+$") or ""
          if #word < 2 and not prefix:match("[.:]$") then return end
          pcall(cmp.show, {})
        end)
      )
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave", "InsertEnter" }, {
    callback = function() timer:stop() end,
  })
end
