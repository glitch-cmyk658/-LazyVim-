-- Comment helpers for the "comment selection" keymaps.
--
-- Everything here is driven by `commentstring`, so the marker is always the
-- one the current filetype uses (`//` in Rust, `#` in Python, `--` in Lua,
-- `/* ... */` where the filetype only has block comments). Toggling works on
-- whole lines: a block where every non-blank line is already commented loses
-- its marker, anything else gains one.
local M = {}

---@param buf integer
---@return string prefix, string suffix
local function markers(buf)
  local spec = vim.bo[buf].commentstring or ""
  local prefix, suffix = spec:match("^(.-)%%s(.*)$")
  if not prefix then
    prefix, suffix = spec, ""
  end
  prefix = vim.trim(prefix)
  suffix = vim.trim(suffix)
  if prefix == "" then
    prefix = "#"
  end
  return prefix, suffix
end

---@param indent string
---@param prefix string
---@param suffix string
---@param rest string
local function add_markers(indent, prefix, suffix, rest)
  if rest == "" then
    return indent .. prefix
  end
  local line = indent .. prefix .. " " .. rest
  if suffix ~= "" then
    line = line .. " " .. suffix
  end
  return line
end

---@param body string  line without indentation
---@param prefix string
---@param suffix string
---@return boolean
local function has_markers(body, prefix, suffix)
  if body:sub(1, #prefix) ~= prefix then
    return false
  end
  if suffix == "" then
    return true
  end
  return body:sub(-#suffix) == suffix
end

---Toggle the markers on lines `first`..`last` (1-based, inclusive).
---
---`false` is returned when the range holds nothing but blank lines: there is
---nothing to comment and nothing to uncomment.
---@param buf integer
---@param first integer
---@param last integer
---@return boolean changed
function M.toggle_lines(buf, first, last)
  local prefix, suffix = markers(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local content, all_commented = false, true
  for _, line in ipairs(lines) do
    local body = line:gsub("^%s+", "")
    if body ~= "" then
      content = true
      if not has_markers(body, prefix, suffix) then
        all_commented = false
      end
    end
  end
  if not content then
    return false
  end
  local out = {}
  for _, line in ipairs(lines) do
    local indent, body = line:match("^(%s*)(.*)$")
    if all_commented then
      body = body:gsub("^" .. vim.pesc(prefix) .. "%s?", "", 1)
      if suffix ~= "" then
        body = body:gsub("%s?" .. vim.pesc(suffix) .. "$", "", 1)
      end
      out[#out + 1] = indent .. body
    elseif body ~= "" and has_markers(body, prefix, suffix) then
      -- A half-commented block only gains markers on the lines missing them.
      out[#out + 1] = line
    else
      out[#out + 1] = add_markers(indent, prefix, suffix, body)
    end
  end
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, out)
  return true
end

---Toggle the lines the visual selection covers.
---
---`'<`/`'>` only move once visual mode ends, so a mapping that runs inside
---visual mode has to read the live anchor (`v`) and cursor instead.
function M.toggle_visual()
  local anchor = vim.fn.line("v")
  local cursor = vim.fn.line(".")
  local first = math.min(anchor, cursor)
  local last = math.max(anchor, cursor)
  M.toggle_lines(vim.api.nvim_get_current_buf(), first, last)
end

---Toggle the line the cursor is on.
function M.toggle_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  M.toggle_lines(vim.api.nvim_get_current_buf(), row, row)
end

return M