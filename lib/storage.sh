#!/usr/bin/env bash
# Font storage layer - unified JSONL history with terminal context
# Single history file synced across machines via gist

set -euo pipefail

_STORAGE_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dev mode: use FONT_ENV=development (set via direnv in ~/tools/font/.envrc)
_is_dev_mode() {
  [[ "${FONT_ENV:-}" == "development" ]]
}

if _is_dev_mode; then
  FONT_STATE_DIR="$_STORAGE_APP_DIR/.dev-data"
else
  FONT_STATE_DIR="$HOME/.local/state/font"
fi
FONT_HISTORY_FILE="$FONT_STATE_DIR/history.jsonl"

_storage_get_terminal_context() {
  if type -t get_terminal_context &>/dev/null; then
    get_terminal_context
  else
    echo '{}'
  fi
}

log_action() {
  local action="$1"
  local font="${2:-}"
  local message="${3:-}"

  if [[ -z "$action" ]]; then
    echo "Error: action required" >&2
    return 1
  fi

  mkdir -p "$FONT_STATE_DIR"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local context
  context=$(_storage_get_terminal_context)

  local record
  if [[ -n "$message" ]]; then
    record=$(echo "$context" | jq -c \
      --arg ts "$timestamp" \
      --arg font "$font" \
      --arg act "$action" \
      --arg msg "$message" \
      '. + {ts: $ts, font: $font, action: $act, message: $msg}')
  else
    record=$(echo "$context" | jq -c \
      --arg ts "$timestamp" \
      --arg font "$font" \
      --arg act "$action" \
      '. + {ts: $ts, font: $font, action: $act}')
  fi

  echo "$record" >> "$FONT_HISTORY_FILE"
}

get_history() {
  if [[ -f "$FONT_HISTORY_FILE" ]]; then
    jq -s 'sort_by(.ts)' "$FONT_HISTORY_FILE"
  else
    echo "[]"
  fi
}

get_history_raw() {
  if [[ -f "$FONT_HISTORY_FILE" ]]; then
    jq -c '.' "$FONT_HISTORY_FILE" | sort
  fi
}

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
    echo "arch"
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-linux}"
  else
    echo "unknown"
  fi
}

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
      platforms: [.[].platform] | unique,
      machines: [.[].machine // "unknown"] | unique
    }
  '
}

calculate_usage_time() {
  local current_font="$1"

  get_history | jq -r --arg current "$current_font" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    [map(select(.action == "apply")) | sort_by(.ts) | to_entries[]] as $applies |

    ($applies | map(
      . as $entry |
      $entry.key as $idx |
      $entry.value as $apply |

      if ($idx < (($applies | length) - 1)) then
        {
          font: $apply.font,
          duration: (($applies[$idx + 1].value.ts | parse_ts) - ($apply.ts | parse_ts))
        }
      elif $apply.font == $current then
        {
          font: $apply.font,
          duration: ((now | floor) - ($apply.ts | parse_ts))
        }
      else
        null
      end
    ) | map(select(. != null))) as $durations |

    ($durations | group_by(.font) | map({
      key: .[0].font,
      value: (map(.duration) | add // 0)
    }) | from_entries)
  '
}

get_rankings() {
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
      sort_key: (if (map(select(.action == "apply")) | length) > 0 then (map(select(.action == "apply")) | max_by(.ts) | .ts) else "0" end)
    }) |
    sort_by(.score, .sort_key) | reverse |
    .[]
  '
}

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

get_last_terminal_context() {
  local font="$1"

  get_history | jq --arg font "$font" '
    map(select(.font == $font and .action == "apply")) |
    sort_by(.ts) | last // {}
  '
}

count_total_actions() {
  get_history | jq 'length'
}

count_fonts_tracked() {
  get_history | jq 'group_by(.font) | length'
}

list_tracked_fonts() {
  get_history | jq -r 'group_by(.font) | .[].font' | sort -u
}

get_all_apply_counts() {
  get_history | jq -r '
    map(select(.action == "apply")) |
    group_by(.font) |
    map({font: .[0].font, count: length}) |
    .[] |
    "\(.font)\t\(.count)"
  '
}

validate_history_file() {
  if [[ ! -f "$FONT_HISTORY_FILE" ]]; then
    return 0
  fi

  if ! jq -e '.' "$FONT_HISTORY_FILE" >/dev/null 2>&1; then
    echo "Invalid JSON in: $FONT_HISTORY_FILE" >&2
    return 1
  fi

  return 0
}

reject_font() {
  local font="$1"
  local reason="${2:-No reason provided}"

  if [[ -z "$font" ]]; then
    echo "Error: font name required" >&2
    return 1
  fi

  log_action "reject" "$font" "$reason"
}

unreject_font() {
  local font="$1"

  if [[ -z "$font" ]]; then
    echo "Error: font name required" >&2
    return 1
  fi

  log_action "unreject" "$font"
}

is_font_rejected() {
  local font="$1"

  if [[ ! -f "$FONT_HISTORY_FILE" ]]; then
    return 1
  fi

  local last_action
  last_action=$(jq -s -r --arg font "$font" '
    map(select(.font == $font and (.action == "reject" or .action == "unreject"))) |
    sort_by(.ts) | last | .action // "none"
  ' "$FONT_HISTORY_FILE")

  [[ "$last_action" == "reject" ]]
}

get_rejected_font_info() {
  local font="$1"

  if [[ ! -f "$FONT_HISTORY_FILE" ]]; then
    echo "{}"
    return
  fi

  jq -s --arg font "$font" '
    map(select(.font == $font and .action == "reject")) |
    sort_by(.ts) | last // {}
  ' "$FONT_HISTORY_FILE"
}

list_rejected_fonts() {
  if [[ ! -f "$FONT_HISTORY_FILE" ]]; then
    return
  fi

  jq -s -c '
    group_by(.font) |
    map(
      . as $actions |
      ($actions | map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last) as $last |
      if $last.action == "reject" then
        {
          font: .[0].font,
          rejected_date: $last.ts,
          reason: $last.message,
          platforms: [$actions[].platform] | unique | join(",")
        }
      else
        null
      end
    ) |
    map(select(. != null)) |
    sort_by(.rejected_date) | reverse |
    .[]
  ' "$FONT_HISTORY_FILE"
}

init_storage() {
  if [[ ! -d "$FONT_STATE_DIR" ]]; then
    mkdir -p "$FONT_STATE_DIR"
  fi

  if [[ ! -f "$FONT_HISTORY_FILE" ]]; then
    touch "$FONT_HISTORY_FILE"
  fi
}

init_storage
