return {
  {
    "dnlhc/glance.nvim",
    cmd = "Glance",
    opts = {
      border = { enable = true },
      use_trouble_qf = false,
      mappings = { list = { "<C-j>", "<C-k>" } },
    },
    keys = {
      { "<leader>gD", "<cmd>Glance definitions<cr>", desc = "Glance Definitions" },
      { "<leader>gR", "<cmd>Glance references<cr>", desc = "Glance References" },
      { "<leader>gI", "<cmd>Glance implementations<cr>", desc = "Glance Implementations" },
      { "<leader>gT", "<cmd>Glance type_definitions<cr>", desc = "Glance Type Definitions" },
    },
  },
}