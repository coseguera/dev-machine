-- dev-machine: --no-mason
-- Disable Mason and its LazyVim auto-install integration so a weak host (e.g. a
-- Pi Zero 2 W) never downloads or compiles language servers / tools. Neovim +
-- LazyVim still work; LSPs are simply unavailable unless a server is already on
-- PATH. Staged into the LazyVim config only when install.sh is run with --no-mason.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "williamboman/mason.nvim", enabled = false },
  { "williamboman/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
}
