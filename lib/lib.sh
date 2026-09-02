#!/usr/bin/env bash
# Font sync library - modular, testable functions
# Each function has a single responsibility and can be tested independently

set -euo pipefail

# terminal.sh sources this for font_trim, and bin/font sources both, so the guard
# stops the assignments below running twice.
[[ -n "${_FONT_LIB_SOURCED:-}" ]] && return 0
_FONT_LIB_SOURCED=1

# Directories and files
FONT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FONT_APP_DIR="$(cd "$FONT_LIB_DIR/.." && pwd)"
CODE_FONTS_DIR="${CODE_FONTS_DIR:-$HOME/Documents/code_fonts}"

# Strip leading and trailing whitespace from a value read out of a config file.
#
# Never `| xargs` for this. With no command xargs runs `echo`, so a value
# starting with a dash is read as echo's own flags: a ghostty font-family of
# "--help" comes back as "Usage: echo [SHORT-OPTION]... [STRING]...", and that
# string was written into history as a font name. xargs also strips quotes and
# backslashes and fails outright on an unmatched quote, so a font file path
# containing one takes the lookup down.
font_trim() {
  local value="$*"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s' "${value%"${value##*[![:space:]]}"}"
}

# ==============================================================================
# CORE FUNCTIONS - Each can be tested independently
# ==============================================================================

# An exported value wins, which is how a test points font discovery at a fixture
# registry rather than at the curated one. Nothing in the tool sets it.
FONT_REGISTRY_FILE="${FONT_REGISTRY_FILE:-$FONT_APP_DIR/data/font-registry.json}"

# List managed fonts from the registry
# Returns: One font family name per line (only managed: true entries)
list_fonts() {
  jq -r 'to_entries[] | select(.value.managed == true) | .key' "$FONT_REGISTRY_FILE" | sort
}

# One side of the rejection line, read out of the registry. $1 is "rejected" for
# the fonts whose last reject/unreject is a reject, "active" for the rest.
#
# Both halves come from the registry, so `font list --status active` and
# `--status rejected` partition `--status all`. A rejection filed against a font
# outside the registry falls in neither half, because `font list` lists curated
# families and that font is not one.
_list_fonts_by_rejection() {
  local want="$1"

  local rejected
  rejected=$(get_rejected_font_ids)

  declare -A rejected_map
  local font
  while IFS= read -r font; do
    [[ -n "$font" ]] && rejected_map["$font"]=1
  done <<<"$rejected"

  local state
  while IFS= read -r font; do
    state="active"
    [[ -n "${rejected_map[$font]:-}" ]] && state="rejected"
    if [[ "$state" == "$want" ]]; then
      echo "$font"
    fi
  done < <(list_fonts)
}

# The set `font random` draws from. `font reject` promises a font is out of
# rotation, and rejection lives in the history rather than in the registry, so a
# listing taken from the registry alone still offers every rejected font.
list_fonts_active() {
  _list_fonts_by_rejection active
}

# The complement, and what `font list --status rejected` prints.
list_fonts_rejected() {
  _list_fonts_by_rejection rejected
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
    font_file=$(font_trim "$(fc-list : family file style | grep -F -- "$medium_family" | grep -iE "style=(Medium|Semibold)" | head -1 | cut -d: -f1)")
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Nimbus Mono PS - use Bold for better visibility (only has Regular and Bold)
  if [[ "$font_name" == "Nimbus Mono PS" ]]; then
    font_file=$(font_trim "$(fc-list : family file style | grep -F -- "$font_name" | grep -iE "style=Bold$" | head -1 | cut -d: -f1)")
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Try to get Regular style first (must be primary style, not secondary in TTC)
  # Handles numeric weight prefixes like "400 Regular" or plain "Regular"
  font_file=$(font_trim "$(fc-list : family file style | grep -F -- "$font_name" | grep -iE "style=([0-9]+ )?(Regular|Normal|Book|Roman)(,|$)" | head -1 | cut -d: -f1)")

  # If no Regular variant, fall back to any variant (but skip Bold/Italic if possible)
  if [[ -z "$font_file" ]]; then
    font_file=$(font_trim "$(fc-list : family file style | grep -F -- "$font_name" | grep -viE "style=(Bold|Italic|Light|Thin|Black|Heavy|Oblique|Slant)" | head -1 | cut -d: -f1)")
  fi

  # If still nothing, just take whatever is available
  if [[ -z "$font_file" ]]; then
    font_file=$(font_trim "$(fc-list : family file | grep -F -- "$font_name" | head -1 | cut -d: -f1)")
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

  local style
  style=$(fc-list : family file style | grep -F -- "$font_name" | grep -iE "style=(Regular|Normal|Book|Medium|Roman)" | head -1 | cut -d: -f3 | sed 's/style=//')
  font_trim "$style" || echo "Unknown"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Count available fonts
count_fonts() {
  list_fonts | wc -l | xargs
}

# Reads "<name>\t<weight>" lines on stdin and prints one name, chosen with
# probability proportional to its weight. Returns 1 on empty input.
#
# One awk over the whole list, seeded from $RANDOM. awk's bare srand() takes the
# clock in whole seconds, so two picks inside the same second return the same
# name — which a rotation driven by a keybinding hits routinely.
weighted_random_choice() {
  awk -F'\t' -v seed="${RANDOM}$$" '
    {
      name[NR] = $1
      weight[NR] = $2 + 0
      total += weight[NR]
    }
    END {
      if (NR == 0 || total <= 0) exit 1
      srand(seed)
      target = rand() * total
      for (i = 1; i <= NR; i++) {
        cumulative += weight[i]
        if (target <= cumulative) {
          print name[i]
          exit 0
        }
      }
      print name[NR]
    }
  '
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

# Format an elapsed number of seconds as a coarse "ago" string for recency.
format_relative() {
  local seconds="$1"

  if [[ "$seconds" -lt 3600 ]]; then
    echo "just now"
  elif [[ "$seconds" -lt 86400 ]]; then
    echo "$((seconds / 3600))h ago"
  else
    echo "$((seconds / 86400))d ago"
  fi
}

# YYYY-MM for the month N months before the current one. Anchored to the first
# of the month so day-of-month overflow can't skip a month. Handles both BSD
# (macOS) and GNU date.
_month_key_offset() {
  local n="$1"

  if date -v1d +%Y-%m >/dev/null 2>&1; then
    date -v1d -v-"${n}"m +%Y-%m
  else
    date -d "$(date +%Y-%m-01) -${n} month" +%Y-%m
  fi
}

# Render a trailing-12-month usage sparkline from a {YYYY-MM: seconds} map.
# Prints nothing when the map has no usage. $2 is an optional line prefix.
_render_sparkline() {
  local map="$1"
  local prefix="${2:-usage }"
  local months=12

  local -a values=()
  local i m val
  for ((i = months - 1; i >= 0; i--)); do
    m=$(_month_key_offset "$i")
    val=$(echo "$map" | jq -r --arg m "$m" '.[$m] // 0')
    values+=("$val")
  done

  local max=0 total=0 v
  for v in "${values[@]}"; do
    [[ "$v" -gt "$max" ]] && max=$v
    total=$((total + v))
  done
  [[ "$total" -le 0 ]] && return 0

  local ramp=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  local spark=""
  for v in "${values[@]}"; do
    if [[ "$v" -le 0 ]]; then
      spark+="▁"
    else
      local idx=$((v * 7 / max))
      spark+="${ramp[$idx]}"
    fi
  done
  printf "%s%s (12mo)\n" "$prefix" "$spark"
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

  # Usage detail: seconds, sessions, average session, recency.
  local usage_seconds sessions avg_seconds seconds_since
  usage_seconds=0
  sessions=0
  avg_seconds=0
  seconds_since=""
  if type -t get_font_usage_stats &>/dev/null; then
    local usage_stats
    usage_stats=$(get_font_usage_stats "$font" 2>/dev/null)
    if [[ -n "$usage_stats" ]]; then
      usage_seconds=$(echo "$usage_stats" | jq -r '.usage_seconds // 0')
      sessions=$(echo "$usage_stats" | jq -r '.sessions // 0')
      avg_seconds=$(echo "$usage_stats" | jq -r '.avg_seconds // 0')
      seconds_since=$(echo "$usage_stats" | jq -r '.seconds_since // empty')
    fi
  fi

  local usage_time="not used"
  [[ "$usage_seconds" -gt 0 ]] && usage_time=$(format_duration "$usage_seconds")
  local recency=""
  [[ -n "$seconds_since" ]] && recency=$(format_relative "$seconds_since")

  # Rank positions among registry-managed fonts (likes list and hours list).
  local likes_pos="" hours_pos="" rank_total=""
  if type -t get_font_rank_positions &>/dev/null; then
    local positions
    positions=$(get_font_rank_positions "$font" 2>/dev/null)
    if [[ -n "$positions" ]]; then
      likes_pos=$(echo "$positions" | jq -r '.likes_pos // empty')
      hours_pos=$(echo "$positions" | jq -r '.hours_pos // empty')
      rank_total=$(echo "$positions" | jq -r '.total // empty')
    fi
  fi

  # Most-used context (machine / terminal / size).
  local ctx_machine="" ctx_terminal="" ctx_size=""
  if type -t get_font_context_mode &>/dev/null; then
    local ctx_mode
    ctx_mode=$(get_font_context_mode "$font" 2>/dev/null)
    if [[ -n "$ctx_mode" ]]; then
      ctx_machine=$(echo "$ctx_mode" | jq -r '.machine // empty')
      ctx_terminal=$(echo "$ctx_mode" | jq -r '.terminal // empty')
      ctx_size=$(echo "$ctx_mode" | jq -r '.size // empty')
    fi
  fi

  # Trailing-12-month usage map for the sparkline.
  local monthly_map="{}"
  if type -t get_font_monthly_usage_map &>/dev/null; then
    monthly_map=$(get_font_monthly_usage_map "$font" 2>/dev/null)
    [[ -z "$monthly_map" ]] && monthly_map="{}"
  fi

  echo ""
  if [[ "$format" == "full" ]]; then
    echo "Stats:"
    printf "  Score: %+d (%d likes, %d dislikes)\n" "$score" "$likes" "$dislikes"
    printf "  Usage time: %s\n" "$usage_time"
    if [[ "$sessions" -gt 0 ]]; then
      printf "  Sessions: %d (avg %s)\n" "$sessions" "$(format_duration "$avg_seconds")"
    fi
    [[ -n "$recency" ]] && printf "  Last used: %s\n" "$recency"
    _render_rank_line "  Rank: " "$likes_pos" "$hours_pos" "$rank_total"
    _render_sparkline "$monthly_map" "  Usage trend: "
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
    printf "%+d · %d↑ %d↓" "$score" "$likes" "$dislikes"
    [[ "$usage_seconds" -gt 0 ]] && printf " · %s used" "$usage_time"
    echo ""

    printf "%d× applied" "$applies"
    [[ "$sessions" -gt 0 ]] && printf " · %d sessions · avg %s" "$sessions" "$(format_duration "$avg_seconds")"
    [[ -n "$recency" ]] && printf " · %s" "$recency"
    echo ""

    _render_rank_line "rank: " "$likes_pos" "$hours_pos" "$rank_total"
    _render_context_line "$ctx_machine" "$ctx_terminal" "$ctx_size"
    _render_sparkline "$monthly_map"
  fi
}

# Print a rank line like "<prefix>likes #2 · hours #5 of 11", only if at least
# one position is known. $prefix is the complete label (e.g. "rank: ", "  Rank: ").
_render_rank_line() {
  local prefix="$1" likes_pos="$2" hours_pos="$3" total="$4"
  [[ -z "$likes_pos" && -z "$hours_pos" ]] && return 0

  local line=""
  [[ -n "$likes_pos" ]] && line="likes #${likes_pos}"
  if [[ -n "$hours_pos" ]]; then
    [[ -n "$line" ]] && line="$line · "
    line="${line}hours #${hours_pos}"
  fi
  [[ -n "$total" ]] && line="$line of $total"
  printf "%s%s\n" "$prefix" "$line"
}

# Print a "mostly <machine> / <terminal> @ <size>px" context line, only if at
# least one field is known.
_render_context_line() {
  local machine="$1" terminal="$2" size="$3"
  [[ -z "$machine" && -z "$terminal" && -z "$size" ]] && return 0

  local ctx=""
  if [[ -n "$machine" && -n "$terminal" ]]; then
    ctx="$machine / $terminal"
  else
    ctx="${machine}${terminal}"
  fi
  [[ -n "$size" ]] && ctx="$ctx @ ${size}px"
  printf "mostly %s\n" "$ctx"
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
