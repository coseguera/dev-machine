-- Opens the Snacks terminal as a large floating window flush to the top,
-- right, and bottom edges (a ~95%-wide right-side overlay). A float is used
-- instead of a split so it never reflows/crushes the file explorer: the
-- explorer is left intact underneath and returns exactly as before on hide.
-- All other terminal behavior (toggle, keymaps, auto-insert) is unchanged.
-- Because the no-command terminal keymaps (<C-/>, <C-_>, <leader>ft) share a
-- single Snacks terminal instance, this affects all of them.

return {
  "folke/snacks.nvim",
  opts = {
    terminal = {
      win = {
        position = "float",
        border = "none",
        height = 0,
        width = 0.95,
        row = 0,
        col = function()
          return vim.o.columns - math.floor(vim.o.columns * 0.95)
        end,
      },
    },
  },
}
