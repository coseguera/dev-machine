# dev-machine shell setup (sourced from ~/.bashrc)
# tmux reattach-or-new: survives SSH/console disconnects.
alias ta='tmux attach -t main 2>/dev/null || tmux new -s main'
