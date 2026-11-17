return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>fy", "<cmd>Yazi<cr>", desc = "Yazi: open at current file" },
    { "<leader>fY", "<cmd>Yazi cwd<cr>", desc = "Yazi: open in working directory" },
  },
  opts = {
    open_for_directories = true,
    keymaps = { show_help = "<f1>" },
    yazi_floating_window_border = "rounded",
  },
}
