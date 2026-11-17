return {
  -- Replace mini.pairs with nvim-autopairs: it handles <CR> expansion correctly
  -- and respects shiftwidth for the inner line.
  { "nvim-mini/mini.pairs", enabled = false },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = true,
      map_cr = true,
      map_bs = true,
      fast_wrap = {},
      disable_filetype = { "TelescopePrompt", "snacks_picker_input", "spectre_panel" },
    },
  },
}
