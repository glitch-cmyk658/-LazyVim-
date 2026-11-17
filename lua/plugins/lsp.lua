return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        underline = true,
        update_in_insert = true,
        severity_sort = true,
        virtual_text = {
          spacing = 2,
          source = "if_many",
          prefix = "●",
          -- Truncate long LSP messages (e.g. markdownlint) so they never overflow the window.
          format = function(d)
            local msg = (d.message or ""):gsub("\r?\n", " ")
            local max = 60
            if vim.fn.strdisplaywidth(msg) > max then
              msg = vim.fn.strcharpart(msg, 0, max) .. "…"
            end
            return msg
          end,
        },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "E",
            [vim.diagnostic.severity.WARN] = "W",
            [vim.diagnostic.severity.INFO] = "I",
            [vim.diagnostic.severity.HINT] = "H",
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
      },
      formatters = {
        ["clang-format"] = { prepend_args = { "--style={BasedOnStyle: LLVM, IndentWidth: 4, TabWidth: 4, UseTab: Never, ContinuationIndentWidth: 4, AccessModifierOffset: -4}" } },
      },
    },
  },
}
