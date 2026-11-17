-- 跳跃动画（G / gg / % / n / N）
--
-- 现象：这几个动作会把光标“瞬间”挪到别处，屏幕上没有任何过渡，眼睛跟不上。
-- 做法：先照常执行动作、记下终点和视口；在同一个事件循环里把光标/视口恢复原位
--       （nvim 要等这一轮结束才渲染，用户看不到那次瞬间跳），然后画过渡。
-- 两种观感，`:FlyJumpStyle ghost|slip` 切换：
--   ghost（默认）：真光标**立刻**到位，只在路径上留 4 个由暗到亮的残影，按距离依次消失
--                （80–140ms）。不用等，也不挑时长参数，接近 Pebrel 里那个拖影的观感。
--   slip：真光标不动，一个实心块从起点滑到终点，滑到了才落位（需要调时长，慢一点更明显）。
-- 限制：只处理“终点仍在当前视口内”的跳转——跨屏跳转（G/gg 去远处）在 Pebrel 里本来就有
--       平滑滚动，这里不再插手；屏外行的 screenpos() 返回 0，也算不出轨迹。
--       只挪 1 行的跳转（min_rows 以下）直接放行，避免连续 j/k 时发黏。
local M = {}

M.enabled = true
M.style = "ghost" -- ghost | slip
M.min_rows = 2 -- 屏幕行距小于这个值就直接跳（只挪 1 行没必要动画）

-- ghost 参数
M.ghost_count = 4 -- 残影个数（多了会糊）
M.ghost_duration = 110 -- 最近的残影保留多久（ms），更远的按比例提前消失

-- slip 参数
M.duration = 180 -- 动画最长时长（ms）
M.duration_min = 90 -- 只跳几行时用最短时长
M.duration_per_row = 6 -- 每多一行多画几毫秒
M.step = 16 -- 帧间隔（ms）

M.keys = { "G", "gg", "%", "n", "N" }

local anim = nil
local hl_ready = false

local function blend(a, b, k)
  local function ch(v, div)
    return math.floor(v / div) % 256
  end
  local function mix(x, y)
    return math.floor(x + (y - x) * k + 0.5)
  end
  local r = mix(ch(a, 65536), ch(b, 65536))
  local g = mix(ch(a, 256), ch(b, 256))
  local bl = mix(ch(a, 1), ch(b, 1))
  return r * 65536 + g * 256 + bl
end

local function ensure_hl()
  if hl_ready then
    return
  end
  hl_ready = true
  local cursor = vim.api.nvim_get_hl(0, { name = "Cursor" })
  local base = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
  if not base.bg then
    base = vim.api.nvim_get_hl(0, { name = "Normal" })
  end
  local bg = base.bg or 0x1e1e2e
  local fg = cursor.bg or 0xcdd6f4
  vim.api.nvim_set_hl(0, "FlyJumpCursor", { bg = fg, fg = cursor.fg or bg })
  -- 残影：从背景色往光标色靠，越靠近终点越亮
  for i = 1, 4 do
    local k = 0.18 + 0.19 * i -- 0.37 / 0.56 / 0.75 / 0.94
    vim.api.nvim_set_hl(0, "FlyJumpGhost" .. i, { bg = blend(bg, fg, k), fg = bg })
  end
end

local function close_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function stop()
  local a = anim
  anim = nil
  if not a then
    return
  end
  if a.timer then
    a.timer:stop()
    if not a.timer:is_closing() then
      a.timer:close()
    end
  end
  for _, win in ipairs(a.wins or {}) do
    close_win(win)
  end
end

-- 把 buffer 里的 (lnum, col) 换算成“窗口内”的 1-based 行列
local function win_pos(lnum, col)
  local sp = vim.fn.screenpos(0, lnum, math.max(col, 1))
  if sp.row == 0 or sp.col == 0 then
    return nil
  end
  local off = vim.fn.win_screenpos(0)
  return { row = sp.row - (off[1] - 1), col = sp.col - (off[2] - 1) }
end

local function jump_now(pos, view)
  if view then
    vim.fn.winrestview(view)
  end
  vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] })
end

local function open_block(row, col, hl)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "█" })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = 0,
    row = math.floor(row) - 1,
    col = math.floor(col) - 1,
    width = 1,
    height = 1,
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = 300,
  })
  vim.wo[win].winhl = "Normal:" .. hl
  return win
end

-- ghost：真光标立刻落位，路径上留一串依次消失的残影
local function ghost_jump(src, dst, target, view)
  ensure_hl()
  local n = math.max(2, math.min(M.ghost_count, 6))
  local wins = {}
  -- 从起点到终点均匀取 n 个点（不含终点本身，终点是真光标）
  for i = 1, n do
    local e = i / (n + 1)
    local row = src.row + (dst.row - src.row) * e
    local col = src.col + (dst.col - src.col) * e
    local level = math.max(1, math.min(4, math.ceil(i / n * 4)))
    wins[i] = open_block(row, col, "FlyJumpGhost" .. level)
  end

  -- 先把真光标放过去，残影只是“回忆”
  jump_now(target, view)

  local a = { wins = wins, timer = vim.uv.new_timer() }
  anim = a
  local step = math.max(1, math.floor(M.ghost_duration / (n + 1)))
  local closed = 0
  a.timer:start(
    0,
    step,
    vim.schedule_wrap(function()
      if anim ~= a then
        return
      end
      closed = closed + 1
      -- 从离光标最远的开始消失
      close_win(wins[closed])
      if closed >= n then
        stop()
      end
    end)
  )
end

-- slip：真光标不动，一个实心块滑到终点后才落位
local function slip_jump(src, dst, target, view, dur)
  ensure_hl()
  local win = open_block(src.row, src.col, "FlyJumpCursor")
  local a = { wins = { win }, t0 = vim.uv.now(), timer = vim.uv.new_timer() }
  anim = a

  a.timer:start(
    0,
    M.step,
    vim.schedule_wrap(function()
      if anim ~= a then
        return
      end
      if not vim.api.nvim_win_is_valid(win) then
        stop()
        return
      end
      local t = math.min((vim.uv.now() - a.t0) / dur, 1.0)
      local e = t < 0.5 and 2 * t * t or 1 - ((-2 * t + 2) ^ 2) / 2 -- easeInOutQuad
      local row = src.row + (dst.row - src.row) * e
      local col = src.col + (dst.col - src.col) * e
      pcall(vim.api.nvim_win_set_config, win, {
        relative = "win",
        win = 0,
        row = math.floor(row) - 1,
        col = math.floor(col) - 1,
        width = 1,
        height = 1,
      })
      if t >= 1.0 then
        stop()
        jump_now(target, view)
      end
    end)
  )
end

local function fly(keys)
  return function()
    -- 关掉时把按键还回去，不能直接 return nil（那样 G/gg 会变成“按了没反应”）
    if not M.enabled then
      return keys
    end
    stop()
    -- 注意：有计数时才能拼 "5G"/"5gg"；没有计数时 v:count 是 0，
    -- 用 count1(=1) 会变成 "1G"（跳到第 1 行），语义完全变了。
    local count = vim.v.count
    local from = vim.api.nvim_win_get_cursor(0)
    local from_view = vim.fn.winsaveview()

    -- 先照常执行动作，拿到真正的终点
    local ok = pcall(vim.cmd, count > 0 and ("normal! %d%s"):format(count, keys) or ("normal! " .. keys))
    if not ok then
      return nil
    end
    local target = vim.api.nvim_win_get_cursor(0)
    local dst_view = vim.fn.winsaveview()

    -- 回到起点（同一轮里不会渲染，看不到）
    vim.fn.winrestview(from_view)
    vim.api.nvim_win_set_cursor(0, from)

    local src = win_pos(from[1], from[2] + 1)
    local dst = win_pos(target[1], target[2] + 1)
    local moved_rows = math.abs(target[1] - from[1])

    -- 终点不在屏内 / 距离太近 / 拿不到屏幕坐标 → 直接跳
    if not src or not dst or moved_rows < M.min_rows then
      jump_now(target, dst_view)
      return nil
    end

    if M.style == "slip" then
      local dur = math.max(M.duration_min, math.min(M.duration, M.duration_min + moved_rows * M.duration_per_row))
      slip_jump(src, dst, target, dst_view, dur)
    else
      ghost_jump(src, dst, target, dst_view)
    end
    return nil
  end
end

function M.setup()
  for _, key in ipairs(M.keys) do
    vim.keymap.set("n", key, fly(key), { desc = "跳跃动画 " .. key, silent = true })
  end
  vim.api.nvim_create_user_command("FlyJumpToggle", function()
    M.enabled = not M.enabled
    vim.notify("flyjump: " .. (M.enabled and "on" or "off"))
  end, {})
  vim.api.nvim_create_user_command("FlyJumpStyle", function(opts)
    local s = (opts.args or ""):lower()
    if s ~= "ghost" and s ~= "slip" then
      vim.notify("flyjump style: " .. M.style .. "（可选 ghost / slip）")
      return
    end
    M.style = s
    vim.notify("flyjump style -> " .. s)
  end, { nargs = "?" })
end

return M
