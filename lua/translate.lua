local M = {}

local proxy = "http://127.0.0.1:7897"
local endpoint = "https://translate.googleapis.com/translate_a/single"

local function run(curl_args)
  local out = vim.system(curl_args, { text = true }):wait()
  if out.code ~= 0 then return nil, (out.stderr or "curl failed") end
  local ok, data = pcall(vim.json.decode, out.stdout or "")
  if not ok or type(data) ~= "table" or type(data[1]) ~= "table" then
    return nil, "无法解析翻译结果"
  end
  local parts = {}
  for _, seg in ipairs(data[1]) do
    if type(seg) == "table" and seg[1] then parts[#parts + 1] = seg[1] end
  end
  local res = table.concat(parts)
  if res == "" then return nil, "翻译结果为空" end
  return res
end

function M.sync(text, target)
  if not text or text:match("^%s*$") then return nil, "没有选中内容" end
  target = target or "zh-CN"
  local url = string.format("%s?client=gtx&sl=auto&tl=%s&dt=t&q=%s", endpoint, target, vim.uri_encode(text))
  local base = { "curl", "-sS", "--max-time", "20" }
  local with_proxy = vim.list_extend(vim.deepcopy(base), { "--proxy", proxy, url })
  local res = run(with_proxy)
  if res then return res end
  local direct = vim.list_extend(vim.deepcopy(base), { url })
  local res2, err2 = run(direct)
  return res2, res2 and nil or err2
end

-- Returns 0-based start/end row+col (end col exclusive) of the current visual selection.
function M.visual_range()
  local mode = vim.fn.mode()
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  local sr, sc, er, ec = s[2], s[3], e[2], e[3]
  if sr > er or (sr == er and sc > ec) then
    sr, er = er, sr
    sc, ec = ec, sc
  end
  if mode:sub(1, 1) == "V" then
    sc, ec = 1, nil
  end
  return sr - 1, sc - 1, er - 1, ec and (ec - 1) or nil
end

function M.visual_text()
  local sr, sc, er, ec = M.visual_range()
  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, sr, sc, er, ec or -1, {})
  if not ok or #lines == 0 then return "" end
  return table.concat(lines, "\n")
end

function M.show(text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  local width = 0
  for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local ui = vim.api.nvim_list_uis()[1]
  local w = math.min(width + 2, math.floor((ui and ui.width or 80) * 0.7))
  local h = math.min(#vim.split(text, "\n", { plain = true }), 10)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.max(w, 10),
    height = math.max(h, 1),
    style = "minimal",
    border = "rounded",
  })
  vim.wo[win].wrap = true
  vim.defer_fn(function()
    if not vim.api.nvim_win_is_valid(win) then return end
    vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
      once = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
      end,
    })
  end, 500)
end

function M.translate(text, target)
  local res, err = M.sync(text, target)
  if res then M.show(res) else vim.notify(err or "翻译失败", vim.log.levels.WARN) end
  return res, err
end

function M.replace(target)
  local text = M.visual_text()
  local res, err = M.sync(text, target or "zh-CN")
  if not res then vim.notify(err or "翻译失败", vim.log.levels.WARN) return end
  local sr, sc, er, ec = M.visual_range()
  vim.api.nvim_buf_set_text(0, sr, sc, er, ec or -1, vim.split(res, "\n", { plain = true }))
end

local function copy_to_clipboard(text)
  local candidates = {
    { "clip.exe" },
    { "wl-copy" },
    { "xclip", "-selection", "clipboard" },
  }
  for _, cmd in ipairs(candidates) do
    if vim.fn.executable(cmd[1]) == 1 then
      local ok, out = pcall(vim.system, cmd, { stdin = text, text = false })
      if ok and out:wait().code == 0 then return true end
    end
  end
  return false
end

-- Put text on the system clipboard (WSL: Windows clipboard via clip.exe).
function M.term(text)
  if not text or text:match("^%s*$") then return nil, "没有内容" end
  if copy_to_clipboard(text) then
    vim.notify("已复制: " .. text, vim.log.levels.INFO)
    return text
  end
  vim.notify("没有可用的剪贴板工具", vim.log.levels.WARN)
  return nil, "no clipboard"
end

-- Translate current selection/word and copy the result to the system clipboard.
function M.translate_and_copy(text, target)
  local res, err = M.sync(text, target or "zh-CN")
  if not res then
    vim.notify(err or "翻译失败", vim.log.levels.WARN)
    return nil
  end
  M.term(res)
  return res
end

return M
