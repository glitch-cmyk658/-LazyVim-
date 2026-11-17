return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- use the clangd already installed at ~/.local/clangd (no mason download)
        clangd = { mason = false },
      },
    },
  },
}
