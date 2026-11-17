-- async 模块兼容层
--
-- 背景：两个插件都提供 lua/async.lua，但 API 不兼容：
--   * nvim-ufo 依赖 kevinhwang91/promise-async：async 是可调用对象（async(function() ... end) + 全局 await）
--   * refactoring.nvim 在 Neovim 0.12 上依赖 lewis6991/async.nvim：async 提供 .wrap / .run / .sleep
-- 谁先出现在 runtimepath，另一个就报错。这里放一个更早生效的 shim，把两套 API 合到一个对象里。

local lazy = vim.fn.stdpath("data") .. "/lazy"
local pa_path = lazy .. "/promise-async/lua/async.lua"
local an_path = lazy .. "/async.nvim/lua/async.lua"

local pa, an
if vim.uv.fs_stat(pa_path) then
  local ok, mod = pcall(dofile, pa_path)
  pa = ok and mod or nil
end
if vim.uv.fs_stat(an_path) then
  local ok, mod = pcall(dofile, an_path)
  an = ok and mod or nil
end

if pa == nil and an ~= nil then
  return an
elseif pa == nil then
  error("async shim: neither promise-async nor async.nvim is installed")
end

local merged = setmetatable({}, {
  __call = function(_, ...)
    return pa(...)
  end,
  __index = function(_, key)
    if an ~= nil and an[key] ~= nil then
      return an[key]
    end
    return pa[key]
  end,
})

return merged
