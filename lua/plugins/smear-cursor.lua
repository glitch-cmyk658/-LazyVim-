-- 光标拖影动画（2026-11-12 加；2026-11-13 临时关闭做对比）
-- 现象：hjkl、翻页、跨窗口大跳时，光标是硬切过去的，眼睛要重新找一下落点。
-- 原因：nvim 的 cursor 只能瞬移，Windows Terminal 也没有「光标动画」开关；
--       能做到的只是「真光标直接到目标 + 用 extmark 画一条渐隐的残影」，骗一下眼睛。
-- 方案：sphamba/smear-cursor.nvim；它默认值就能用，这里只改几处。
-- 2026-11-13：enabled = false —— 用户要在 Pebrel 里对比「终端自带的拖影」和「nvim 插件拖影」，
--   先关掉 nvim 这条，免得两个动画叠在一起分不清。对比完把 false 改回 true（或删掉这一行）即可。
return {
  "sphamba/smear-cursor.nvim",
  event = "VeryLazy",
  opts = {
    enabled = false,
    -- 切 buffer/窗口不拖影，两条拖影交叠会显得乱
    smear_between_buffers = false,
    -- 插入模式不拖，打字时才不会觉得光标「粘」
    smear_insert_mode = false,
    -- 默认 0.6 / 0.45：越大越跟手、拖尾越短；越小越飘、拖尾越长
    stiffness = 0.6,
    trailing_stiffness = 0.45,
  },
}
