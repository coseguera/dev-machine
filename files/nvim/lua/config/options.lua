-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Route yanks through the system clipboard. Over SSH, nvim's built-in OSC 52
-- provider pushes the + register to the client terminal's clipboard. This
-- overrides LazyVim's SSH default, which blanks clipboard when SSH_CONNECTION
-- is set.
vim.opt.clipboard = "unnamedplus"
