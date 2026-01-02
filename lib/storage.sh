#!/usr/bin/env bash
# Font storage layer - JSONL-based tracking
# Per-platform history files to avoid git merge conflicts

# Data directory - stored in ~/.config/font (symlinked to dotfiles for git tracking)
FONT_DATA_DIR="$HOME/.config/font"

#==============================================================================
# PLATFORM DETECTION
#==============================================================================

detect_platform() {
  # Check for PLATFORM env var first (set by dotfiles)
  if [[ -n "${PLATFORM:-}" ]]; then
    echo "$PLATFORM"
    return
  fi

  # Detect platform
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    echo "wsl"
  elif [[ -f /etc/arch-release ]]; then
    echo "arch"
  elif [[ -f /etc/os-release ]]; then
    # Generic Linux fallback
    . /etc/os-release
    echo "${ID:-linux}"
  else
    echo "unknown"
  fi
}

#==============================================================================
# CORE STORAGE OPERATIONS
#==============================================================================

log_action() {
  local action="$1"
  local font="${2:-}"
  local message="${3:-}"

  if [[ -z "$action" ]]; then
    echo "Error: action required" >&2
    return 1
  fi

  local platform
  platform=$(detect_platform)
  local timestamp
  # Store timestamps in UTC to avoid timezone conversion issues
  timestamp=$(date -u -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

  # Per-platform history file - eliminates merge conflicts
  local history_file="$FONT_DATA_DIR/history-${platform}.jsonl"
  mkdir -p "$FONT_DATA_DIR"

  # Build JSON record (compact format for JSONL)
  local record
  if [[ -n "$message" ]]; then
    record=$(jq -nc \
      --arg ts "$timestamp" \
      --arg plat "$platform" \
      --arg font "$font" \
      --arg act "$action" \
      --arg msg "$message" \
      '{ts:$ts, platform:$plat, font:$font, action:$act, message:$msg}')
  else
    record=$(jq -nc \
      --arg ts "$timestamp" \
      --arg plat "$platform" \
      --arg font "$font" \
      --arg act "$action" \
      '{ts:$ts, platform:$plat, font:$font, action:$act}')
  fi

  echo "$record" >> "$history_file"
}

get_history() {
  # Combine all platform history files
  # Returns sorted JSON array
  if compgen -G "$FONT_DATA_DIR/history-*.jsonl" > /dev/null; then
    cat "$FONT_DATA_DIR"/history-*.jsonl 2>/dev/null | jq -s 'sort_by(.ts)'
  else
    echo "[]"
  fi
}

get_history_raw() {
  # Return raw JSONL (one object per line) for streaming
  if compgen -G "$FONT_DATA_DIR/history-*.jsonl" > /dev/null; then
    cat "$FONT_DATA_DIR"/history-*.jsonl 2>/dev/null | jq -c '.' | sort
  fi
}

#==============================================================================
# QUERY FUNCTIONS
#==============================================================================

get_font_stats() {
  local font="$1"

  if [[ -z "$font" ]]; then
    echo "Error: font name required" >&2
    return 1
  fi

  get_history | jq --arg font "$font" '
    map(select(.font == $font)) |
    {
      font: $font,
      total_actions: length,
      likes: map(select(.action == "like")) | length,
      dislikes: map(select(.action == "dislike")) | length,
      notes: map(select(.action == "note")) | length,
      applies: map(select(.action == "apply")) | length,
      score: (map(select(.action == "like")) | length) - (map(select(.action == "dislike")) | length),
      last_used: map(select(.action == "apply")) | max_by(.ts) | .ts // "never",
      platforms: [.[].platform] | unique
    }
  '
}

calculate_usage_time() {
  # Calculate total usage time for each font in seconds
  # Usage = time between apply and next apply (or now if currently active)
  local current_font="$1"

  get_history | jq -r --arg current "$current_font" '
    # Helper to parse ISO 8601 timestamps (handles both UTC and timezone offsets)
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        # Old format with timezone - strip and treat as UTC (legacy handling)
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        # New format in UTC
        fromdateiso8601
      end;

    # Get all apply actions sorted by timestamp (across all fonts)
    [map(select(.action == "apply")) | sort_by(.ts) | to_entries[]] as $applies |

    # For each apply, calculate duration until next apply
    ($applies | map(
      . as $entry |
      $entry.key as $idx |
      $entry.value as $apply |

      # Find next apply (any font)
      if ($idx < (($applies | length) - 1)) then
        # Duration = next apply time - current apply time
        {
          font: $apply.font,
          duration: (($applies[$idx + 1].value.ts | parse_ts) - ($apply.ts | parse_ts))
        }
      elif $apply.font == $current then
        # Last apply and it matches current font - add time until now
        {
          font: $apply.font,
          duration: ((now | floor) - ($apply.ts | parse_ts))
        }
      else
        # Last apply but not current font
        null
      end
    ) | map(select(. != null))) as $durations |

    # Group by font and sum durations
    ($durations | group_by(.font) | map({
      key: .[0].font,
      value: (map(.duration) | add // 0)
    }) | from_entries)
  '
}

get_rankings() {
  # Aggregate and rank all fonts by likes/dislikes
  # Returns JSONL (compact JSON, one object per line)
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  local usage_times
  usage_times=$(calculate_usage_time "$current_font")

  get_history | jq -c --argjson usage "$usage_times" '
    group_by(.font) |
    map({
      font: .[0].font,
      likes: map(select(.action == "like")) | length,
      dislikes: map(select(.action == "dislike")) | length,
      score: (map(select(.action == "like")) | length) - (map(select(.action == "dislike")) | length),
      last_used: (map(select(.action == "apply")) | max_by(.ts) | .ts // "never"),
      platforms: [.[].platform] | unique | join(","),
      usage_seconds: ($usage[.[0].font] // 0),
      # Add sort_key for proper ordering (never gets lowest timestamp)
      sort_key: (if (map(select(.action == "apply")) | length) > 0 then (map(select(.action == "apply")) | max_by(.ts) | .ts) else "0" end)
    }) |
    # Sort by score descending (negate for desc), then by sort_key descending
    sort_by(.score, .sort_key) | reverse |
    .[]
  '
}

#==============================================================================
# FILTER FUNCTIONS
#==============================================================================

filter_by_font() {
  local font="$1"
  get_history | jq --arg font "$font" 'map(select(.font == $font))'
}

filter_by_action() {
  local action="$1"
  get_history | jq --arg action "$action" 'map(select(.action == $action))'
}

filter_by_platform() {
  local platform="$1"
  get_history | jq --arg platform "$platform" 'map(select(.platform == $platform))'
}

filter_by_date_range() {
  local start="$1"
  local end="$2"
  get_history | jq --arg start "$start" --arg end "$end" '
    map(select(.ts >= $start and .ts <= $end))
  '
}

#==============================================================================
# ANALYSIS FUNCTIONS
#==============================================================================

get_most_liked_fonts() {
  local limit="${1:-10}"

  get_history | jq --arg limit "$limit" '
    group_by(.font) |
    map({
      font: .[0].font,
      likes: map(select(.action == "like")) | length
    }) |
    sort_by(-.likes) |
    limit($limit | tonumber; .[])
  '
}

get_recently_used() {
  local limit="${1:-10}"

  get_history | jq --arg limit "$limit" '
    map(select(.action == "apply")) |
    sort_by(-.ts) |
    unique_by(.font) |
    limit($limit | tonumber; .[])
  '
}

get_font_notes() {
  local font="$1"

  get_history | jq --arg font "$font" '
    map(select(.font == $font and .action == "note")) |
    sort_by(.ts) |
    .[]
  '
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

count_total_actions() {
  get_history | jq 'length'
}

count_fonts_tracked() {
  get_history | jq 'group_by(.font) | length'
}

list_tracked_fonts() {
  get_history | jq -r 'group_by(.font) | .[].font' | sort -u
}

#==============================================================================
# VALIDATION
#==============================================================================

validate_history_files() {
  local valid=true

  for file in "$FONT_DATA_DIR"/history-*.jsonl; do
    [[ -f "$file" ]] || continue

    if ! jq -e '.' "$file" >/dev/null 2>&1; then
      echo "Invalid JSON in: $file" >&2
      valid=false
    fi
  done

  $valid
}

#==============================================================================
# REJECTED FONTS TRACKING
#==============================================================================

# Get per-machine rejected fonts file path
get_rejected_fonts_file() {
  local platform
  platform=$(detect_platform)
  echo "$FONT_DATA_DIR/rejected-fonts-${platform}.json"
}

# Mark a font as rejected with reason
reject_font() {
  local font="$1"
  local reason="${2:-No reason provided}"

  if [[ -z "$font" ]]; then
    echo "Error: font name required" >&2
    return 1
  fi

  local rejected_file
  rejected_file=$(get_rejected_fonts_file)

  local platform
  platform=$(detect_platform)
  local timestamp
  # Store timestamps in UTC to avoid timezone conversion issues
  timestamp=$(date -u -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

  # Initialize rejected fonts file if it doesn't exist
  if [[ ! -f "$rejected_file" ]]; then
    echo "{}" > "$rejected_file"
  fi

  # Add or update rejected font entry
  local temp_file="${rejected_file}.tmp"
  jq --arg font "$font" \
     --arg reason "$reason" \
     --arg platform "$platform" \
     --arg ts "$timestamp" \
     '.[$font] = {
       "rejected_date": $ts,
       "reason": $reason,
       "platforms": ((.[$font].platforms // []) + [$platform] | unique)
     }' "$rejected_file" > "$temp_file"

  mv "$temp_file" "$rejected_file"
}

# Check if a font is rejected
is_font_rejected() {
  local font="$1"
  local rejected_file
  rejected_file=$(get_rejected_fonts_file)

  if [[ ! -f "$rejected_file" ]]; then
    return 1
  fi

  jq -e --arg font "$font" '.[$font] != null' "$rejected_file" >/dev/null 2>&1
}

# Get rejected font info
get_rejected_font_info() {
  local font="$1"
  local rejected_file
  rejected_file=$(get_rejected_fonts_file)

  if [[ ! -f "$rejected_file" ]]; then
    echo "{}"
    return
  fi

  jq --arg font "$font" '.[$font] // {}' "$rejected_file"
}

# List all rejected fonts
list_rejected_fonts() {
  local rejected_file
  rejected_file=$(get_rejected_fonts_file)

  if [[ ! -f "$rejected_file" ]]; then
    echo "[]"
    return
  fi

  jq -c 'to_entries | map({font: .key, rejected_date: .value.rejected_date, reason: .value.reason, platforms: .value.platforms | join(",")}) | sort_by(.rejected_date) | reverse | .[]' "$rejected_file"
}

# Remove font from rejected list
unreject_font() {
  local font="$1"

  if [[ -z "$font" ]]; then
    echo "Error: font name required" >&2
    return 1
  fi

  local rejected_file
  rejected_file=$(get_rejected_fonts_file)

  if [[ ! -f "$rejected_file" ]]; then
    return 0
  fi

  local temp_file="${rejected_file}.tmp"
  jq --arg font "$font" 'del(.[$font])' "$rejected_file" > "$temp_file"
  mv "$temp_file" "$rejected_file"
}

#==============================================================================
# INITIALIZATION
#==============================================================================

init_storage() {
  # Ensure data directory exists
  if [[ ! -d "$FONT_DATA_DIR" ]]; then
    mkdir -p "$FONT_DATA_DIR"
  fi

  # Ensure platform-specific history file exists
  local platform
  platform=$(detect_platform)
  local history_file="$FONT_DATA_DIR/history-${platform}.jsonl"

  if [[ ! -f "$history_file" ]]; then
    touch "$history_file"
  fi

  # Ensure rejected fonts file exists
  local rejected_file
  rejected_file=$(get_rejected_fonts_file)
  if [[ ! -f "$rejected_file" ]]; then
    echo "{}" > "$rejected_file"
  fi
}

# Auto-initialize on source
# This ensures the data directory and current platform's history file exist
# Making the tool robust against deleted log files
init_storage
