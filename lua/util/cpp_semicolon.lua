-- 在 struct / class / union / enum 的右花括号后自动补 ";"
-- 纯 Lua 实现，不依赖 Treesitter / vim-endwise。
local M = {}

local TYPE_KEYWORDS = { struct = true, class = true, union = true, enum = true }

local function starts_type_decl(line)
  local kw = line:match("^%s*(%a[%w_]*)")
  if kw and TYPE_KEYWORDS[kw] then
    return true
  end
  local tkw = line:match("^%s*template%s*<.-%>%s*(%a[%w_]*)")
  if tkw and TYPE_KEYWORDS[tkw] then
    return true
  end
  return false
end

-- 从 (row, col) 的 } 往左上找配对的 {
local function find_matching_open(buf, row, col)
  local depth = 0
  for r = row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, r - 1, r, false)[1] or ""
    local i = (r == row) and (col + 1) or #line
    while i >= 1 do
      local c = line:sub(i, i)
      if c == "}" then
        depth = depth + 1
      elseif c == "{" then
        depth = depth - 1
        if depth == 0 then
          return r, line
        end
      end
      i = i - 1
    end
  end
  return nil
end

-- 在第 row 行第 col 列（0-based，指向 }）之后插 ";"
local function append_after_brace(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  if line:sub(col + 1, col + 1) ~= "}" then
    return false
  end
  local tail = line:sub(col + 2)
  if tail:match("^%s*;") then
    return false -- 已经有分号
  end
  if tail:match("%S") then
    return false -- } 后面还有别的东西
  end
  local orow, oline = find_matching_open(buf, row, col)
  if not orow then
    return false
  end
  -- Allman 风格：{ 单独成行时，声明关键字在上一行
  local r = orow - 1
  while oline:match("^%s*{%s*$") and r >= 1 do
    oline = vim.api.nvim_buf_get_lines(buf, r - 1, r, false)[1] or ""
    r = r - 1
  end
  if not starts_type_decl(oline) then
    return false
  end
  vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { ";" })
  if vim.api.nvim_win_get_buf(0) == buf then
    vim.api.nvim_win_set_cursor(0, { row, col + 1 })
  end
  return true
end

function M.fix(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
    return false
  end
  local ft = vim.bo[buf].filetype
  if ft ~= "c" and ft ~= "cpp" then
    return false
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

  -- 情况 1：光标就停在行尾的 } 上
  if line:sub(col + 1, col + 1) == "}" then
    return append_after_brace(buf, row, col)
  end

  -- 情况 2：打完 } 按了回车、光标落在下一行空白行
  if line:match("^%s*$") and row > 1 then
    local prev = vim.api.nvim_buf_get_lines(buf, row - 2, row - 1, false)[1] or ""
    local idx = prev:match("()}%s*$")
    if idx then
      return append_after_brace(buf, row - 1, idx - 1)
    end
  end
  return false
end

return M
