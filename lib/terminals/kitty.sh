#!/usr/bin/env bash
# Kitty terminal backend
# Config format: key value (space-separated)

KITTY_CONFIG_DIR="$HOME/.config/kitty/fonts"
KITTY_CONFIG_FILE="$KITTY_CONFIG_DIR/current.conf"

kitty_config_path() {
  echo "$KITTY_CONFIG_FILE"
}

kitty_get_font() {
  if [[ -f "$KITTY_CONFIG_FILE" ]]; then
    grep "^font_family" "$KITTY_CONFIG_FILE" 2>/dev/null | sed 's/^font_family //' | xargs
  else
    echo ""
  fi
}

kitty_get_size() {
  if [[ -f "$KITTY_CONFIG_FILE" ]]; then
    local size
    size=$(grep "^font_size" "$KITTY_CONFIG_FILE" 2>/dev/null | sed 's/^font_size //' | xargs)
    # Remove decimal part if present
    echo "${size%%.*}"
  else
    echo ""
  fi
}

kitty_set_font() {
  local font="$1"
  local size
  size=$(kitty_get_size)
  [[ -z "$size" ]] && size=17

  mkdir -p "$KITTY_CONFIG_DIR"

  cat > "$KITTY_CONFIG_FILE" << EOF
font_family ${font}
font_size ${size}.0
EOF
}

kitty_set_size() {
  local size="$1"
  local font
  font=$(kitty_get_font)
  [[ -z "$font" ]] && font="monospace"

  mkdir -p "$KITTY_CONFIG_DIR"

  cat > "$KITTY_CONFIG_FILE" << EOF
font_family ${font}
font_size ${size}.0
EOF

  # Reload kitty config
  pkill -USR1 kitty 2>/dev/null || true
}

kitty_apply() {
  local font="$1"
  kitty_set_font "$font"
  # Reload kitty config
  pkill -USR1 kitty 2>/dev/null || true
}
