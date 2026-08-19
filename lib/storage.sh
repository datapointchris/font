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

# Temporary font name migration (remove after all machines have synced)
# Old Nerd Font names -> new spaced names from curate-fonts.sh rename step
_JQ_NORMALIZE_FONT_NAMES='
  .font = (
    if .font == "ComicMonoNF" then "Comic Mono Nerd Font"
    elif .font == "ComicShannsMono Nerd Font" then "Comic Shanns Mono Nerd Font"
    elif .font == "FiraCode Nerd Font" then "Fira Code Nerd Font"
    elif .font == "JetBrainsMono Nerd Font" then "JetBrains Mono Nerd Font"
    elif .font == "MesloLGM Nerd Font" then "Meslo LGM Nerd Font"
    elif .font == "MonaspiceNe Nerd Font" then "Monaspice Ne Nerd Font"
    elif .font == "RobotoMono Nerd Font" then "Roboto Mono Nerd Font"
    elif .font == "SeriousShanns Nerd Font Mono" then "Serious Shanns Nerd Font"
    elif .font == "Iosevka Term Slab" then "Iosevka Term Slab Nerd Font"
    else .font
    end
  )
'

# Canonicalize .machine to a lowercased hostname so one physical machine reads as
# one machine. Handles the legacy "platform-host" format (strip a known platform
# prefix) and the current bare-host format alike; leaves records without a
# machine field untouched. Applied at read time so existing history merges too.
_JQ_NORMALIZE_MACHINE='
  if (.machine // null) == null then .
  else
    .machine = (
      (.machine | ascii_downcase)
      | if test("^(macos|archlinux|arch|wsl|linux|unknown)-")
        then sub("^(macos|archlinux|arch|wsl|linux|unknown)-"; "")
        else .
        end
    )
  end
'

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

  echo "$record" >>"$FONT_HISTORY_FILE"
}

get_history() {
  if [[ -f "$FONT_HISTORY_FILE" ]]; then
    jq -s "map($_JQ_NORMALIZE_FONT_NAMES | $_JQ_NORMALIZE_MACHINE) | sort_by(.ts)" "$FONT_HISTORY_FILE"
  else
    echo "[]"
  fi
}

get_history_raw() {
  if [[ -f "$FONT_HISTORY_FILE" ]]; then
    jq -s -c "map($_JQ_NORMALIZE_FONT_NAMES | $_JQ_NORMALIZE_MACHINE) | sort_by(.ts) | .[]" "$FONT_HISTORY_FILE"
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
    echo "archlinux"
  elif [[ -f /etc/os-release ]]; then
    # A Linux system file, absent wherever this lints on macOS.
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
      score: ((map(select(.action == "like")) | length) - (map(select(.action == "dislike")) | length)),
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

# Usage detail for a single font: total seconds, session count, average session,
# last-used timestamp, and seconds since last use. Usage is computed the same way
# as calculate_usage_time (time until the next apply of any font), so numbers
# agree across the tool. A "session" is a maximal run of this font in the apply
# timeline — re-applying the same font back-to-back stays one session.
get_font_usage_stats() {
  local font="$1"
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  get_history | jq -c --arg font "$font" --arg current "$current_font" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    (map(select(.action == "apply")) | sort_by(.ts)) as $applies |
    ($applies | length) as $n |

    ([range(0; $n) as $i |
      $applies[$i] as $a |
      if $i < ($n - 1) then
        {font: $a.font, duration: (($applies[$i + 1].ts | parse_ts) - ($a.ts | parse_ts))}
      elif $a.font == $current then
        {font: $a.font, duration: ((now | floor) - ($a.ts | parse_ts))}
      else null end
    ] | map(select(. != null))) as $durations |

    ($durations | map(select(.font == $font) | .duration) | add // 0) as $usage |

    ([range(0; $n) as $i |
      if $applies[$i].font == $font and ($i == 0 or $applies[$i - 1].font != $font)
      then 1 else 0 end
    ] | add // 0) as $sessions |

    ($applies | map(select(.font == $font)) | last) as $last |

    {
      usage_seconds: $usage,
      sessions: $sessions,
      avg_seconds: (if $sessions > 0 then ($usage / $sessions | floor) else 0 end),
      last_used: ($last.ts // null),
      seconds_since: (if $last then ((now | floor) - ($last.ts | parse_ts)) else null end)
    }
  '
}

# Most common machine, terminal, and font size across a font's apply records.
# Nulls when a font has never been applied or a field was never recorded.
get_font_context_mode() {
  local font="$1"

  get_history | jq -c --arg font "$font" '
    def mode(f):
      map(f) | map(select(. != null and . != ""))
      | if length == 0 then null else (group_by(.) | max_by(length) | .[0]) end;

    map(select(.font == $font and .action == "apply")) as $a |
    {machine: ($a | mode(.machine)), terminal: ($a | mode(.terminal)), size: ($a | mode(.font_size))}
  '
}

# Usage seconds bucketed by calendar month (YYYY-MM), for one font. Each apply's
# duration is attributed to the month it started in. Returns a JSON object like
# {"2026-01": 3600, "2026-03": 7200}. Feeds the preview's monthly sparkline.
get_font_monthly_usage_map() {
  local font="$1"
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  get_history | jq -c --arg font "$font" --arg current "$current_font" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    (map(select(.action == "apply")) | sort_by(.ts)) as $applies |
    ($applies | length) as $n |

    [range(0; $n) as $i |
      $applies[$i] as $a |
      (if $i < ($n - 1) then (($applies[$i + 1].ts | parse_ts) - ($a.ts | parse_ts))
       elif $a.font == $current then ((now | floor) - ($a.ts | parse_ts))
       else null end) as $dur |
      if $dur == null then empty else {font: $a.font, month: $a.ts[0:7], dur: $dur} end
    ]
    | map(select(.font == $font))
    | group_by(.month)
    | map({key: .[0].month, value: (map(.dur) | add)})
    | from_entries
  '
}

# A font's 1-based position in each ranking (registry-managed fonts only), plus
# the total ranked. Positions are null when the font is not in the ranked set.
get_font_rank_positions() {
  local font="$1"
  local available_json
  available_json=$(list_fonts | jq -R . | jq -s .)

  get_rankings | jq -s --argjson avail "$available_json" --arg font "$font" '
    map(select(.font as $f | ($avail | index($f)) != null)) as $r |
    ($r | sort_by(.score, .sort_key) | reverse | map(.font) | index($font)) as $li |
    ($r | sort_by(.usage_seconds) | reverse | map(.font) | index($font)) as $hi |
    {
      total: ($r | length),
      likes_pos: (if $li == null then null else $li + 1 end),
      hours_pos: (if $hi == null then null else $hi + 1 end)
    }
  '
}

# ==============================================================================
# PORTFOLIO STATS (font stats dashboard)
# ==============================================================================

# Whole-portfolio summary: fonts tried, active span, total testing time, and how
# often testing ends in a like vs a rejection. Rates are over distinct fonts.
get_stats_overview() {
  local current_font usage_map
  current_font=$(get_current_font 2>/dev/null || echo "")
  usage_map=$(calculate_usage_time "$current_font")

  get_history | jq -c --argjson usage "$usage_map" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    (group_by(.font)) as $byfont |
    (min_by(.ts).ts // null) as $first |
    (max_by(.ts).ts // null) as $last |
    {
      fonts_tried: ($byfont | length),
      first_ts: $first,
      last_ts: $last,
      span_days: (if $first and $last then (($last | parse_ts) - ($first | parse_ts)) / 86400 | floor else 0 end),
      total_usage_seconds: ([$usage[]] | add // 0),
      liked_fonts: ([$byfont[] | select((map(select(.action == "like")) | length) > (map(select(.action == "dislike")) | length))] | length),
      rejected_fonts: ([$byfont[] | select((map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last | .action) == "reject")] | length),
      total_applies: ([.[] | select(.action == "apply")] | length)
    }
  '
}

# Stated-vs-revealed divergence: fonts used a lot but never rated (used_not_liked)
# and fonts liked but barely used (liked_not_used). Rejected fonts are excluded.
get_stats_divergence() {
  local current_font usage_map
  current_font=$(get_current_font 2>/dev/null || echo "")
  usage_map=$(calculate_usage_time "$current_font")

  get_history | jq -c --argjson usage "$usage_map" '
    group_by(.font) | map({
      font: .[0].font,
      likes: (map(select(.action == "like")) | length),
      dislikes: (map(select(.action == "dislike")) | length),
      score: ((map(select(.action == "like")) | length) - (map(select(.action == "dislike")) | length)),
      usage: ($usage[.[0].font] // 0),
      rejected: ((map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last | .action // "none") == "reject")
    })
    | map(select(.rejected | not))
    | (map(.usage) | map(select(. > 0))) as $used |
      (if ($used | length) > 0 then (($used | add) / ($used | length)) else 0 end) as $mean_usage |
      {
        used_not_liked: ([.[] | select(.likes == 0 and .dislikes == 0 and .usage > $mean_usage)] | sort_by(-.usage) | .[0:5]),
        liked_not_used: ([.[] | select(.score > 0 and .usage < $mean_usage)] | sort_by(.usage) | .[0:5])
      }
  '
}

# Count of fonts first tried in each month (exploration pace over time).
get_stats_discovery() {
  get_history | jq -c '
    map(select(.action == "apply"))
    | group_by(.font) | map({font: .[0].font, first: (min_by(.ts).ts)})
    | group_by(.first[0:7]) | map({month: .[0].first[0:7], count: length})
    | sort_by(.month)
  '
}

# The most-used font on each machine, by attributed usage time.
get_stats_machine_favorites() {
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  get_history | jq -c --arg current "$current_font" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    (map(select(.action == "apply")) | sort_by(.ts)) as $applies |
    ($applies | length) as $n |

    [range(0; $n) as $i |
      $applies[$i] as $a |
      (if $i < ($n - 1) then (($applies[$i + 1].ts | parse_ts) - ($a.ts | parse_ts))
       elif $a.font == $current then ((now | floor) - ($a.ts | parse_ts))
       else null end) as $dur |
      if $dur == null then empty else {machine: ($a.machine // "unknown"), font: $a.font, dur: $dur} end
    ]
    | group_by(.machine)
    | map(
        (group_by(.font) | map({font: .[0].font, usage: (map(.dur) | add)}) | max_by(.usage)) as $top |
        {machine: .[0].machine, font: $top.font, usage: $top.usage}
      )
    | sort_by(-.usage)
  '
}

get_rankings() {
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  local usage_times
  usage_times=$(calculate_usage_time "$current_font")

  get_history | jq -c --argjson usage "$usage_times" '
    group_by(.font) |
    map(
      . as $actions |
      ($actions | map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last | .action // "none") as $reject_status |
      if $reject_status == "reject" then
        null
      else
        {
          font: .[0].font,
          likes: map(select(.action == "like")) | length,
          dislikes: map(select(.action == "dislike")) | length,
          score: ((map(select(.action == "like")) | length) - (map(select(.action == "dislike")) | length)),
          last_used: (map(select(.action == "apply")) | max_by(.ts) | .ts // "never"),
          platforms: [.[].platform] | unique | join(","),
          usage_seconds: ($usage[.[0].font] // 0),
          sort_key: (if (map(select(.action == "apply")) | length) > 0 then (map(select(.action == "apply")) | max_by(.ts) | .ts) else "0" end)
        }
      end
    ) |
    map(select(. != null)) |
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

# Rejected font names, one per line. One jq over the whole history rather than
# is_font_rejected per font, which spawns one for every font in the registry.
#
# Through get_history, so a rejection recorded under a legacy spelling is read
# under the name the registry uses. A raw read compares "FiraCode Nerd Font"
# against a registry saying "Fira Code Nerd Font" and finds no rejection at all.
get_rejected_font_ids() {
  get_history | jq -r '
    group_by(.font) |
    map(
      (map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last | .action // "none") as $last |
      if $last == "reject" then .[0].font else null end
    ) |
    map(select(. != null)) |
    .[]
  '
}

# How long a font goes unused before it weighs twice as much as one applied
# today, and the ceiling that weight climbs to. A font with no applies at all is
# held at the cap rather than running away with the whole distribution.
FONT_RECENCY_SCALE_DAYS=30
FONT_RECENCY_CAP_DAYS=180

# Selection weight per font, read from font names on stdin and printed as
# "<font>\t<weight>".
#
# The axis is time since last apply, not apply count. Measured 2026-08-19
# against the real history: the 11 managed fonts sat between 17 and 33 applies
# and eight of them were level on 17. A count that flat separates nothing, and
# it is a font newly added on zero that a count then singles out.
compute_font_weights() {
  local names_json
  names_json=$(jq -R . | jq -s -c .)

  get_history | jq -r \
    --argjson names "$names_json" \
    --argjson scale "$FONT_RECENCY_SCALE_DAYS" \
    --argjson cap "$FONT_RECENCY_CAP_DAYS" '
    def parse_ts:
      if test("[+-][0-9]{2}:[0-9]{2}$") then
        gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
      else
        fromdateiso8601
      end;

    (now) as $now |
    (
      map(select(.action == "apply")) |
      group_by(.font) |
      map({key: .[0].font, value: (max_by(.ts) | .ts)}) |
      from_entries
    ) as $last_applied |

    # A clock-skewed record from another machine can date an apply in the
    # future, which subtracts to a negative age and then to a weight below 1.
    def clamp_days: if . < 0 then 0 elif . > $cap then $cap else . end;

    $names[] |
    . as $font |
    (
      if $last_applied[$font] == null then
        $cap
      else
        (($now - ($last_applied[$font] | parse_ts)) / 86400) | clamp_days
      end
    ) as $days |
    "\($font)\t\(1 + ($days / $scale))"
  '
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
