-- dev-machine: --minimal-treesitter
-- Trim Treesitter to a small set of parsers and disable on-the-fly installation,
-- so a weak host never compiles the full LazyVim default parser set. Staged into
-- the LazyVim config only when install.sh is run with --minimal-treesitter.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      auto_install = false,
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "bash",
        "markdown",
        "markdown_inline",
      },
    },
  },
}
