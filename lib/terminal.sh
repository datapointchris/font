#!/usr/bin/env bash
# Terminal detection, context capture, and dispatcher
# Supports: Ghostty, Kitty, Windows Terminal

set -euo pipefail

TERMINAL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# The backends read config values through font_trim, and every platform branch
# here reads detect_platform. Both files are guarded on their own end, so
# bin/font sourcing them too is free.
source "$TERMINAL_LIB_DIR/lib.sh"
source "$TERMINAL_LIB_DIR/storage.sh"

source "$TERMINAL_LIB_DIR/terminals/ghostty.sh"
source "$TERMINAL_LIB_DIR/terminals/kitty.sh"
source "$TERMINAL_LIB_DIR/terminals/windows_terminal.sh"
source "$TERMINAL_LIB_DIR/arch-apps.sh"

# Initialize terminal config files if they don't exist
# This prevents errors on first run after fresh install
init_terminal_configs() {
  # Ghostty config
  if [[ ! -d "$GHOSTTY_CONFIG_DIR" ]]; then
    mkdir -p "$GHOSTTY_CONFIG_DIR"
  fi
  if [[ ! -f "$GHOSTTY_CONFIG_FILE" ]]; then
    cat >"$GHOSTTY_CONFIG_FILE" <<EOF
font-family = "monospace"
font-size = 17
EOF
  fi

  # Kitty config
  if [[ ! -d "$KITTY_CONFIG_DIR" ]]; then
    mkdir -p "$KITTY_CONFIG_DIR"
  fi
  if [[ ! -f "$KITTY_CONFIG_FILE" ]]; then
    cat >"$KITTY_CONFIG_FILE" <<EOF
font_family monospace
font_size 17.0
EOF
  fi

  # Arch-specific apps (waybar, hyprlock, dunst)
  init_arch_configs
}

# Run initialization at module load time (same pattern as storage.sh)
init_terminal_configs

detect_terminal() {
  if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    echo "ghostty"
  elif [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
    echo "kitty"
  elif [[ -n "${WT_SESSION:-}" ]]; then
    echo "windows_terminal"
  else
    echo "unknown"
  fi
}

# What a command acting on this terminal's font says when detect_terminal
# returns unknown. Over ssh, or in a tmux server started elsewhere, the
# variable is often what is missing, so the message names each one.
terminal_unknown_error() {
  echo "Error: font cannot tell which terminal this is." >&2
  echo "It knows Ghostty (GHOSTTY_RESOURCES_DIR), Kitty (KITTY_WINDOW_ID) and Windows Terminal (WT_SESSION), and none of those variables is set here." >&2
}

detect_tmux() {
  [[ -n "${TMUX:-}" ]] && echo "true" || echo "false"
}

get_terminal_cols() {
  tput cols 2>/dev/null || echo ""
}

get_terminal_rows() {
  tput lines 2>/dev/null || echo ""
}

get_screen_resolution() {
  local platform="${1:-}"
  [[ -z "$platform" ]] && platform=$(detect_platform 2>/dev/null || echo "unknown")

  case "$platform" in
    macos)
      system_profiler SPDisplaysDataType 2>/dev/null \
        | grep -o 'Resolution: [0-9]* x [0-9]*' \
        | head -1 \
        | sed 's/Resolution: //' \
        | tr -d ' '
      ;;
    archlinux | linux)
      xrandr 2>/dev/null | grep '\*' | awk '{print $1}' | head -1
      ;;
    wsl)
      wmic.exe path Win32_VideoController get CurrentHorizontalResolution,CurrentVerticalResolution 2>/dev/null \
        | awk 'NR==2 {print $1"x"$2}'
      ;;
    *)
      echo ""
      ;;
  esac
}

get_current_font() {
  local terminal
  terminal=$(detect_terminal)

  case "$terminal" in
    ghostty)
      ghostty_get_font
      ;;
    kitty)
      kitty_get_font
      ;;
    windows_terminal)
      windows_terminal_get_font
      ;;
    *)
      echo "Unknown"
      ;;
  esac
}

get_current_font_size() {
  local terminal
  terminal=$(detect_terminal)

  case "$terminal" in
    ghostty)
      ghostty_get_size
      ;;
    kitty)
      kitty_get_size
      ;;
    windows_terminal)
      windows_terminal_get_size
      ;;
    *)
      echo "Unknown"
      ;;
  esac
}

# The terminal size size-up and size-down choose, kept per machine and never
# synced, since each screen wants its own. Like every size font writes, it is
# meant for 0.74em digits, and each terminal gets it scaled to the font it shows.
FONT_TERMINAL_SIZE_FILE="$FONT_STATE_DIR/terminal-size.json"

# Until the first size-up or size-down, this is the size the terminal already
# holds, or 17. It is recorded at once, because the next apply writes a scaled
# size there, and reading that back as the choice would scale it twice.
get_terminal_base_size() {
  local size=""
  if [[ -f "$FONT_TERMINAL_SIZE_FILE" ]]; then
    size=$(jq -r '.size // empty' "$FONT_TERMINAL_SIZE_FILE" 2>/dev/null) || true
  fi
  if [[ -z "$size" ]]; then
    size=$(get_current_font_size) || true
    [[ "$size" == "Unknown" ]] && size=$(ghostty_get_size)
    size="${size:-17}"
    set_terminal_base_size "$size"
  fi
  printf '%s' "$size"
}

set_terminal_base_size() {
  local size="$1"
  mkdir -p "$FONT_STATE_DIR"
  jq -n --argjson size "$size" '{size: $size}' >"$FONT_TERMINAL_SIZE_FILE"
}

terminal_apply_font() {
  local font="$1"
  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")

  local applied=()

  # Always update all terminal configs for consistency across terminals
  ghostty_apply "$font" 2>/dev/null && applied+=("ghostty")
  kitty_apply "$font" 2>/dev/null && applied+=("kitty")

  # Windows Terminal only on WSL
  if [[ "$platform" == "wsl" ]]; then
    windows_terminal_apply "$font" 2>/dev/null && applied+=("windows-terminal")
  fi

  # Arch-specific apps (uses include/source pattern to avoid modifying tracked dotfiles)
  if [[ "$platform" == "archlinux" ]]; then
    local arch_applied
    if arch_applied=$(arch_apply_font "$font" 2>/dev/null); then
      for app in $arch_applied; do
        applied+=("$app")
      done
    fi
  fi

  if [[ ${#applied[@]} -gt 0 ]]; then
    echo "${applied[*]}"
    return 0
  else
    return 1
  fi
}

# Moves this machine's chosen size, then writes every terminal that size scaled
# to the font it shows.
change_font_size() {
  local delta="$1"

  local current_size new_size
  current_size=$(get_terminal_base_size)
  new_size=$(jq -n --argjson size "$current_size" --argjson delta "$delta" '$size + $delta')

  if jq -en --argjson size "$new_size" '$size < 6' >/dev/null; then
    echo "Error: Font size cannot be less than 6" >&2
    return 1
  elif jq -en --argjson size "$new_size" '$size > 72' >/dev/null; then
    echo "Error: Font size cannot be greater than 72" >&2
    return 1
  fi

  set_terminal_base_size "$new_size"

  ghostty_set_size "$(calibrate_font_size "$(ghostty_get_font)" "$new_size")" 2>/dev/null || true
  kitty_set_size "$(calibrate_font_size "$(kitty_get_font)" "$new_size")" 2>/dev/null || true

  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")
  if [[ "$platform" == "wsl" ]]; then
    windows_terminal_set_size "$(calibrate_font_size "$(windows_terminal_get_font)" "$new_size")" 2>/dev/null || true
  fi

  local font
  font=$(ghostty_get_font)
  echo "$current_size → $new_size, which ${font:-monospace} draws at $(calibrate_font_size "$font" "$new_size")"
}

# What a history row records about the terminal an action was typed in. The
# machine and platform come from log_action, which writes them on every row.
get_terminal_context() {
  local terminal
  terminal=$(detect_terminal)
  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")

  local cols rows resolution font_size in_tmux
  cols=$(get_terminal_cols)
  rows=$(get_terminal_rows)
  resolution=$(get_screen_resolution "$platform")
  font_size=$(get_current_font_size)
  in_tmux=$(detect_tmux)

  jq -nc \
    --arg terminal "$terminal" \
    --argjson in_tmux "$in_tmux" \
    --arg cols "$cols" \
    --arg rows "$rows" \
    --arg resolution "$resolution" \
    --arg font_size "$font_size" \
    '{
      terminal: $terminal,
      in_tmux: $in_tmux,
      cols: (if $cols == "" then null else ($cols | tonumber) end),
      rows: (if $rows == "" then null else ($rows | tonumber) end),
      resolution: (if $resolution == "" then null else $resolution end),
      font_size: (if $font_size == "" or $font_size == "Unknown" then null else ($font_size | tonumber) end)
    }'
}
