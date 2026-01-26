#!/usr/bin/env bash
# Terminal detection, context capture, and dispatcher
# Supports: Ghostty, Kitty, Windows Terminal

set -euo pipefail

TERMINAL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

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
    cat > "$GHOSTTY_CONFIG_FILE" << EOF
font-family = "monospace"
font-size = 17
EOF
  fi

  # Kitty config
  if [[ ! -d "$KITTY_CONFIG_DIR" ]]; then
    mkdir -p "$KITTY_CONFIG_DIR"
  fi
  if [[ ! -f "$KITTY_CONFIG_FILE" ]]; then
    cat > "$KITTY_CONFIG_FILE" << EOF
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
      system_profiler SPDisplaysDataType 2>/dev/null | \
        grep -o 'Resolution: [0-9]* x [0-9]*' | \
        head -1 | \
        sed 's/Resolution: //' | \
        tr -d ' '
      ;;
    arch|linux)
      xrandr 2>/dev/null | grep '\*' | awk '{print $1}' | head -1
      ;;
    wsl)
      wmic.exe path Win32_VideoController get CurrentHorizontalResolution,CurrentVerticalResolution 2>/dev/null | \
        awk 'NR==2 {print $1"x"$2}'
      ;;
    *)
      echo ""
      ;;
  esac
}

get_machine_id() {
  local platform="${1:-}"
  [[ -z "$platform" ]] && platform=$(detect_platform 2>/dev/null || echo "unknown")
  local hostname
  hostname=$(hostname -s 2>/dev/null || hostname)
  echo "${platform}-${hostname}"
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
  if [[ "$platform" == "arch" ]]; then
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

change_font_size() {
  local delta="$1"

  local current_size
  current_size=$(get_current_font_size)

  if [[ "$current_size" == "Unknown" || -z "$current_size" ]]; then
    echo "Error: Could not read current font size" >&2
    echo "Run 'font apply <name>' first to initialize font config" >&2
    return 1
  fi

  local new_size=$((current_size + delta))

  if [[ "$new_size" -lt 6 ]]; then
    echo "Error: Font size cannot be less than 6" >&2
    return 1
  elif [[ "$new_size" -gt 72 ]]; then
    echo "Error: Font size cannot be greater than 72" >&2
    return 1
  fi

  # Update all terminal configs for consistency
  ghostty_set_size "$new_size" 2>/dev/null || true
  kitty_set_size "$new_size" 2>/dev/null || true

  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")
  if [[ "$platform" == "wsl" ]]; then
    windows_terminal_set_size "$new_size" 2>/dev/null || true
  fi

  echo "$current_size → $new_size"
}

get_terminal_context() {
  local terminal
  terminal=$(detect_terminal)
  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")

  local cols rows resolution font_size in_tmux machine
  cols=$(get_terminal_cols)
  rows=$(get_terminal_rows)
  resolution=$(get_screen_resolution "$platform")
  font_size=$(get_current_font_size)
  in_tmux=$(detect_tmux)
  machine=$(get_machine_id "$platform")

  jq -nc \
    --arg terminal "$terminal" \
    --arg machine "$machine" \
    --arg platform "$platform" \
    --argjson in_tmux "$in_tmux" \
    --arg cols "$cols" \
    --arg rows "$rows" \
    --arg resolution "$resolution" \
    --arg font_size "$font_size" \
    '{
      terminal: $terminal,
      machine: $machine,
      platform: $platform,
      in_tmux: $in_tmux,
      cols: (if $cols == "" then null else ($cols | tonumber) end),
      rows: (if $rows == "" then null else ($rows | tonumber) end),
      resolution: (if $resolution == "" then null else $resolution end),
      font_size: (if $font_size == "" or $font_size == "Unknown" then null else ($font_size | tonumber) end)
    }'
}
