return {
  {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      lightbulb = { enable = false },
      symbol_in_winbar = { enable = false },
      outline = { auto_preview = false },
      implement = { enable = false },
    },
    keys = {
      { "<leader>lp", "<cmd>Lspsaga peek_definition<cr>", desc = "Peek Definition (Lspsaga)" },
      { "<leader>lD", "<cmd>Lspsaga show_cursor_diagnostics<cr>", desc = "Cursor Diagnostics (Lspsaga)" },
      { "<leader>lC", "<cmd>Lspsaga code_action<cr>", desc = "Code Action (Lspsaga)" },
      { "<leader>lO", "<cmd>Lspsaga outline<cr>", desc = "Outline (Lspsaga)" },
    },
  },
}