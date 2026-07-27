#!/usr/bin/env bash
set -euo pipefail

# Overridable so a fork can install itself, and so this script can be exercised
# against the commit under test rather than against whatever is on main. Same
# reasoning as bashselfupdate's own installer, which these mirror.
REPO_URL="${FONT_REPO_URL:-https://github.com/datapointchris/font.git}"
INSTALL_DIR="${FONT_INSTALL_DIR:-$HOME/.local/share/font}"
BIN_DIR="${FONT_BIN_DIR:-$HOME/.local/bin}"
BASHSELFUPDATE_INSTALL_URL="https://raw.githubusercontent.com/datapointchris/bashselfupdate/main/install.sh"

info() { echo "[info] $*"; }
success() { echo "[ok] $*"; }
error() { echo "[error] $*" >&2; }

if ! command -v git &>/dev/null; then
  error "git is required but not installed"
  exit 1
fi

mkdir -p "$BIN_DIR"

# font sources bashselfupdate for `font update` and the daily notice, so the
# installer has to put it there. Idempotent: its own installer fetches and
# re-checks-out when the directory already exists.
info "Installing bashselfupdate..."
if ! curl -fsSL "$BASHSELFUPDATE_INSTALL_URL" | bash >/dev/null; then
  error "Failed to install bashselfupdate (font update depends on it)"
  exit 1
fi
success "bashselfupdate installed"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  info "Installing font..."
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
  fi
  if ! git clone --quiet "$REPO_URL" "$INSTALL_DIR"; then
    error "Failed to clone font repository"
    exit 1
  fi
  success "font cloned to $INSTALL_DIR"
fi

# Moving to the newest tag, not `git pull`. The previous version pulled, which
# fails outright once `font upgrade` has run: a plain `git checkout <tag>`
# leaves a detached HEAD, a detached HEAD has no upstream, and git answers with
# "You are not currently on a branch". Re-running the installer then meant
# reinstalling from scratch.
#
# checkout_latest rather than update: a fresh clone lands on main, which between
# releases is ahead of the newest tag, and update declines a checkout that is not
# sitting on one. It leaves the checkout on a branch and is idempotent, which is
# what makes re-running this script mean what everyone assumes it means.
# shellcheck source=/dev/null
source "${XDG_LIB_HOME:-$HOME/.local/lib}/bashselfupdate/load.bash"

if ! tag=$(bashselfupdate_checkout_latest "$INSTALL_DIR"); then
  error "Failed to move font to its latest release"
  exit 1
fi
success "font at $tag"

ln -sf "$INSTALL_DIR/bin/font" "$BIN_DIR/font"
success "font installed: $BIN_DIR/font"

if command -v font &>/dev/null; then
  info "Run 'font' to get started"
else
  info "Add $BIN_DIR to your PATH, then run 'font'"
fi
