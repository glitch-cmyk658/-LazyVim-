return {
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        doc = {
          enabled = true,
          -- Pebrel has no unicode-placeholder support, so inline rendering is
          -- skipped by snacks; float mode still renders the image over the
          -- document as the cursor moves onto it.
          inline = false,
          float = true,
          max_width = 70,
          max_height = 30,
        },
      },
    },
  },
}
