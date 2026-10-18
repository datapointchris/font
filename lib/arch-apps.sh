#!/usr/bin/env bash
# Arch-specific application backends (Waybar, Hyprlock, Dunst)
# Uses include/source patterns to avoid modifying tracked dotfiles

# Waybar: Uses @import - style.css imports fonts/current.css which sets font-family
# (GTK CSS doesn't support var() so we set the property directly)
WAYBAR_FONTS_DIR="$HOME/.config/waybar/fonts"
WAYBAR_FONTS_FILE="$WAYBAR_FONTS_DIR/current.css"

# Hyprlock: Uses source and variables
HYPRLOCK_FONTS_DIR="$HOME/.config/hypr/fonts"
HYPRLOCK_FONTS_FILE="$HYPRLOCK_FONTS_DIR/current.conf"

# Dunst: Uses drop-in directory
DUNST_DROPIN_DIR="$HOME/.config/dunst/dunstrc.d"
DUNST_FONTS_FILE="$DUNST_DROPIN_DIR/99-font.conf"

# Initialize Arch app config files if they don't exist
init_arch_configs() {
  # Only initialize on Arch/Linux
  local platform
  platform=$(detect_platform 2>/dev/null || echo "unknown")
  [[ "$platform" != "archlinux" ]] && return 0

  # Waybar fonts
  if [[ -d "$HOME/.config/waybar" ]]; then
    if [[ ! -d "$WAYBAR_FONTS_DIR" ]]; then
      mkdir -p "$WAYBAR_FONTS_DIR"
    fi
    if [[ ! -f "$WAYBAR_FONTS_FILE" ]]; then
      cat >"$WAYBAR_FONTS_FILE" <<'EOF'
/* Font configuration - managed by font tool */
* {
    font-family: "monospace", monospace;
}
EOF
    fi
  fi

  # Hyprlock fonts
  if [[ -d "$HOME/.config/hypr" ]]; then
    if [[ ! -d "$HYPRLOCK_FONTS_DIR" ]]; then
      mkdir -p "$HYPRLOCK_FONTS_DIR"
    fi
    if [[ ! -f "$HYPRLOCK_FONTS_FILE" ]]; then
      cat >"$HYPRLOCK_FONTS_FILE" <<'EOF'
# Font configuration - managed by font tool
# Source this in hyprlock.conf: source = ~/.config/hypr/fonts/current.conf
# Then use: font_family = $font
$font = monospace
EOF
    fi
  fi

  # Dunst fonts (drop-in directory)
  if [[ -d "$HOME/.config/dunst" ]]; then
    if [[ ! -d "$DUNST_DROPIN_DIR" ]]; then
      mkdir -p "$DUNST_DROPIN_DIR"
    fi
    if [[ ! -f "$DUNST_FONTS_FILE" ]]; then
      cat >"$DUNST_FONTS_FILE" <<'EOF'
# Font configuration - managed by font tool
# This drop-in overrides font setting from dunstrc
[global]
font = monospace 10
EOF
    fi
  fi
}

waybar_set_font() {
  local font="$1"

  mkdir -p "$WAYBAR_FONTS_DIR"

  cat >"$WAYBAR_FONTS_FILE" <<EOF
/* Font configuration - managed by font tool */
* {
    font-family: "${font}", monospace;
}
EOF

  # A restart rather than SIGUSR2. When playerctld starts after waybar, its
  # mpris module leaks a player whose handlers outlive the module a reload
  # destroys, and the next player event segfaults waybar. A process started
  # while playerctld runs holds no leaked player.
  if pgrep -x waybar &>/dev/null; then
    pkill -x waybar 2>/dev/null || true
    start_session_daemon waybar
  fi
}

# Starts a desktop daemon outside the apply's cgroup, which systemd kills when
# an apply run as a service ends, setsid or not. Hyprland's child sits where
# login started it. A transient scope is the fallback.
start_session_daemon() {
  local program="$1"
  if command -v hyprctl &>/dev/null \
    && [[ "$(hyprctl dispatch "hl.dsp.exec_cmd('$program')" 2>/dev/null)" == "ok" ]]; then
    return 0
  fi
  if systemctl --user show-environment &>/dev/null; then
    systemd-run --user --scope --collect --quiet "$program" >/dev/null 2>&1 </dev/null &
  else
    setsid "$program" >/dev/null 2>&1 </dev/null &
  fi
  disown
}

hyprlock_set_font() {
  local font="$1"

  mkdir -p "$HYPRLOCK_FONTS_DIR"

  cat >"$HYPRLOCK_FONTS_FILE" <<EOF
# Font configuration - managed by font tool
\$font = ${font}
EOF
}

dunst_get_size() {
  if [[ -f "$DUNST_FONTS_FILE" ]]; then
    grep '^font = ' "$DUNST_FONTS_FILE" 2>/dev/null \
      | grep -o '[0-9]*$' | head -1
  else
    echo "10"
  fi
}

dunst_set_font() {
  local font="$1"
  local size
  size=$(dunst_get_size)
  [[ -z "$size" ]] && size=10

  mkdir -p "$DUNST_DROPIN_DIR"

  cat >"$DUNST_FONTS_FILE" <<EOF
# Font configuration - managed by font tool
[global]
font = ${font} ${size}
EOF

  # D-Bus starts it again at the next notification, through dunst.service, so
  # it lands outside the apply's cgroup with no help from here.
  killall dunst 2>/dev/null || true
}

# Apply font to all Arch apps
arch_apply_font() {
  local font="$1"
  local applied=()

  if [[ -d "$HOME/.config/waybar" ]]; then
    waybar_set_font "$font" && applied+=("waybar")
  fi

  if [[ -d "$HOME/.config/hypr" ]]; then
    hyprlock_set_font "$font" && applied+=("hyprlock")
  fi

  if [[ -d "$HOME/.config/dunst" ]]; then
    dunst_set_font "$font" && applied+=("dunst")
  fi

  if [[ ${#applied[@]} -gt 0 ]]; then
    echo "${applied[*]}"
    return 0
  fi
  return 1
}
