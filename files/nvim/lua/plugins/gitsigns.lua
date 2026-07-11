-- Adds a toggle that restyles gitsigns from plain gutter signs into a
-- LazyGit-style inline diff: green added/changed lines, red removed lines
-- shown inline, plus word-level highlighting. The diff base is unchanged
-- (working tree vs index), so only the appearance toggles.

local diff_look_enabled = false

local function toggle_diff_look()
  local gs = require("gitsigns")
  diff_look_enabled = not diff_look_enabled

  -- toggle_* helpers accept an explicit target state, keeping the three
  -- display options in sync regardless of their previous individual state.
  gs.toggle_linehl(diff_look_enabled)
  gs.toggle_deleted(diff_look_enabled)
  gs.toggle_word_diff(diff_look_enabled)

  -- linehl and the deleted virtual lines only repaint on the next update,
  -- so force a refresh to apply the look immediately.
  gs.refresh()

  vim.notify(
    "Inline git diff " .. (diff_look_enabled and "ON" or "OFF"),
    vim.log.levels.INFO,
    { title = "gitsigns" }
  )
end

return {
  "lewis6991/gitsigns.nvim",
  keys = {
    { "<leader>g<space>", toggle_diff_look, desc = "Toggle inline git diff (LazyGit style)" },
  },
}
