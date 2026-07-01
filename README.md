# dev-machine

The **platform-agnostic, flag-driven** core build for console-first developer
environments (LazyVim + optional Copilot CLI + toolchain + dotfiles). A single
`install.sh` plus a `files/` tree installs the toolchain and stages config into a
target directory.

It is deliberately **host/cloud-unaware** -- it knows nothing about Entra ID,
cloud-init, JIT, USB-gadget, autologin, or admin accounts -- so it can be reused
under any host overlay: an Azure SSH VM, a Pi Zero 2 W (headless or local
console), or an rpi4/rpi5 desktop. The build **shape** is selected entirely by
granular on/off flags.

## What it does

- Always installs system-wide tools: `git`, `ripgrep`, `fd`, `fzf`, `jq`,
  `git-delta`, `tmux`, build deps, Python venv/pipx; `gh`; Neovim (release) +
  the LazyVim starter config.
- Optionally installs Node.js + Copilot CLI, lazygit, a local console
  (cage + foot), or a local desktop (sway + browser) -- see the flags below.

It uses no system keyring: the agentic `@github/copilot` CLI keeps its token in a
file under `~/.copilot`, so there is nothing to unlock.

## Usage

```sh
sudo ./install.sh [options]
```

| Flag | Effect |
|---|---|
| `--target-dir DIR` | Where dotfiles are staged. Default `/etc/skel`. |
| `--no-copilot` | Skip the Copilot CLI npm global install. |
| `--no-node` | Skip Node.js entirely (implies `--no-copilot`). |
| `--no-mason` | Disable LazyVim Mason LSP/tool auto-install (lite). |
| `--minimal-treesitter` | Trim Treesitter to a minimal parser set (lite). |
| `--no-lazygit` | Skip the lazygit release download. |
| `--with-console` | Install cage + foot + a Nerd Font; stage `foot.ini`. |
| `--with-desktop` | Install sway + foot + i3status + wofi + grim/slurp + fonts. |
| `--with-browser=NAME` | `firefox` \| `chromium` \| `none` (default `none`). Requires `--with-desktop`. |

- `--target-dir /etc/skel` (default) -- a **multi-user template**: each new
  user's home is seeded from it (e.g. Entra SSH first login via `pam_mkhomedir`).
- `--target-dir "$HOME"` -- a **single machine/user** (e.g. a Pi or laptop).

Requires root (installs system packages). Re-runnable: each step guards itself.
Targets Debian/Ubuntu, `amd64` or `arm64`.

### Example shapes

```sh
# Azure SSH VM / capable host: the full environment.
sudo ./install.sh --target-dir /etc/skel

# Pi Zero 2 W, headless: no Copilot/Node, no heavy LSP/parsers.
sudo ./install.sh --target-dir "$HOME" \
  --no-node --no-mason --minimal-treesitter

# Pi Zero 2 W, local console kiosk (cage + foot).
sudo ./install.sh --target-dir "$HOME" \
  --no-node --no-mason --minimal-treesitter --with-console
```

## Layout

```
install.sh                          # flag-driven installer
files/
  tmux.conf                         -> <target>/.tmux.conf
  gitconfig                         -> <target>/.gitconfig
  bashrc.d/10-dev-machine.sh        -> <target>/.bashrc.d/
  lazygit/config.yml                -> <target>/.config/lazygit/config.yml
  nvim/lua/config/options.lua       -> overrides LazyVim options (OSC 52 clipboard)
  nvim/lua/plugins/lite-no-mason.lua    -> staged only with --no-mason
  nvim/lua/plugins/lite-treesitter.lua  -> staged only with --minimal-treesitter
  console/foot.ini                  -> staged with --with-console or --with-desktop
  desktop/sway/config               -> staged only with --with-desktop
  desktop/i3status/config           -> staged only with --with-desktop
  desktop/wofi/config               -> staged only with --with-desktop
  desktop/wofi/style.css            -> staged only with --with-desktop
```

The terminal for `--with-desktop` is **foot** (Wayland-native, CPU-rendered, tiny;
pairs with tmux for multiplexing), the same terminal used by `--with-console`
(cage), with Sixel image support disabled to shrink its attack surface. The
launcher is **wofi** and screenshots use **grim + slurp + wl-clipboard**. Browsers
install as real Raspberry Pi OS
.debs (`firefox-esr` / `chromium-browser`), never snaps.

## How host overlays consume it

Each host adds a **thin overlay** that does its own setup (datasource, autologin,
session launch, provisioning), then runs this core build with the flags it wants.
For example, `azure-dev-terminal` mounts this repo as a git submodule at
`core-build/` and inlines it (base64 tarball) into its cloud-init custom-data,
then runs `install.sh --target-dir /etc/skel`. A Pi overlay wires tty1 autologin
to `cage -s -- foot` (console) or `sway` (desktop) and runs `install.sh`
with the matching `--with-*` flags. Wiring the session launch is the overlay's
job; this script only installs packages and stages config.
