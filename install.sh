#!/usr/bin/env bash
set -euo pipefail

# Overridable so a fork can install itself, and so this script can be exercised
# against the commit under test rather than against whatever is on main. Same
# reasoning as bashselfupdate's own installer, which these mirror.
REPO_URL="${FONT_REPO_URL:-https://github.com/datapointchris/font.git}"
INSTALL_DIR="${FONT_INSTALL_DIR:-$HOME/.local/share/font}"
BIN_DIR="${FONT_BIN_DIR:-$HOME/.local/bin}"
BASHSELFUPDATE_REPO_URL="${BASHSELFUPDATE_REPO_URL:-https://github.com/datapointchris/bashselfupdate.git}"
BASHSELFUPDATE_INSTALL_URL="https://github.com/datapointchris/bashselfupdate"

info() { echo "[info] $*"; }
success() { echo "[ok] $*"; }
error() { echo "[error] $*" >&2; }

if ! command -v git &>/dev/null; then
  error "git is required but not installed"
  exit 1
fi

mkdir -p "$BIN_DIR"

# font sources bashselfupdate for `font update` and the daily notice.
#
# Cloned with git rather than piped from its install script over curl, because
# git is the one transport this installer already requires, and the two are not
# equally available: a locked-down network can allow github.com over git while
# blocking raw.githubusercontent.com. A second transport would make font
# uninstallable on a machine that reaches github.com over git alone.
#
# Sourced from the fresh clone and then pointed at itself, so the tag comparator
# lives in one place. `git tag --sort=-v:refname` here would be the sort -V
# ordering the library exists to replace.
install_bashselfupdate() {
  local dir="${XDG_LIB_HOME:-$HOME/.local/lib}/bashselfupdate"

  if [[ ! -d "$dir/.git" ]]; then
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir")"
    git clone --quiet "$BASHSELFUPDATE_REPO_URL" "$dir" || return 1
  fi

  source "$dir/lib/version.sh"
  source "$dir/lib/source.sh"
  source "$dir/lib/update.sh"

  bashselfupdate_checkout_latest "$dir" >/dev/null
}

# Not fatal. font works without it — only `font update` and the daily notice
# need it, and bin/font degrades to an actionable error and silence
# respectively. Failing the whole install here would make an unreachable
# github.com cost the user a working font command for no reason.
info "Installing bashselfupdate..."
if install_bashselfupdate; then
  success "bashselfupdate installed"
else
  error "Could not install bashselfupdate — 'font update' will not work until it is"
  error "  Install it separately: $BASHSELFUPDATE_INSTALL_URL"
fi

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

# Moving to the newest tag, not `git pull`. `font update` leaves the checkout on
# a local `release` branch with no upstream, and `git pull` there fails with
# "There is no tracking information for the current branch".
#
# checkout_latest rather than update: a fresh clone lands on main, which between
# releases is ahead of the newest tag, and update declines a checkout that is not
# sitting on one. checkout_latest fetches the tags and moves the checkout with
# `git checkout -B`, which lands on the newest tag from any starting point. That
# is what makes re-running this script safe. The branch only keeps HEAD attached.
if declare -F bashselfupdate_checkout_latest &>/dev/null; then
  if ! tag=$(bashselfupdate_checkout_latest "$INSTALL_DIR"); then
    error "Failed to move font to its latest release"
    exit 1
  fi
  success "font at $tag"
else
  # Without the library there is no comparator to pick the newest tag with, so
  # this tracks the branch instead. Reachable only when bashselfupdate could not
  # be installed above. A fresh clone is on main, which pull moves. A checkout an
  # earlier run put on `release` has no upstream, and pull fails with git's own
  # message.
  if ! git -C "$INSTALL_DIR" pull --quiet; then
    error "Failed to update font"
    exit 1
  fi
  success "font updated from $(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)"
fi

ln -sf "$INSTALL_DIR/bin/font" "$BIN_DIR/font"
success "font installed: $BIN_DIR/font"

if command -v font &>/dev/null; then
  info "Run 'font' to get started"
else
  info "Add $BIN_DIR to your PATH, then run 'font'"
fi
