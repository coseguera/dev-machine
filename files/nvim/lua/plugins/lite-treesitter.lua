-- dev-machine: --minimal-treesitter
-- Disable all Treesitter parser auto-install, so a weak host (e.g. a Pi Zero
-- 2 W) never has to build one. LazyVim's base spec sets
-- opts_extend = { "ensure_installed" }, which makes lazy.nvim *concatenate*
-- a plain-table ensure_installed onto LazyVim's full default list instead of
-- replacing it -- so opts must be a function to actually override the list.
-- ensure_installed must be {} (empty), not a list of Neovim's bundled parsers
-- (c, lua, markdown, ...): nvim-treesitter's own "installed" bookkeeping
-- (get_installed()) only scans its own install dir, never Neovim's bundled
-- parser directory, so even bundled languages are always treated as missing
-- and get build-attempted. Any build needs the tree-sitter CLI, which
-- nvim-treesitter's `main` branch can only fetch via Mason -- unavailable
-- when paired with --no-mason. Filetypes simply fall back to Vim's legacy
-- regex syntax highlighting. Staged into the LazyVim config only when
-- install.sh is run with --minimal-treesitter.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
