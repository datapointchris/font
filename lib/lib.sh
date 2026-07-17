#!/usr/bin/env bash
# Font sync library - modular, testable functions
# Each function has a single responsibility and can be tested independently

set -euo pipefail

# Directories and files
FONT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FONT_APP_DIR="$(cd "$FONT_LIB_DIR/.." && pwd)"
CODE_FONTS_DIR="${CODE_FONTS_DIR:-$HOME/Documents/code_fonts}"

# ==============================================================================
# CORE FUNCTIONS - Each can be tested independently
# ==============================================================================

FONT_REGISTRY_FILE="$FONT_APP_DIR/data/font-registry.json"

# List managed fonts from the registry
# Returns: One font family name per line (only managed: true entries)
list_fonts() {
  jq -r 'to_entries[] | select(.value.managed == true) | .key' "$FONT_REGISTRY_FILE" | sort
}

# Get the file path for a font by family name
# Args: $1 - font family name
# Returns: Absolute path to font file (prefers Regular/Normal style)
# Exit: 0 if found, 1 if not found
get_font_file_path() {
  local font_name="$1"
  local font_file

  # Use fc-list to find the font file, preferring Regular/Normal styles
  # Format: /path/to/font.ttf: Family Name:style=Style Name

  # Special handling for fonts that render too dim with Regular weight
  # Iosevka Slab - use Medium weight for better visibility (TTC files have family name "Iosevka Slab Medium")
  if [[ "$font_name" =~ "Iosevka".*"Slab" ]]; then
    local medium_family="${font_name} Medium"
    font_file=$(fc-list : family file style | grep -F "$medium_family" | grep -iE "style=(Medium|Semibold)" | head -1 | cut -d: -f1 | xargs)
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Nimbus Mono PS - use Bold for better visibility (only has Regular and Bold)
  if [[ "$font_name" == "Nimbus Mono PS" ]]; then
    font_file=$(fc-list : family file style | grep -F "$font_name" | grep -iE "style=Bold$" | head -1 | cut -d: -f1 | xargs)
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Try to get Regular style first (must be primary style, not secondary in TTC)
  # Handles numeric weight prefixes like "400 Regular" or plain "Regular"
  font_file=$(fc-list : family file style | grep -F "$font_name" | grep -iE "style=([0-9]+ )?(Regular|Normal|Book|Roman)(,|$)" | head -1 | cut -d: -f1 | xargs)

  # If no Regular variant, fall back to any variant (but skip Bold/Italic if possible)
  if [[ -z "$font_file" ]]; then
    font_file=$(fc-list : family file style | grep -F "$font_name" | grep -viE "style=(Bold|Italic|Light|Thin|Black|Heavy|Oblique|Slant)" | head -1 | cut -d: -f1 | xargs)
  fi

  # If still nothing, just take whatever is available
  if [[ -z "$font_file" ]]; then
    font_file=$(fc-list : family file | grep -F "$font_name" | head -1 | cut -d: -f1 | xargs)
  fi

  if [[ -z "$font_file" ]] || [[ ! -f "$font_file" ]]; then
    return 1
  fi

  echo "$font_file"
  return 0
}

# Get font style information for a font family
# Args: $1 - font family name
# Returns: Style name (e.g., "Regular", "Bold", etc.)
get_font_style() {
  local font_name="$1"

  fc-list : family file style | grep -F "$font_name" | grep -iE "style=(Regular|Normal|Book|Medium|Roman)" | head -1 | cut -d: -f3 | sed 's/style=//' | xargs || echo "Unknown"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Count available fonts
count_fonts() {
  list_fonts | wc -l | xargs
}

# Format a duration in seconds as a compact human string (e.g. "2h 15m", "3d").
# Lives here (not bin/font) so fzf preview subshells, which source only the
# libs, can render usage times too.
format_duration() {
  local seconds="$1"

  if [[ "$seconds" -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ "$seconds" -lt 3600 ]]; then
    echo "$((seconds / 60))m"
  elif [[ "$seconds" -lt 86400 ]]; then
    local hours=$((seconds / 3600))
    local mins=$(((seconds % 3600) / 60))
    if [[ "$mins" -gt 0 ]]; then
      echo "${hours}h ${mins}m"
    else
      echo "${hours}h"
    fi
  else
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    if [[ "$hours" -gt 0 ]]; then
      echo "${days}d ${hours}h"
    else
      echo "${days}d"
    fi
  fi
}

# Total seconds a font was active. calculate_usage_time returns a per-font map
# for the whole history; we pass the *actual* current font so only the truly
# active font accrues live (now - last apply) time, then read this font's value.
_font_usage_seconds() {
  local font="$1"

  if ! type -t calculate_usage_time &>/dev/null; then
    echo 0
    return
  fi

  local current
  current=$(get_current_font 2>/dev/null || echo "")
  calculate_usage_time "$current" 2>/dev/null | jq -r --arg f "$font" '.[$f] // 0'
}

# ==============================================================================
# FONT INFO DISPLAY
# ==============================================================================

# Get font information from registry
# Args: $1 - font name
# Returns: JSON object with font info
get_font_info() {
  local font="$1"
  jq -r --arg font "$font" '.[$font] // {}' "$FONT_REGISTRY_FILE"
}

# Render the "About" block (registry metadata). Shown first: it's the identity
# of the font, independent of usage.
_render_font_about() {
  local font="$1" format="$2"

  local font_info
  font_info=$(get_font_info "$font")
  [[ -z "$font_info" || "$font_info" == "{}" ]] && return 0

  local description known_for creator year url
  description=$(echo "$font_info" | jq -r '.description // empty')
  known_for=$(echo "$font_info" | jq -r '.known_for // empty')
  creator=$(echo "$font_info" | jq -r '.creator // empty')
  year=$(echo "$font_info" | jq -r '.year // empty')
  url=$(echo "$font_info" | jq -r '.url // empty')

  [[ -z "$description" ]] && return 0

  if [[ "$format" == "full" ]]; then
    echo "$description"
    [[ -n "$known_for" ]] && echo "  Known for: $known_for"
    [[ -n "$creator" ]] && echo "  Creator: $creator"
    [[ -n "$year" ]] && echo "  Year: $year"
    [[ -n "$url" ]] && echo "  URL: $url"
  else
    echo "$description"
    [[ -n "$known_for" ]] && echo "Known for: $known_for"
    [[ -n "$creator" ]] && echo "Creator: $creator ($year)"
  fi
}

# Render this font's action history, oldest to newest.
# Args: $1 font, $2 limit (0 = all; N = most recent N entries).
_render_font_history() {
  local font="$1" limit="$2"

  type -t get_history &>/dev/null || return 0

  local total
  total=$(get_history | jq --arg font "$font" '[.[] | select(.font == $font)] | length')
  [[ "$total" -eq 0 ]] && return 0

  local label="History"
  if [[ "$limit" -gt 0 && "$total" -gt "$limit" ]]; then
    label="Recent (last $limit of $total)"
  fi

  echo ""
  echo "$label"
  get_history | jq -r --arg font "$font" --argjson limit "$limit" '
    ( map(select(.font == $font)) | sort_by(.ts) ) as $all |
    ( if $limit > 0 then $all[-$limit:] else $all end ) |
    .[] |
    .action as $act |
    .ts[0:10] as $date |
    .message as $msg |
    if $act == "apply" then "  \($date)  applied"
    elif $act == "like" then (if $msg then "  \($date)  liked: \($msg)" else "  \($date)  liked" end)
    elif $act == "dislike" then (if $msg then "  \($date)  disliked: \($msg)" else "  \($date)  disliked" end)
    elif $act == "note" then "  \($date)  note: \($msg)"
    elif $act == "reject" then "  \($date)  rejected: \($msg)"
    elif $act == "unreject" then "  \($date)  unrejected"
    else "  \($date)  \($act)"
    end
  ' 2>/dev/null
}

# Render the stats footer. Shown last: the numbers read better as a summary
# after the description and history have set context.
_render_font_stat_footer() {
  local font="$1" format="$2"

  type -t get_font_stats &>/dev/null || return 0

  local stats
  stats=$(get_font_stats "$font" 2>/dev/null)
  [[ -z "$stats" || "$stats" == "null" ]] && return 0

  local score likes dislikes notes applies platforms
  score=$(echo "$stats" | jq -r '.score // 0')
  likes=$(echo "$stats" | jq -r '.likes // 0')
  dislikes=$(echo "$stats" | jq -r '.dislikes // 0')
  notes=$(echo "$stats" | jq -r '.notes // 0')
  applies=$(echo "$stats" | jq -r '.applies // 0')
  platforms=$(echo "$stats" | jq -r '.platforms | join(", ") // "none"')

  local usage_seconds usage_time
  usage_seconds=$(_font_usage_seconds "$font")
  usage_time="not used"
  [[ "$usage_seconds" -gt 0 ]] && usage_time=$(format_duration "$usage_seconds")

  echo ""
  if [[ "$format" == "full" ]]; then
    echo "Stats:"
    printf "  Score: %+d (%d likes, %d dislikes)\n" "$score" "$likes" "$dislikes"
    printf "  Usage time: %s\n" "$usage_time"
    printf "  Notes: %d\n" "$notes"
    printf "  Times applied: %d\n" "$applies"
    printf "  Platforms: %s\n" "$platforms"
    local machines
    machines=$(echo "$stats" | jq -r '.machines | join(", ") // "unknown"')
    printf "  Machines: %s\n" "$machines"

    if type -t get_last_terminal_context &>/dev/null; then
      local ctx
      ctx=$(get_last_terminal_context "$font" 2>/dev/null)
      if [[ -n "$ctx" && "$ctx" != "{}" && "$ctx" != "null" ]]; then
        local terminal in_tmux cols rows resolution font_size
        terminal=$(echo "$ctx" | jq -r '.terminal // "unknown"')
        in_tmux=$(echo "$ctx" | jq -r '.in_tmux // "unknown"')
        cols=$(echo "$ctx" | jq -r '.cols // "unknown"')
        rows=$(echo "$ctx" | jq -r '.rows // "unknown"')
        resolution=$(echo "$ctx" | jq -r '.resolution // "unknown"')
        font_size=$(echo "$ctx" | jq -r '.font_size // "unknown"')

        echo ""
        echo "Last Session:"
        printf "  Terminal: %s\n" "$terminal"
        [[ "$cols" != "null" && "$cols" != "unknown" ]] && printf "  Size: %sx%s (cols x rows)\n" "$cols" "$rows"
        [[ "$font_size" != "null" && "$font_size" != "unknown" ]] && printf "  Font size: %s\n" "$font_size"
        [[ "$resolution" != "null" && "$resolution" != "unknown" ]] && printf "  Resolution: %s\n" "$resolution"
        [[ "$in_tmux" != "null" ]] && printf "  In tmux: %s\n" "$in_tmux"
      fi
    fi
  else
    printf "%+d · %d↑ %d↓ · %d× applied" "$score" "$likes" "$dislikes" "$applies"
    [[ "$usage_seconds" -gt 0 ]] && printf " · %s used" "$usage_time"
    echo ""
  fi
}

# Display font details. Order: description (About) -> history (line-capped in
# the compact picker) -> stats footer.
# Args: $1 - font name
#       $2 - format ("full" for 'font current'/'font info', "compact" for the change picker)
display_font_details() {
  local font="$1"
  local format="${2:-full}"

  # Source storage.sh if needed (when invoked from the fzf preview subshell)
  if ! type -t get_font_stats &>/dev/null; then
    source "$FONT_APP_DIR/lib/storage.sh" 2>/dev/null || true
  fi

  local history_limit=0
  if [[ "$format" == "full" ]]; then
    echo ""
    echo "$font"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  else
    echo "━━━ $font ━━━"
    history_limit=6
  fi

  _render_font_about "$font" "$format"
  _render_font_history "$font" "$history_limit"
  _render_font_stat_footer "$font" "$format"

  if [[ "$format" == "full" ]]; then
    echo ""
  else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi
}

# ==============================================================================
# PLATFORM DETECTION
# ==============================================================================

detect_platform() {
  if [[ -n "${PLATFORM:-}" ]]; then
    echo "$PLATFORM"
    return
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    echo "wsl"
  elif [[ -f /etc/arch-release ]]; then
    echo "archlinux"
  else
    echo "linux"
  fi
}

# Arch-specific font functions moved to lib/terminals/arch.sh
