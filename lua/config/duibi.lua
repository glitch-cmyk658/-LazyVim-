-- 通用「对拍」入口：任选一个测试案例，把两个程序跑同一份输入，看 SAME/DIFF。
-- 前身是 assign0 专用的 lua/config/assign0.lua（2026-11-16 改成通用版）：
--   * 程序对不再写死 reassemble / reassemble_soln，改成「目录里找 <name>_soln 且 <name> 也可执行」；
--     想手动指定用 :DuibiPair <left> <right>（存在 vim.g.duibi_pair）。
--   * <leader>rr 不再直接跑 tests/simple.txt，改成弹出案例列表（tests/*.txt、custom_tests 里的命令行、
--     当前 buffer），选中再跑——用户 2026-11-16 明确要求「用空格+rr 查找想要的测试案例」。
-- 只读运行可执行文件，输入走 stdin，不改项目目录里任何文件。
-- 注意：不要写成 lua/plugins/xxx.lua 返回 {"LazyVim/LazyVim", init=…}——实测 lazy 不执行那种重复 spec 的
-- init（见 docs/nvim/pitfalls.md §13），所以由 lua/config/keymaps.lua 末尾 require 本模块。

local M = {}

-- 最近一次探测到的项目根/程序对（结果窗口里再按键时复用，见 context()）
local last_root, last_pair

local function is_exec(path)
  return vim.fn.executable(path) == 1
end

-- 目录里找一对「<name> 与 <name>_soln」可执行文件；找不到返回 nil
local function detect_pair(dir)
  if vim.g.duibi_pair then
    local p = vim.g.duibi_pair
    if is_exec(p[1]) or is_exec(dir .. "/" .. p[1]) then
      return { p[1], p[2] }
    end
  end
  for _, soln in ipairs(vim.fn.glob(dir .. "/*_soln", false, true)) do
    local base = soln:gsub("_soln$", "")
    if is_exec(soln) and is_exec(base) then
      return { base, soln }
    end
  end
  return nil
end

-- 从当前 buffer 往上找项目根（顺便返回程序对）
local function project(buf)
  buf = buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  local dir = name ~= "" and vim.fn.fnamemodify(name, ":h") or vim.fn.getcwd()
  for _ = 1, 8 do
    local pair = detect_pair(dir)
    if pair then
      return dir, pair
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil, nil
end

-- 在结果窗口（nofile scratch）里再按 <leader>rr / <leader>rf 时，project() 拿不到源文件名
-- （buffer 名为空），会退回 cwd；所以这里缓存最近一次探测到的 root/pair 给它复用。
local function context(buf)
  buf = buf or 0
  if vim.bo[buf].buftype == "nofile" and last_root then
    return last_root, last_pair
  end
  local root, pair = project(buf)
  if root then
    last_root, last_pair = root, pair
  end
  return root, pair
end

-- list 形式传参，不用 shell，路径有空格/中文也不会被拆开
-- input == nil：不设 stdin（子进程继承 nvim 的 stdin，程序要读输入时会卡住，只在明确不读 stdin 时用）
-- input == "" ：喂一个空串，程序读到立刻 EOF（「没有输入」的测试走这条）
-- input 其它 ：喂这份内容当 stdin
local function run(binary, args, input)
  local cmd = { binary }
  vim.list_extend(cmd, args or {})
  local opts = { text = true }
  if input ~= nil then
    opts.stdin = input
  end
  local ok, obj = pcall(function()
    return vim.system(cmd, opts):wait(5000)
  end)
  if not ok or obj == nil then
    return "", "(无法运行 " .. binary .. ")", 127
  end
  return obj.stdout or "", obj.stderr or "", obj.code or 0
end

-- 结果窗口必须用「新建的 scratch buffer」，不能 :split 之后直接改造当前 buffer：
-- `:split` 只是再开一个窗口指着同一个 buffer，对它 set buftype/set_lines 等于把用户正在编辑的
-- 源文件 buffer 换成结果内容（2026-11-16 实测：reassemble.c 的 buffer 被结果覆盖且 ft 仍是 c，
-- clangd 对中文结果行报 `E13: Unknown type name '左'`）。所以先建 scratch，再 split、win_set_buf。
--
-- 渲染：一行要分「名字 / out: / 值」三段不同颜色，nvim_buf_add_highlight 是按整行/整段染的，
-- 只能自己按列切——所以下面用 (text, hl) 段拼行，记每段起止列，写完行再打 extmark。
local NS = vim.api.nvim_create_namespace("duibi_result")
-- 用组名而不是直接写颜色：重载配色（ColorScheme）时链接会跟着主题走，不用重排结果。
local HL = {
  head = "DuibiHead",
  name = "DuibiName",
  stream = "DuibiStream",
  value = "DuibiValue",
  err = "DuibiErr",
  diff = "DuibiDiff",
  same = "DuibiSame",
  input = "DuibiInput",
}

local function setup_hl()
  local function set(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end
  -- 色板取 tokyonight moon：紫=标题、蓝=程序名、灰=标签、红=stderr/DIFF、绿=SAME、黄=输入内容
  set("DuibiHead", { fg = "#bb9af7", bold = true })
  set("DuibiName", { fg = "#7aa2f7" })
  set("DuibiStream", { fg = "#565f89" })
  set("DuibiValue", { fg = "#c0caf5" })
  set("DuibiErr", { fg = "#f7768e" })
  set("DuibiDiff", { fg = "#f7768e", bold = true })
  set("DuibiSame", { fg = "#9ece6a", bold = true })
  set("DuibiInput", { fg = "#e0af68" })
end

-- 按「显示宽度」补空格对齐（中文注释/名字按 2 列算，避免错位）
local function pad(s, w)
  return s .. string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s)))
end

local function row()
  return { text = "", hl = {} }
end

local function add(r, txt, group)
  if txt == nil or txt == "" then
    return r
  end
  local s = #r.text
  r.text = r.text .. txt
  if group then
    r.hl[#r.hl + 1] = { s, #r.text, group }
  end
  return r
end

local function blank()
  return row()
end

-- 值：只把换行转义成 \n，原样显示。
-- 注意：学生程序 stderr 本来就会带自己的前缀（`reassemble: fragment contains a space`），
-- 所以 `reassemble err: reassemble: ...` 里出现两次名字是程序输出，不是界面 bug——用户
-- 2026-11-16 确认保留原样，只做列对齐 + 颜色，不要加引号/删前缀。
local function val(s)
  return ((s or ""):gsub("\n", "\\n"))
end

-- 输入内容按行铺开时，末尾换行 split 出来的那个空串不要当成一行：
-- 否则会渲染出只有 3 个空格的行，listchars 的 trail:- 把它画成 `---`，看着像多了一行。
local function input_lines(s)
  local t = vim.split(s or "", "\n", { plain = true })
  if #t > 0 and t[#t] == "" then
    table.remove(t)
  end
  return t
end

local function kvline(name, width, key, v)
  local r = row()
  add(r, "   ")
  add(r, pad(name, width), HL.name)
  -- v 为空时不要留 ": " 的空格：listchars 里 trail:- 会把行尾空格画成「-」，
  -- 空 stderr 行就变成 `err:-`，看着像多输出了一个字符。
  add(r, "  " .. key .. (v ~= "" and ": " or ":"), HL.stream)
  add(r, v, key == "err" and HL.err or HL.value)
  return r
end

local function result_buf(title, rows)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "duibi" -- 不继承 c 的语法/LSP，中文结果行不会再被当成 C 代码报错
  vim.bo[buf].modifiable = true
  setup_hl()
  local lines, marks = {}, {}
  for _, r in ipairs(rows) do
    if type(r) == "string" then
      r = { text = r, hl = {} }
    end
    lines[#lines + 1] = r.text
    marks[#marks + 1] = r.hl
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for i, hs in ipairs(marks) do
    for _, h in ipairs(hs) do
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, h[1], { end_col = h[2], hl_group = h[3] })
    end
  end
  vim.bo[buf].modifiable = false
  vim.cmd("botright 14split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set("n", "<leader>rr", function()
    M.run(buf)
  end, { buffer = buf, desc = "对拍：选案例再跑" })
  vim.keymap.set("n", "<leader>rf", function()
    M.fuzz(20, buf)
  end, { buffer = buf, desc = "对拍：随机 20 组" })
  vim.keymap.set("n", "<leader>rv", function()
    M.versions(buf)
  end, { buffer = buf, desc = "多版本对拍：yazi 里 i/e 标记" })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "关闭结果窗口" })
  return buf
end

-- 结果里不写「左/右」，直接写程序文件名（用户 2026-11-16 明确要求：
-- 「这个不要再写左右了，直接写文件名」——左右要在脑子里换算一次，名字不用）。
-- 排版：名字列按两者最宽的补空格对齐；out 两行挨着、err 两行挨着，值列不用手工数空格。
local function head_row(label, verdict, lcode, rcode)
  local r = row()
  add(r, "== ", HL.head)
  add(r, label, HL.head)
  add(r, " | ", HL.stream)
  add(r, verdict, verdict == "DIFF" and HL.diff or HL.same)
  add(r, (" | exit %d vs %d "):format(lcode, rcode), HL.stream)
  add(r, "==", HL.head)
  return r
end

local function show(label, lname, rname, l_out, l_err, l_code, r_out, r_err, r_code, input)
  local same = l_out == r_out and l_err == r_err and l_code == r_code
  local width = math.max(vim.fn.strdisplaywidth(lname), vim.fn.strdisplaywidth(rname))
  local rows = { head_row(label, same and "SAME" or "DIFF", l_code, r_code), blank() }
  if same then
    local r = row()
    add(r, ("%s 与 %s 完全一致，这个案例没暴露差异。"):format(lname, rname), HL.stream)
    rows[#rows + 1] = r
  else
    rows[#rows + 1] = kvline(lname, width, "out", val(l_out))
    rows[#rows + 1] = kvline(rname, width, "out", val(r_out))
    rows[#rows + 1] = kvline(lname, width, "err", val(l_err))
    rows[#rows + 1] = kvline(rname, width, "err", val(r_err))
  end
  if input and input ~= "" then
    rows[#rows + 1] = blank()
    local r = row()
    add(r, "-- 输入内容是 --", HL.stream)
    rows[#rows + 1] = r
    for _, line in ipairs(input_lines(input)) do
      local rr = row()
      add(rr, "   " .. line, HL.input)
      rows[#rows + 1] = rr
    end
  end
  result_buf(title, rows)
end

-- 案例列表：当前 buffer、tests/*.txt、custom_tests 里的命令行（可带 -r 等参数）
local function cases(root)
  local list = {}
  local buf_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
  if buf_content:match("^%s*{") then
    list[#list + 1] = { label = "当前 buffer 内容", args = {}, input = buf_content }
  end
  for _, f in ipairs(vim.fn.glob(root .. "/tests/*.txt", false, true)) do
    local rel = vim.fn.fnamemodify(f, ":.")
    list[#list + 1] = { label = rel, args = { rel }, input = "" }
  end
  local custom = root .. "/custom_tests"
  if vim.fn.filereadable(custom) == 1 then
    for _, line in ipairs(vim.fn.readfile(custom)) do
      line = vim.trim(line)
      if line ~= "" and not line:match("^#") then
        local args = vim.split(line, "%s+", { trimempty = true })
        local has_file = false
        for _, a in ipairs(args) do
          if not a:match("^%-") then
            has_file = true
          end
        end
        -- stdin 一律给空串（读到 EOF）：自定义命令行里可能带文件也可能不带，
        -- 不带文件时程序会去读 stdin，留空会继承 nvim 的 stdin 卡在那里。
        list[#list + 1] = { label = "custom_tests: " .. line, args = args, input = "" }
      end
    end
  end
  return list
end

-- <leader>rr：弹案例列表（快搜），选中后对拍
function M.run(buf)
  buf = buf or 0
  local root, pair = context(buf)
  if not root then
    vim.notify("这个目录里没找到可对拍的程序对（<name> 与 <name>_soln，或用 :DuibiPair 指定）", vim.log.levels.WARN)
    return
  end
  local list = cases(root)
  if #list == 0 then
    vim.notify("没有可用案例（当前 buffer 不是片段、没有 tests/*.txt 或 custom_tests）", vim.log.levels.WARN)
    return
  end
  -- vim.ui.select 的回调收到的是「条目本身」而不是下标：snacks 的 select 实现会把 items 原样传回，
  -- 所以这里直接传条目表 + format_item，回调里用 c；早先版本按 list[choice] 取，回车就会 nil 报错。
  vim.ui.select(list, {
    prompt = "对拍案例（可输入筛选）：",
    format_item = function(c)
      return c.label
    end,
  }, function(c)
    if not c then
      return
    end
    -- 注意别写 { (run(...)) }：括号会把多返回值截成 1 个，后面 stdout/stderr/退出码全 nil，
    -- 之前就是这样在 string.format 里炸的。
    local l_out, l_err, l_code = run(pair[1], c.args, c.input)
    local r_out, r_err, r_code = run(pair[2], c.args, c.input)
    show(
      c.label,
      vim.fn.fnamemodify(pair[1], ":t"),
      vim.fn.fnamemodify(pair[2], ":t"),
      l_out, l_err, l_code, r_out, r_err, r_code,
      c.input
    )
  end)
end

local function rand_fragments()
  local words = { "a", "b", "bc", "abc", "abcd", "hello", "world", "abcabc", "x" }
  local pieces = {}
  for i = 1, math.random(1, 4) do
    local kind = math.random(1, 4)
    local body
    if kind == 1 then
      body = words[math.random(#words)]
    elseif kind == 2 then
      body = words[math.random(#words)] .. " " .. words[math.random(#words)]
    elseif kind == 3 then
      body = string.rep(words[math.random(#words)], math.random(1, 3))
    else
      body = ""
    end
    pieces[i] = "{" .. body .. "}"
  end
  return table.concat(pieces, "\n") .. "\n"
end

function M.fuzz(count, buf)
  local root, pair = context(buf or 0)
  if not root then
    vim.notify("这个目录里没找到可对拍的程序对", vim.log.levels.WARN)
    return
  end
  count = count or 20
  math.randomseed(os.time())
  local diffs = {}
  for _ = 1, count do
    local input = rand_fragments()
    local l_out, l_err, l_code = run(pair[1], {}, input)
    local r_out, r_err, r_code = run(pair[2], {}, input)
    if l_out ~= r_out or l_err ~= r_err or l_code ~= r_code then
      diffs[#diffs + 1] = { input = input, l_code = l_code, r_code = r_code, l_out = l_out, r_out = r_out, l_err = l_err, r_err = r_err }
    end
  end
  local lname = vim.fn.fnamemodify(pair[1], ":t")
  local rname = vim.fn.fnamemodify(pair[2], ":t")
  local width = math.max(vim.fn.strdisplaywidth(lname), vim.fn.strdisplaywidth(rname))
  local head = row()
  add(head, "== 随机对拍 ", HL.head)
  add(head, tostring(count), HL.value)
  add(head, " 组 | 差异 ", HL.head)
  add(head, tostring(#diffs), #diffs > 0 and HL.diff or HL.same)
  add(head, " 组 ==", HL.head)
  local rows = { head, blank() }
  if #diffs == 0 then
    local r = row()
    add(r, ("这 %d 组全 SAME，换个方向再试。"):format(count), HL.stream)
    rows[#rows + 1] = r
  else
    for i, d in ipairs(diffs) do
      local h = row()
      add(h, ("-- 第 %d 组 (exit %d vs %d) --"):format(i, d.l_code, d.r_code), HL.stream)
      rows[#rows + 1] = h
      for _, line in ipairs(input_lines(d.input)) do
        local rr = row()
        add(rr, "   " .. line, HL.input)
        rows[#rows + 1] = rr
      end
      rows[#rows + 1] = kvline(lname, width, "out", val(d.l_out))
      rows[#rows + 1] = kvline(rname, width, "out", val(d.r_out))
      rows[#rows + 1] = kvline(lname, width, "err", val(d.l_err))
      rows[#rows + 1] = kvline(rname, width, "err", val(d.r_err))
      rows[#rows + 1] = blank()
    end
  end
  result_buf("fuzz", rows)
end

-- ── 多版本对拍：yazi 里 i 标记输入、e 标记多个候选版本 ───────────────────
-- 为什么走 yazi：同一份输入要配多个已编译程序，nvim 的 vim.ui.select 只能选一个；
-- yazi 里能一边浏览一边按 i/e 打标记，一次会话标完再退出（用户 2026-11-16 拍的 B 方案）。
-- 标记文件由 yazi 的 keymap（~/.config/yazi/keymap.toml 里 i/e 两条 shell）追加，行格式：
--   i<TAB>路径    测试用例（有多个时取最后一个）
--   e<TAB>路径    候选版本（可多个）
-- 注意 yazi 的 %h 替换会给带空格的路径自动加引号（实测写了 '…in put 1.txt'），所以读出来要去引号。
local MARKS = "/tmp/duibi-marks.txt"

local function unquote(s)
  s = vim.trim(s)
  local q = s:sub(1, 1)
  if (q == "'" or q == '"') and #s >= 2 and s:sub(-1) == q then
    return s:sub(2, -2)
  end
  return s
end

local function read_marks()
  local input, cands = nil, {}
  if vim.fn.filereadable(MARKS) == 0 then
    return input, cands
  end
  for _, line in ipairs(vim.fn.readfile(MARKS)) do
    local kind, path = line:match("^([ie])\t(.+)$")
    if kind then
      path = unquote(path)
      if kind == "i" then
        input = path
      elseif path ~= "" then
        cands[#cands + 1] = path
      end
    end
  end
  return input, cands
end

local function yazi_bin()
  local p = vim.fn.exepath("yazi")
  if p ~= "" then
    return p
  end
  -- exepath 找不到时按常见安装位置再找一遍（不写死个人目录，换个机器也能用）
  local home = vim.env.HOME or ""
  for _, cand in ipairs({ home .. "/.local/bin/yazi", "/usr/local/bin/yazi", "/usr/bin/yazi" }) do
    if vim.fn.executable(cand) == 1 then
      return cand
    end
  end
  return "yazi"
end

-- 同一份输入文件作为 argv 喂给每个候选程序，按 (退出码, stdout, stderr) 分组
local function run_versions(input, cands)
  local results = {}
  for _, bin in ipairs(cands) do
    local out, err, code = run(bin, { input }, "")
    results[#results + 1] = { name = vim.fn.fnamemodify(bin, ":t"), out = out, err = err, code = code }
  end
  local groups, keys = {}, {}
  for _, r in ipairs(results) do
    local key = r.code .. "\0" .. r.out .. "\0" .. r.err
    if not groups[key] then
      groups[key] = { code = r.code, out = r.out, err = r.err, names = {} }
      keys[#keys + 1] = key
    end
    table.insert(groups[key].names, r.name)
  end
  table.sort(keys, function(a, b)
    return groups[a].code < groups[b].code
  end)
  local rows = {}
  local head = row()
  add(head, "== 多版本对拍 | 输入: ", HL.head)
  add(head, vim.fn.fnamemodify(input, ":t"), HL.value)
  add(head, (" | %d 个版本 → "):format(#cands), HL.head)
  add(head, ("%d 组"):format(#keys), #keys > 1 and HL.diff or HL.same)
  add(head, " ==", HL.head)
  rows[#rows + 1] = head
  rows[#rows + 1] = blank()
  if #keys == 1 then
    local r = row()
    add(r, ("所有 %d 个版本输出完全一致，这组输入没暴露差异。"):format(#cands), HL.stream)
    rows[#rows + 1] = r
    rows[#rows + 1] = blank()
  end
  for i, key in ipairs(keys) do
    local g = groups[key]
    local h = row()
    add(h, ("-- 第 %d 组 (exit %d) — "):format(i, g.code), HL.stream)
    add(h, table.concat(g.names, ", "), HL.name)
    add(h, " --", HL.stream)
    rows[#rows + 1] = h
    local o = row()
    add(o, "   ")
    add(o, "out:", HL.stream)
    if g.out ~= "" then
      add(o, " ", HL.stream)
      add(o, val(g.out), HL.value)
    end
    rows[#rows + 1] = o
    local e = row()
    add(e, "   ")
    add(e, "err:", HL.stream)
    if g.err ~= "" then
      add(e, " ", HL.stream)
      add(e, val(g.err), HL.err)
    end
    rows[#rows + 1] = e
    rows[#rows + 1] = blank()
  end
  result_buf("多版本", rows)
end

-- <leader>rv / :DuibiVersions：在下方开一个终端跑 yazi，标完退出即出结果
function M.versions(buf)
  buf = buf or 0
  local root = context(buf)
  local cwd = root or vim.fn.getcwd()
  vim.fn.delete(MARKS)
  local sbuf = vim.api.nvim_create_buf(false, true)
  vim.cmd("botright 16split")
  vim.api.nvim_win_set_buf(0, sbuf)
  -- 用 termopen 而不是 jobstart({term=true})：jobstart 的终端 buffer 不一定接管当前窗口，
  -- 实测会停在前一个普通 buffer 上（NORMAL 模式），按键全被 nvim 当普通命令吃掉，
  -- yazi 一个标记都没收到。termopen 直接把当前窗口变成终端，并且自动进终端模式。
  local ok, err = pcall(vim.fn.termopen, { yazi_bin() }, {
    cwd = cwd,
    on_exit = function()
      vim.schedule(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == sbuf then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
        local input, cands = read_marks()
        if not input then
          vim.notify("没有标记测试用例：在 yazi 里对输入文件按 i", vim.log.levels.WARN)
          return
        end
        if #cands == 0 then
          vim.notify("没有标记候选版本：在 yazi 里对编译好的程序按 e（可多个）", vim.log.levels.WARN)
          return
        end
        run_versions(input, cands)
      end)
    end,
  })
  if not ok then
    vim.notify("启动 yazi 失败：" .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.cmd("startinsert")
end

-- ── :Test：命令行形式的对拍（2026-11-17 用户要求）──────────────────────
-- 用户不想再在「案例列表 + 固定随机规则」里挑，希望直接敲参数：
--   :Test -r -e ./reassemble ./reassemble_soln                 没有输入，只比参数处理（-r 等原样传给程序）
--   :Test -e ./reassemble ./reassemble_soln -g 20              随机生成 20 组片段当输入
--   :Test -e ./reassemble ./reassemble_soln -g 20 ./gen.py     用生成脚本造 20 组输入（脚本每次打印一份）
--   :Test -r -e ./reassemble ./reassemble_soln -i tests/simple.txt tests/big.txt
--                                                              用这些文件的内容当 stdin
--   :Test -r -e ./reassemble ./reassemble_soln -q              同上，但只比 stdout + 退出码（调试打印在 stderr 时用）
-- -g 与 -i 互斥；-e 省掉时用目录里自动探测到的程序对。
-- nvim 的用户命令必须大写开头（E183），所以命令注册成 :Test，setup() 里再配 cnoreabbrev 让 :test 也能用。
local function parse_test_args(tokens)
  local prog_args, exes, rule, inputs = {}, {}, nil, nil
  local gen_script, quiet = nil, false
  local mode, i = "args", 1
  while i <= #tokens do
    local t = tokens[i]
    if t == "-q" then
      quiet = true
      i = i + 1
    elseif t == "-e" then
      mode, i = "exes", i + 1
    elseif t == "-g" then
      mode, i = "gen", i + 1
    elseif t == "-i" then
      mode, i = "inputs", i + 1
      inputs = inputs or {}
    elseif mode == "args" then
      prog_args[#prog_args + 1] = t
      i = i + 1
    elseif mode == "exes" then
      exes[#exes + 1] = t
      i = i + 1
    elseif mode == "inputs" then
      inputs[#inputs + 1] = t
      i = i + 1
    elseif mode == "gen" then
      -- -g 后面先可以跟次数（纯数字），再可以跟一个生成脚本路径；只给路径时次数默认 20
      if t:match("^%d+$") then
        rule = tonumber(t)
        i = i + 1
      else
        gen_script = t
        mode = "done"
        i = i + 1
      end
    else
      return nil, "多余的参数：" .. t
    end
  end
  if (rule or gen_script) and inputs then
    return nil, "-g 和 -i 不能一起用：要么用生成脚本/随机规则造输入，要么用你给的素材文件"
  end
  return { prog_args = prog_args, exes = exes, rule = rule, gen_script = gen_script, inputs = inputs, quiet = quiet }
end

local function resolve_exes(exes, root)
  local out = {}
  for _, e in ipairs(exes) do
    local p = e
    if not is_exec(p) and root then
      p = root .. "/" .. e
    end
    if not is_exec(p) then
      return nil, "找不到可执行文件：" .. e
    end
    out[#out + 1] = p
  end
  if #out == 0 then
    local _, pair = context(0)
    if not pair then
      return nil, "缺 -e：至少给一个被测程序（如 -e ./reassemble ./reassemble_soln），或先 :DuibiPair 指定"
    end
    out = pair
  end
  if #out < 2 then
    return nil, "至少给两个被测程序才能对拍（-e 程序1 程序2）"
  end
  return out
end

-- 按 (退出码, stdout, stderr) 分组：结果相同的程序并成一行
-- quiet = true 时忽略 stderr（程序里临时加的调试 fprintf 都走 stderr，会把每组都变成「有差异」）
local function group_results(results, quiet)
  local groups, keys = {}, {}
  for _, r in ipairs(results) do
    local key = quiet and (r.code .. "\0" .. r.out) or (r.code .. "\0" .. r.out .. "\0" .. r.err)
    if not groups[key] then
      groups[key] = { code = r.code, out = r.out, err = r.err, names = {} }
      keys[#keys + 1] = key
    end
    table.insert(groups[key].names, r.name)
  end
  table.sort(keys, function(a, b)
    return groups[a].code < groups[b].code
  end)
  return groups, keys
end

-- -g 的第二种用法：-g [次数] <生成脚本>。脚本每次被调用时把「一份输入」打印到 stdout，
-- 当前是第几组通过 argv[1] 传进去（第 1..N 组），脚本可以拿它当随机种子，同一组序号每次
-- 生成同样的内容，复现问题方便。脚本可执行就直接跑，否则按扩展名找解释器（.py → python3，.sh → bash…）。
local INTERP = { py = "python3", sh = "bash", lua = "lua", pl = "perl", js = "node" }

local function resolve_script(p, root)
  local path = p
  if vim.fn.filereadable(path) == 0 and root then
    path = root .. "/" .. p
  end
  if vim.fn.filereadable(path) == 0 then
    return nil, "生成脚本读不到：" .. p
  end
  if vim.fn.executable(path) == 1 then
    return { path }
  end
  local ext = path:match("%.([%w]+)$")
  local interp = INTERP[ext or ""]
  if not interp then
    return nil, "脚本没有执行权限、也不是认识的类型（.py/.sh/.lua/.pl/.js）：" .. p
  end
  return { interp, path }
end

local function gen_input(cmd, idx, cwd)
  local args = {}
  for _, a in ipairs(cmd) do
    args[#args + 1] = a
  end
  args[#args + 1] = tostring(idx)
  local ok, obj = pcall(function()
    return vim.system(args, { text = true, cwd = cwd }):wait(5000)
  end)
  if not ok or obj == nil then
    return nil, "生成脚本运行失败：" .. table.concat(cmd, " ")
  end
  if (obj.code or 0) ~= 0 then
    return nil, ("生成脚本第 %d 组退出码 %d：%s"):format(idx, obj.code, (obj.stderr or ""):sub(1, 200))
  end
  return obj.stdout or ""
end

-- 输入内容最多铺 8 行，多了只说还剩几行（-i 的素材文件可能很长）
local function case_input_lines(input)
  local lines = input_lines(input or "")
  if #lines <= 8 then
    return lines, 0
  end
  local keep = {}
  for i = 1, 8 do
    keep[i] = lines[i]
  end
  return keep, #lines - 8
end

function M.test(tokens)
  local spec, perr = parse_test_args(tokens)
  if not spec then
    vim.notify(perr, vim.log.levels.ERROR)
    return
  end
  local root = context(0)
  local exes, xerr = resolve_exes(spec.exes, root)
  if not exes then
    vim.notify(xerr, vim.log.levels.ERROR)
    return
  end

  local case_list = {}
  if spec.inputs then
    for _, f in ipairs(spec.inputs) do
      local p = f
      if vim.fn.filereadable(p) == 0 and root then
        p = root .. "/" .. f
      end
      if vim.fn.filereadable(p) == 0 then
        vim.notify("素材文件读不到：" .. f, vim.log.levels.ERROR)
        return
      end
      case_list[#case_list + 1] = {
        label = f,
        input = table.concat(vim.fn.readfile(p), "\n") .. "\n",
      }
    end
  elseif spec.gen_script then
    local total = spec.rule or 20
    local script, serr = resolve_script(spec.gen_script, root)
    if not script then
      vim.notify(serr, vim.log.levels.ERROR)
      return
    end
    for i = 1, total do
      local content, gerr = gen_input(script, i, root or vim.fn.getcwd())
      if not content then
        vim.notify(gerr, vim.log.levels.ERROR)
        return
      end
      case_list[#case_list + 1] = { label = ("脚本第 %d 组"):format(i), input = content }
    end
  elseif spec.rule then
    math.randomseed(os.time())
    for i = 1, spec.rule do
      case_list[#case_list + 1] = { label = ("随机第 %d 组"):format(i), input = rand_fragments() }
    end
  else
    case_list[#case_list + 1] = { label = "无输入（stdin 直接 EOF）", input = "" }
  end

  local names = {}
  for _, e in ipairs(exes) do
    names[#names + 1] = vim.fn.fnamemodify(e, ":t")
  end

  local rows = {}
  local head = row()
  add(head, "== Test | ", HL.head)
  add(head, tostring(#case_list) .. " 组 | ", HL.head)
  add(head, table.concat(names, ", "), HL.name)
  if #spec.prog_args > 0 then
    add(head, " | 参数: ", HL.head)
    add(head, table.concat(spec.prog_args, " "), HL.input)
  end
  if spec.gen_script then
    add(head, " | 脚本: ", HL.head)
    add(head, vim.fn.fnamemodify(spec.gen_script, ":t"), HL.stream)
  end
  if spec.quiet then
    add(head, " | 只比 stdout", HL.stream)
  end
  add(head, " ==", HL.head)
  rows[#rows + 1] = head
  rows[#rows + 1] = blank()

  local diff_n = 0
  for idx, c in ipairs(case_list) do
    local results = {}
    for _, bin in ipairs(exes) do
      local o, e, code = run(bin, spec.prog_args, c.input)
      results[#results + 1] = { name = vim.fn.fnamemodify(bin, ":t"), out = o, err = e, code = code }
    end
    local groups, keys = group_results(results, spec.quiet)
    local h = row()
    add(h, ("-- 案例 %d：%s"):format(idx, c.label), HL.stream)
    add(h, ("（%d 种结果）--"):format(#keys), #keys > 1 and HL.diff or HL.same)
    rows[#rows + 1] = h
    if #keys > 1 then
      diff_n = diff_n + 1
    end
    if c.input ~= "" then
      local lines, rest = case_input_lines(c.input)
      for _, line in ipairs(lines) do
        local rr = row()
        add(rr, "   " .. line, HL.input)
        rows[#rows + 1] = rr
      end
      if rest > 0 then
        local rr = row()
        add(rr, ("   …还有 %d 行输入"):format(rest), HL.stream)
        rows[#rows + 1] = rr
      end
    end
    if #keys == 1 then
      local g = groups[keys[1]]
      local r = row()
      add(r, "   全部一致", HL.same)
      add(r, ("（exit %d）"):format(g.code), HL.stream)
      if g.out ~= "" then
        add(r, "  out: ", HL.stream)
        add(r, val(g.out), HL.value)
      end
      if g.err ~= "" and not spec.quiet then
        add(r, "  err: ", HL.stream)
        add(r, val(g.err), HL.err)
      end
      rows[#rows + 1] = r
    else
      for gi, key in ipairs(keys) do
        local g = groups[key]
        local gh = row()
        add(gh, ("   组 %d (exit %d) — "):format(gi, g.code), HL.stream)
        add(gh, table.concat(g.names, ", "), HL.name)
        rows[#rows + 1] = gh
        local o = row()
        add(o, "     out:", HL.stream)
        if g.out ~= "" then
          add(o, " ", HL.stream)
          add(o, val(g.out), HL.value)
        end
        rows[#rows + 1] = o
        local e = row()
        add(e, "     err:", HL.stream)
        if g.err ~= "" and not spec.quiet then
          add(e, " ", HL.stream)
          add(e, val(g.err), HL.err)
        end
        if not spec.quiet then
          rows[#rows + 1] = e
        end
      end
    end
    rows[#rows + 1] = blank()
  end
  local foot = row()
  add(foot, ("%d 组里 %d 组有差异"):format(#case_list, diff_n), diff_n > 0 and HL.diff or HL.same)
  rows[#rows + 1] = foot
  result_buf("Test", rows)
end

local function attach_keys(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local _, pair = project(buf)
  if not pair or vim.b[buf].duibi_keys then
    return
  end
  vim.b[buf].duibi_keys = true
  vim.keymap.set("n", "<leader>rr", function()
    M.run(buf)
  end, { buffer = buf, desc = "对拍：选案例再跑" })
  vim.keymap.set("n", "<leader>rf", function()
    M.fuzz(20, buf)
  end, { buffer = buf, desc = "对拍：随机 20 组" })
  vim.keymap.set("n", "<leader>rv", function()
    M.versions(buf)
  end, { buffer = buf, desc = "多版本对拍：yazi 里 i/e 标记" })
end

function M.setup()
  vim.api.nvim_create_user_command("Duibi", function()
    M.run(0)
  end, { desc = "对拍：弹案例列表再跑" })
  vim.api.nvim_create_user_command("DuibiFuzz", function(o)
    M.fuzz(tonumber(o.args) or 20, 0)
  end, { nargs = "?", desc = "对拍：随机 N 组，只列差异" })
  vim.api.nvim_create_user_command("DuibiVersions", function()
    M.versions(0)
  end, { desc = "多版本对拍：开 yazi，i 标记输入、e 标记候选版本" })
  vim.api.nvim_create_user_command("DuibiPair", function(o)
    vim.g.duibi_pair = vim.split(o.args, "%s+", { trimempty = true })
  end, { nargs = "+", desc = "对拍：手动指定 左程序 右程序" })

  vim.api.nvim_create_user_command("Test", function(o)
    M.test(o.fargs)
  end, { nargs = "*", desc = "对拍：:Test [程序参数] [-q] -e 程序1 程序2 [-g [次数] [生成脚本] | -i 素材文件…]" })
  -- nvim 的用户命令必须大写开头（E183: User defined commands must start with a capital letter），
  -- 所以命令只能是 :Test；这里加一条命令模式缩写，让敲 :test 也落到 :Test。
  vim.cmd([[cnoreabbrev <expr> test getcmdtype() ==# ':' && getcmdline() =~# '^test' ? 'Test' : 'test']])

  local group = vim.api.nvim_create_augroup("user.duibi_keys", { clear = true })
  vim.keymap.set("n", "<leader>rv", function()
    M.versions(0)
  end, { desc = "多版本对拍：yazi 里 i/e 标记" })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = group,
    callback = function(args)
      attach_keys(args.buf)
    end,
  })
  local function attach_all()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      attach_keys(b)
    end
  end
  vim.api.nvim_create_autocmd("VimEnter", { group = group, callback = attach_all })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "VeryLazy", callback = attach_all })
  attach_all()
end

-- 给探针/调试用（docs/nvim-tests/duibi-verify.sh 会调用）
M.project = project
M.cases = cases
M.detect_pair = detect_pair

return M
