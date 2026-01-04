#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/datapointchris/font.git"
INSTALL_DIR="$HOME/.local/share/font"
BIN_DIR="$HOME/.local/bin"

info() { echo "[info] $*"; }
success() { echo "[ok] $*"; }
error() { echo "[error] $*" >&2; }

if ! command -v git &>/dev/null; then
  error "git is required but not installed"
  exit 1
fi

mkdir -p "$BIN_DIR"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Updating existing installation..."
  if git -C "$INSTALL_DIR" pull --quiet; then
    success "font updated"
  else
    error "Failed to update font"
    exit 1
  fi
else
  info "Installing font..."
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
  fi
  if git clone --quiet "$REPO_URL" "$INSTALL_DIR"; then
    success "font cloned to $INSTALL_DIR"
  else
    error "Failed to clone font repository"
    exit 1
  fi
fi

ln -sf "$INSTALL_DIR/bin/font" "$BIN_DIR/font"
success "font installed: $BIN_DIR/font"

if command -v font &>/dev/null; then
  info "Run 'font' to get started"
else
  info "Add $BIN_DIR to your PATH, then run 'font'"
fi
