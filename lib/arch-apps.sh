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

waybar_get_font() {
  if [[ -f "$WAYBAR_FONTS_FILE" ]]; then
    grep 'font-family:' "$WAYBAR_FONTS_FILE" 2>/dev/null \
      | grep -o '"[^"]*"' | head -1 | tr -d '"'
  else
    echo ""
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

  # Reload waybar
  killall -SIGUSR2 waybar 2>/dev/null || true
}

hyprlock_get_font() {
  if [[ -f "$HYPRLOCK_FONTS_FILE" ]]; then
    # $font here is hyprlock's own variable syntax, written literally by
    # hyprlock_set_font — single quotes are what keeps it literal.
    # shellcheck disable=SC2016
    grep '^\$font = ' "$HYPRLOCK_FONTS_FILE" 2>/dev/null \
      | sed 's/^\$font = //' | head -1
  else
    echo ""
  fi
}

hyprlock_set_font() {
  local font="$1"

  mkdir -p "$HYPRLOCK_FONTS_DIR"

  cat >"$HYPRLOCK_FONTS_FILE" <<EOF
# Font configuration - managed by font tool
\$font = ${font}
EOF
}

dunst_get_font() {
  if [[ -f "$DUNST_FONTS_FILE" ]]; then
    grep '^font = ' "$DUNST_FONTS_FILE" 2>/dev/null \
      | sed 's/^font = //;s/ [0-9]*$//' | head -1
  else
    echo ""
  fi
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

  # Restart dunst to pick up changes
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
