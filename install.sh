#!/usr/bin/env bash
# =============================================================================
# dev-machine -- core build installer (platform-agnostic, flag-driven)
# -----------------------------------------------------------------------------
# Installs a system-wide developer toolchain and stages dotfiles + a LazyVim
# config into a TARGET directory. The build SHAPE is selected entirely by
# granular on/off flags, so the same script targets hosts from a Pi Zero 2 W
# (headless) up to an rpi4/rpi5 desktop or an Azure SSH VM.
#
# This script is intentionally HOST/CLOUD-UNAWARE: it knows nothing about Entra
# ID, cloud-init, JIT, NSGs, USB-gadget, autologin, or admin accounts. It only
# installs packages and stages config into --target-dir. Wiring a host's session
# launch (tty1 autologin -> cage+foot, or startx -> i3, or Azure provisioning)
# is the job of the host overlay that CALLS this script.
#
# What it installs (system-wide, on PATH), subject to flags:
#   - CLI toolchain: git, ripgrep, fd, fzf, jq, git-delta, tmux, build deps,
#     Python venv/pipx                                            (always)
#   - gh (GitHub CLI)                                             (always)
#   - Node.js (NodeSource)                                        (unless --no-node)
#   - Copilot CLI (npm global)                                    (unless --no-copilot/--no-node)
#   - Neovim (release) + LazyVim starter config                  (always)
#   - lazygit (release)                                           (unless --no-lazygit)
#   - cage + foot + Nerd Font (local kiosk console)              (--with-console)
#   - i3 + Xorg + i3status + alacritty + flameshot + fonts (desktop) (--with-desktop)
#   - a browser                                                   (--with-browser=...)
#
# LazyVim "lite" knobs (staged as override Lua specs, only when set):
#   --no-mason            disable Mason LSP/tool auto-install
#   --minimal-treesitter  trim Treesitter to a minimal parser set; no auto-install
#
# Usage:
#   sudo ./install.sh [options]
#     --target-dir DIR        Where dotfiles are staged. Default: /etc/skel
#                             - /etc/skel  -> multi-user template; each new user's
#                               home is seeded from it (e.g. Entra SSH + pam_mkhomedir).
#                             - a real $HOME -> a single machine/user (Pi/laptop).
#     --no-copilot            Skip the Copilot CLI npm global install.
#     --no-node               Skip Node.js entirely (implies --no-copilot).
#     --no-mason              Disable LazyVim Mason LSP/tool auto-install.
#     --minimal-treesitter    Trim Treesitter to a minimal parser set.
#     --no-lazygit            Skip the lazygit release download.
#     --with-console          Install cage + foot + a Nerd Font; stage foot.ini.
#     --with-desktop          Install i3 + Xorg + i3status + alacritty + flameshot.
#     --with-browser=NAME     firefox | chromium | none (default none).
#                             Requires --with-desktop when not 'none'.
#     -h | --help             Show this header.
#
# Requires root (installs system packages). Re-runnable: each step guards itself.
# =============================================================================
set -uo pipefail

TARGET_DIR="/etc/skel"
NO_COPILOT=0
NO_NODE=0
NO_MASON=0
MIN_TS=0
NO_LAZYGIT=0
WITH_CONSOLE=0
WITH_DESKTOP=0
BROWSER="none"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir) TARGET_DIR="${2:?--target-dir needs a value}"; shift 2 ;;
    --target-dir=*) TARGET_DIR="${1#*=}"; shift ;;
    --no-copilot) NO_COPILOT=1; shift ;;
    --no-node) NO_NODE=1; NO_COPILOT=1; shift ;;
    --no-mason) NO_MASON=1; shift ;;
    --minimal-treesitter) MIN_TS=1; shift ;;
    --no-lazygit) NO_LAZYGIT=1; shift ;;
    --with-console) WITH_CONSOLE=1; shift ;;
    --with-desktop) WITH_DESKTOP=1; shift ;;
    --with-browser) BROWSER="${2:?--with-browser needs a value}"; shift 2 ;;
    --with-browser=*) BROWSER="${1#*=}"; shift ;;
    -h|--help) sed -n '2,49p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

log()  { echo "[dev-machine] $*"; }
die()  { echo "[dev-machine] ERROR: $*" >&2; exit 1; }

# Install JetBrainsMono Nerd Font system-wide (glyphs for foot/i3/terminals).
# Arch-independent (font files). Idempotent: skips if already installed.
install_nerd_font() {
  if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    log "JetBrainsMono Nerd Font already present"
    return 0
  fi
  log "installing JetBrainsMono Nerd Font"
  local dest="/usr/local/share/fonts/JetBrainsMonoNerdFont"
  mkdir -p "$dest"
  curl -fsSL -o /tmp/JetBrainsMono.tar.xz \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
    || die "Nerd Font download failed"
  tar -C "$dest" -xJf /tmp/JetBrainsMono.tar.xz || die "Nerd Font extract failed"
  rm -f /tmp/JetBrainsMono.tar.xz
  fc-cache -f "$dest" >/dev/null 2>&1 || true
}

# Install the selected browser (Raspberry Pi OS / Debian real .debs, no snaps).
install_browser() {
  case "$BROWSER" in
    firefox)
      apt-get install -y firefox-esr || die "firefox-esr install failed" ;;
    chromium)
      apt-get install -y chromium-browser \
        || apt-get install -y chromium \
        || die "chromium install failed" ;;
    none) : ;;
  esac
}

# --- Validate flags ----------------------------------------------------------
case "$BROWSER" in
  none|firefox|chromium) ;;
  *) die "--with-browser must be one of: firefox, chromium, none (got '$BROWSER')" ;;
esac
if [ "$BROWSER" != "none" ] && [ "$WITH_DESKTOP" -ne 1 ]; then
  die "--with-browser=$BROWSER requires --with-desktop (a browser needs a desktop)"
fi

[ "$(id -u)" -eq 0 ] || die "must run as root (installs system packages)"
[ -d "$FILES_DIR" ] || die "files/ dir not found next to install.sh ($FILES_DIR)"

export DEBIAN_FRONTEND=noninteractive

# On a fresh cloud VM, unattended-upgrades / apt-daily timers and (under cloud-init)
# the platform's own package phase run apt CONCURRENTLY and hold the dpkg lock. Without
# this, an early `apt-get` aborts the whole build with "Could not get lock". Make EVERY
# apt invocation -- including those run by third-party setup scripts such as NodeSource --
# WAIT for the lock instead of failing. (DPkg::Lock::Timeout is honored by apt >= 1.9.11.)
if [ -d /etc/apt ]; then
  mkdir -p /etc/apt/apt.conf.d
  echo 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/99dev-machine-lock-timeout
fi

ARCH="$(dpkg --print-architecture)"   # amd64 | arm64
case "$ARCH" in
  amd64) NVIM_ARCH="x86_64"; LG_ARCH="x86_64" ;;
  arm64) NVIM_ARCH="arm64";  LG_ARCH="arm64"  ;;
  *)     die "unsupported architecture: $ARCH" ;;
esac

# --- System packages (the dev toolchain + LazyVim deps) ----------------------
log "installing apt packages"
apt-get update -y
apt-get install -y \
  build-essential pkg-config git curl ca-certificates gnupg unzip jq \
  ripgrep fd-find fzf git-delta \
  python3-venv python3-pip pipx \
  tmux \
  || die "apt package install failed"

# --- fd symlink (Debian/Ubuntu ship the binary as fdfind) --------------------
if command -v fdfind >/dev/null 2>&1 && [ ! -e /usr/local/bin/fd ]; then
  ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

# --- GitHub CLI from the official apt repo -----------------------------------
if ! command -v gh >/dev/null 2>&1; then
  log "installing gh"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y gh || die "gh install failed"
fi

# --- Node.js (system-wide) via NodeSource; provides node + npm on PATH -------
if [ "$NO_NODE" -eq 1 ]; then
  log "skipping Node.js (--no-node)"
elif ! command -v node >/dev/null 2>&1; then
  log "installing Node.js (system-wide)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || die "NodeSource setup failed"
  apt-get install -y nodejs || die "nodejs install failed"
fi

# --- Copilot CLI (system-wide global) ----------------------------------------
if [ "$NO_COPILOT" -eq 1 ]; then
  log "skipping Copilot CLI (--no-copilot)"
elif ! command -v copilot >/dev/null 2>&1; then
  log "installing Copilot CLI"
  npm install -g @github/copilot || die "Copilot CLI install failed"
fi

# --- Neovim from the latest GitHub release (newer than apt) ------------------
# Fail loudly on download failure: the apt nvim is too old for current LazyVim,
# so a silent fallback would produce a confusingly broken editor.
if ! command -v nvim >/dev/null 2>&1; then
  log "installing Neovim (release)"
  TARBALL="nvim-linux-${NVIM_ARCH}.tar.gz"
  curl -fsSL -o /tmp/nvim.tar.gz \
    "https://github.com/neovim/neovim/releases/latest/download/${TARBALL}" \
    || die "Neovim release download failed (apt nvim is too old for LazyVim)"
  rm -rf /opt/nvim
  tar -C /opt -xzf /tmp/nvim.tar.gz
  mv "/opt/nvim-linux-${NVIM_ARCH}" /opt/nvim
  ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -f /tmp/nvim.tar.gz
fi

# --- lazygit from the latest GitHub release ----------------------------------
if [ "$NO_LAZYGIT" -eq 1 ]; then
  log "skipping lazygit (--no-lazygit)"
elif ! command -v lazygit >/dev/null 2>&1; then
  log "installing lazygit"
  LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
            | jq -r '.tag_name' | sed 's/^v//')"
  if [ -n "$LG_VER" ] && [ "$LG_VER" != "null" ]; then
    curl -fsSL -o /tmp/lazygit.tar.gz \
      "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_${LG_ARCH}.tar.gz" \
      || die "lazygit download failed"
    tar -C /usr/local/bin -xzf /tmp/lazygit.tar.gz lazygit
    rm -f /tmp/lazygit.tar.gz
  else
    die "could not resolve latest lazygit version"
  fi
fi

# --- Local console: cage (Wayland kiosk) + foot (truecolor terminal) ---------
# Installs the packages and stages foot.ini. Wiring tty1 autologin -> `cage -s --
# foot` is the host overlay's job (this script stays session-launch-agnostic).
if [ "$WITH_CONSOLE" -eq 1 ]; then
  log "installing local console (cage + foot)"
  apt-get install -y cage foot fontconfig || die "console package install failed"
  install_nerd_font
fi

# --- Local desktop: i3 + Xorg + i3status + alacritty + browser -----------------
# Installs the packages and stages the rice configs (i3, i3status, alacritty,
# rofi). Wiring startx/i3 launch on tty1 is the host overlay's job (this script
# stays session-launch-agnostic). Terminal is alacritty (Rust, memory-safe,
# minimal attack surface). Config staging happens in the staging section below.
if [ "$WITH_DESKTOP" -eq 1 ]; then
  log "installing local desktop (i3 + Xorg + alacritty)"
  apt-get install -y \
    xserver-xorg xinit x11-xserver-utils \
    i3 rofi alacritty \
    flameshot \
    fontconfig fonts-noto-color-emoji \
    || die "desktop package install failed"
  install_nerd_font
  install_browser
fi

# --- Stage dotfiles into TARGET ----------------------------------------------
log "staging dotfiles into $TARGET_DIR"
mkdir -p "$TARGET_DIR/.bashrc.d" "$TARGET_DIR/.config/lazygit"
install -m 0644 "$FILES_DIR/tmux.conf"  "$TARGET_DIR/.tmux.conf"
install -m 0644 "$FILES_DIR/gitconfig"  "$TARGET_DIR/.gitconfig"
install -m 0644 "$FILES_DIR/bashrc.d/"*.sh "$TARGET_DIR/.bashrc.d/"
install -m 0644 "$FILES_DIR/lazygit/config.yml" "$TARGET_DIR/.config/lazygit/config.yml"

# --- Ensure TARGET .bashrc sources ~/.bashrc.d/*.sh --------------------------
touch "$TARGET_DIR/.bashrc"
if ! grep -q 'bashrc.d/\*.sh' "$TARGET_DIR/.bashrc" 2>/dev/null; then
  cat >> "$TARGET_DIR/.bashrc" <<'RC'

# dev-machine: load drop-in shell config
if [ -d "$HOME/.bashrc.d" ]; then
  for _rc in "$HOME"/.bashrc.d/*.sh; do
    [ -r "$_rc" ] && . "$_rc"
  done
  unset _rc
fi
RC
fi

# --- Stage foot.ini when the console was installed ---------------------------
if [ "$WITH_CONSOLE" -eq 1 ]; then
  log "staging foot.ini into $TARGET_DIR"
  mkdir -p "$TARGET_DIR/.config/foot"
  install -m 0644 "$FILES_DIR/console/foot.ini" "$TARGET_DIR/.config/foot/foot.ini"
fi

# --- Stage desktop rice configs when the desktop was installed ---------------
if [ "$WITH_DESKTOP" -eq 1 ]; then
  log "staging desktop configs (i3, i3status, alacritty, rofi) into $TARGET_DIR"
  mkdir -p "$TARGET_DIR/.config/i3" "$TARGET_DIR/.config/i3status" \
           "$TARGET_DIR/.config/alacritty" "$TARGET_DIR/.config/rofi"
  install -m 0644 "$FILES_DIR/desktop/i3/config"        "$TARGET_DIR/.config/i3/config"
  install -m 0755 "$FILES_DIR/desktop/i3/set-dpi.sh"    "$TARGET_DIR/.config/i3/set-dpi.sh"
  install -m 0644 "$FILES_DIR/desktop/i3status/config"  "$TARGET_DIR/.config/i3status/config"
  install -m 0644 "$FILES_DIR/desktop/rofi/config.rasi" "$TARGET_DIR/.config/rofi/config.rasi"
  # flameshot screenshots (bound to Print / $mod+Shift+p in i3). Config disables the
  # tray icon (i3bar has no systray here) and the startup popup; savePath is left
  # unset so flameshot uses the XDG Pictures dir (~/Pictures), which keeps this
  # home-agnostic for /etc/skel-based multi-user provisioning. Pre-create ~/Pictures
  # so the first save never fails on a minimal image.
  mkdir -p "$TARGET_DIR/.config/flameshot" "$TARGET_DIR/Pictures"
  install -m 0644 "$FILES_DIR/desktop/flameshot/flameshot.ini" "$TARGET_DIR/.config/flameshot/flameshot.ini"
  # alacritty switched its config format from YAML to TOML in 0.13; stage the form
  # that matches the installed version (Pi OS Bookworm ships 0.12 = YAML).
  av="$(alacritty --version 2>/dev/null | awk '{print $2}')"   # e.g. 0.12.3
  use_toml=0
  if [ -n "$av" ]; then
    maj="${av%%.*}"; rest="${av#*.}"; min="${rest%%.*}"
    if [ "${maj:-0}" -gt 0 ] 2>/dev/null || { [ "${maj:-0}" -eq 0 ] && [ "${min:-0}" -ge 13 ]; } 2>/dev/null; then
      use_toml=1
    fi
  fi
  if [ "$use_toml" -eq 1 ]; then
    install -m 0644 "$FILES_DIR/desktop/alacritty/alacritty.toml" "$TARGET_DIR/.config/alacritty/alacritty.toml"
    rm -f "$TARGET_DIR/.config/alacritty/alacritty.yml"
  else
    install -m 0644 "$FILES_DIR/desktop/alacritty/alacritty.yml" "$TARGET_DIR/.config/alacritty/alacritty.yml"
    rm -f "$TARGET_DIR/.config/alacritty/alacritty.toml"
  fi
fi

# --- Stage the LazyVim config into TARGET ------------------------------------
# Only the config is staged; Lazy.nvim installs plugins on the first `nvim` run.
# Keeps the build simple -- one git clone, no headless sync -- at the cost of a
# one-time plugin download the first time nvim opens.
SKEL_NVIM="$TARGET_DIR/.config/nvim"
if [ ! -e "$SKEL_NVIM/init.lua" ]; then
  log "staging LazyVim config into $TARGET_DIR"
  mkdir -p "$TARGET_DIR/.config"
  git clone --depth 1 https://github.com/LazyVim/starter "$SKEL_NVIM" \
    || die "LazyVim starter clone failed"
  rm -rf "$SKEL_NVIM/.git"
  # Override options.lua to route yanks through the OSC 52 system clipboard.
  install -m 0644 "$FILES_DIR/nvim/lua/config/options.lua" \
    "$SKEL_NVIM/lua/config/options.lua"
fi

# --- LazyVim "lite" override specs (only when requested) ---------------------
# Staged into lua/plugins/ so they layer on top of the starter regardless of when
# the config was first cloned (idempotent: install -m re-copies on every run).
mkdir -p "$SKEL_NVIM/lua/plugins"
if [ "$NO_MASON" -eq 1 ]; then
  log "staging --no-mason LazyVim override"
  install -m 0644 "$FILES_DIR/nvim/lua/plugins/lite-no-mason.lua" \
    "$SKEL_NVIM/lua/plugins/lite-no-mason.lua"
else
  rm -f "$SKEL_NVIM/lua/plugins/lite-no-mason.lua"
fi
if [ "$MIN_TS" -eq 1 ]; then
  log "staging --minimal-treesitter LazyVim override"
  install -m 0644 "$FILES_DIR/nvim/lua/plugins/lite-treesitter.lua" \
    "$SKEL_NVIM/lua/plugins/lite-treesitter.lua"
else
  rm -f "$SKEL_NVIM/lua/plugins/lite-treesitter.lua"
fi

# --- Normalize ownership/permissions of the staged paths ---------------------
# Match the TARGET dir's owner (root:root for /etc/skel; the user for a real
# $HOME), so a root-run install does not leave root-owned files in a user home.
owner="$(stat -c '%U' "$TARGET_DIR")"
group="$(stat -c '%G' "$TARGET_DIR")"
for p in .tmux.conf .gitconfig .bashrc .bashrc.d .config/nvim .config/lazygit .config/foot .config/i3 .config/i3status .config/alacritty .config/rofi .config/flameshot Pictures; do
  [ -e "$TARGET_DIR/$p" ] || continue
  chown -R "$owner:$group" "$TARGET_DIR/$p"
  find "$TARGET_DIR/$p" -type d -exec chmod 0755 {} +
done

log "core build complete (target: $TARGET_DIR)"
