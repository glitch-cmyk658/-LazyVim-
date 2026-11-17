-- 2026-10-26 - DSH - 打 { 时若当前行是 class/struct/enum/union 声明，直接补出 {}; 光标留在中间
-- 踩坑：映射必须在 InsertEnter 重设（否则被 autopairs 盖掉）；expr 回调里不能改 buffer（E565）。
-- 做法：返回真正的按键序列（已用 nvim_replace_termcodes 转义），交给 Neovim 当输入处理。
local ok, npairs = pcall(require, "nvim-autopairs")

local function keys(s)
  return vim.api.nvim_replace_termcodes(s, true, false, true)
end

-- 去掉行首可选的 template<...> 前缀（支持嵌套 <> 和逗号），
-- 否则 `template <class T> class graph` 这一行不以 class 开头，规则就不触发。
local function strip_template_head(s)
  local _, e = s:find("^%s*template%s*<")
  if not e then
    return s
  end
  local depth, i = 1, e + 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "<" then
      depth = depth + 1
    elseif c == ">" then
      depth = depth - 1
      if depth == 0 then
        return s:sub(i + 1)
      end
    end
    i = i + 1
  end
  -- 模板头还没敲完（如 `template <class T`），先不触发
  return ""
end

local function is_type_decl(line)
  local rest = strip_template_head(line)
  return rest:match("^%s*class%s")
    or rest:match("^%s*struct%s")
    or rest:match("^%s*enum%s")
    or rest:match("^%s*union%s")
end

local function before_cursor()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return vim.api.nvim_get_current_line():sub(1, col)
end

local function install(bufnr)
  vim.keymap.set("i", "{", function()
    if is_type_decl(before_cursor()) then
      return keys("{};<Left><Left>")
    end
    if ok then return npairs.autopairs_map(bufnr, "{") end
    return keys("{}<Left>")
  end, { expr = true, buffer = bufnr, replace_keycodes = false, desc = "dsh-semicolon-open" })

  vim.keymap.set("i", "}", function()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local after = vim.api.nvim_get_current_line():sub(col + 1)
    if after:match("^}%s*;") then
      return keys("<Right><Right>")
    end
    if ok then return npairs.autopairs_map(bufnr, "}") end
    return "}"
  end, { expr = true, buffer = bufnr, replace_keycodes = false, desc = "dsh-semicolon-close" })
end

install(0)
vim.api.nvim_create_autocmd("InsertEnter", {
  buffer = 0,
  callback = function(ev) install(ev.buf) end,
})
