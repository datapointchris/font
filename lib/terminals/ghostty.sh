#!/usr/bin/env bash
# Ghostty terminal backend
# Config format: key = value

GHOSTTY_CONFIG_DIR="$HOME/.config/ghostty/fonts"
GHOSTTY_CONFIG_FILE="$GHOSTTY_CONFIG_DIR/current.conf"

ghostty_config_path() {
  echo "$GHOSTTY_CONFIG_FILE"
}

ghostty_get_font() {
  if [[ -f "$GHOSTTY_CONFIG_FILE" ]]; then
    grep "^font-family" "$GHOSTTY_CONFIG_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | xargs
  else
    echo ""
  fi
}

ghostty_get_size() {
  if [[ -f "$GHOSTTY_CONFIG_FILE" ]]; then
    grep "^font-size" "$GHOSTTY_CONFIG_FILE" 2>/dev/null | cut -d= -f2 | xargs
  else
    echo ""
  fi
}

ghostty_set_font() {
  local font="$1"
  local size
  size=$(ghostty_get_size)
  [[ -z "$size" ]] && size=17

  mkdir -p "$GHOSTTY_CONFIG_DIR"

  cat > "$GHOSTTY_CONFIG_FILE" << EOF
font-family = "${font}"
font-size = ${size}
EOF
}

ghostty_set_size() {
  local size="$1"
  local font
  font=$(ghostty_get_font)
  [[ -z "$font" ]] && font="monospace"

  mkdir -p "$GHOSTTY_CONFIG_DIR"

  cat > "$GHOSTTY_CONFIG_FILE" << EOF
font-family = "${font}"
font-size = ${size}
EOF
}

ghostty_apply() {
  local font="$1"
  ghostty_set_font "$font"
}
