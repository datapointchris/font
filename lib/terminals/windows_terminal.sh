#!/usr/bin/env bash
# Windows Terminal backend (for WSL)
# Config format: JSON (settings.json)

_windows_terminal_find_settings() {
  local windows_user
  windows_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')

  if [[ -z "$windows_user" ]]; then
    return 1
  fi

  local paths=(
    "/mnt/c/Users/$windows_user/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
    "/mnt/c/Users/$windows_user/AppData/Local/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
    "/mnt/c/Users/$windows_user/AppData/Local/Microsoft/Windows Terminal/settings.json"
  )

  for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

windows_terminal_config_path() {
  _windows_terminal_find_settings
}

windows_terminal_get_font() {
  local settings
  settings=$(_windows_terminal_find_settings) || return 1

  jq -r '.profiles.defaults.font.face // empty' "$settings" 2>/dev/null
}

windows_terminal_get_size() {
  local settings
  settings=$(_windows_terminal_find_settings) || return 1

  local size
  size=$(jq -r '.profiles.defaults.font.size // empty' "$settings" 2>/dev/null)

  # Windows Terminal defaults to size 12 when not explicitly set
  echo "${size:-12}"
}

windows_terminal_set_font() {
  local font="$1"
  local settings
  settings=$(_windows_terminal_find_settings) || return 1

  local size
  size=$(windows_terminal_get_size)

  cp "$settings" "${settings}.backup"

  # Update profiles.defaults AND all profile-specific font settings (always include size)
  jq --arg font "$font" --argjson size "$size" '
    .profiles.defaults.font = (.profiles.defaults.font // {}) + {face: $font, size: $size} |
    .profiles.list = [.profiles.list[] |
      if .font != null then .font.face = $font
      else . + {font: {face: $font, size: $size}}
      end
    ]
  ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
}

windows_terminal_set_size() {
  local size="$1"
  local settings
  settings=$(_windows_terminal_find_settings) || return 1

  cp "$settings" "${settings}.backup"

  # Update profiles.defaults AND all profile-specific font settings
  jq --argjson size "$size" '
    .profiles.defaults.font.size = $size |
    .profiles.list = [.profiles.list[] |
      if .font != null then .font.size = $size
      else . + {font: {size: $size}}
      end
    ]
  ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
}

windows_terminal_apply() {
  local font="$1"
  windows_terminal_set_font "$font"
}
