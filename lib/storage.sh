#!/usr/bin/env bash
# Font storage layer - unified JSONL history with terminal context
# Single history file synced across machines via gist

set -euo pipefail

# terminal.sh sources this for detect_platform and the machine id, and bin/font
# sources both, so the guard stops init_storage running twice.
[[ -n "${_FONT_STORAGE_SOURCED:-}" ]] && return 0
_FONT_STORAGE_SOURCED=1

_STORAGE_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dev mode: use FONT_ENV=development (set via direnv in this repository's .envrc)
_is_dev_mode() {
  [[ "${FONT_ENV:-}" == "development" ]]
}

if _is_dev_mode; then
  FONT_STATE_DIR="$_STORAGE_APP_DIR/.dev-data"
else
  FONT_STATE_DIR="$HOME/.local/state/font"
fi
FONT_HISTORY_FILE="$FONT_STATE_DIR/history.jsonl"

# Maps the family names fonts carried before scripts/curate-fonts.sh spaced them
# out to the names the registry uses. log_action only appends, so a history
# written before the rename keeps rows under the old names until a sync pull
# rewrites it, and on a machine with sync off it keeps them for good. get_history
# and the sync merge read through this, so one font is not ranked, rejected or
# merged as two.
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

# The physical machine's hostname, lowercased. Platform is recorded as its own
# field, so prefixing it (the old "platform-host" format) both duplicated the
# platform and split one machine across records when the platform label changed.
#
# Read through the same normalizer as every history row, because the schedule,
# the usage timeline and sync each select this machine's rows by equality. A
# host named "linux-box" reads back as "box", so a raw id would match none of
# its own rows: a push would send nothing and a pull would drop them.
get_machine_id() {
  local host
  host=$(uname -n 2>/dev/null | cut -d. -f1 | tr '[:upper:]' '[:lower:]')
  [[ -z "$host" ]] && host="unknown"
  jq -rn --arg host "$host" "{machine: \$host} | $_JQ_NORMALIZE_MACHINE | .machine"
}

# The definitions every reading of time on screen shares, so `font rank`,
# `font stats` and the per-font page agree to the second.
#
# parse_ts accepts the +00:00 offset older records carry, which fromdateiso8601
# rejects outright.
#
# apply_spans reads the history array and emits one object per apply. An apply
# ends at the next apply on its own machine, since another machine's apply says
# nothing about this screen. Each machine's latest apply is open: on this
# machine it runs to now while it is still the current font, and on any other
# its duration is null, because nothing here knows when it ended. A session is a
# maximal run of one font on one machine, so a re-apply does not start one.
IFS= read -r -d '' _JQ_TIMELINE_DEFS <<'JQ' || true
  def parse_ts:
    if test("[+-][0-9]{2}:[0-9]{2}$") then gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601
    else fromdateiso8601
    end;

  def apply_spans($machine; $current):
    map(select(.action == "apply")) | group_by(.machine)[] | sort_by(.ts)
    | . as $applies
    | range(0; $applies | length) as $i
    | $applies[$i] as $apply
    | {
        font: $apply.font,
        machine: $apply.machine,
        month: $apply.ts[0:7],
        starts_session: ($i == 0 or $applies[$i - 1].font != $apply.font),
        seconds: (
          if $i < (($applies | length) - 1) then
            ($applies[$i + 1].ts | parse_ts) - ($apply.ts | parse_ts)
          elif $apply.machine == $machine and $apply.font == $current then
            (now | floor) - ($apply.ts | parse_ts)
          else
            null
          end
        )
      };
JQ

_storage_get_terminal_context() {
  if type -t get_terminal_context &>/dev/null; then
    get_terminal_context
  else
    echo '{}'
  fi
}

# Usage: log_action <action> [font] [message] [trigger]
# trigger says who applied a font, "manual" or "schedule". A row without one was
# applied by hand. Absent keys are omitted, never blank.
#
# A scheduled apply runs with no terminal, so its row carries the machine and
# platform and none of the fields a terminal reports.
log_action() {
  local action="$1"
  local font="${2:-}"
  local message="${3:-}"
  local trigger="${4:-}"

  if [[ -z "$action" ]]; then
    echo "Error: action required" >&2
    return 1
  fi

  mkdir -p "$FONT_STATE_DIR"

  local terminal_context='{}'
  [[ "$trigger" == "schedule" ]] || terminal_context=$(_storage_get_terminal_context)

  jq -nc \
    --argjson terminal "$terminal_context" \
    --arg machine "$(get_machine_id)" \
    --arg platform "$(detect_platform)" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg font "$font" \
    --arg act "$action" \
    --arg msg "$message" \
    --arg trigger "$trigger" \
    '$terminal + {machine: $machine, platform: $platform, ts: $ts, font: $font, action: $act}
      + (if $msg == "" then {} else {message: $msg} end)
      + (if $trigger == "" then {} else {trigger: $trigger} end)' >>"$FONT_HISTORY_FILE"
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

# Seconds each font was on screen, summed over every machine's timeline.
calculate_usage_time() {
  local current_font="$1"

  get_history | jq -c --arg current "$current_font" --arg machine "$(get_machine_id)" "$_JQ_TIMELINE_DEFS"'
    [apply_spans($machine; $current) | select(.seconds != null)]
    | group_by(.font)
    | map({key: .[0].font, value: (map(.seconds) | add)})
    | from_entries
  '
}

# Usage detail for a single font: total seconds, session count, average session,
# last-used timestamp, and seconds since last use.
get_font_usage_stats() {
  local font="$1"
  local current_font
  current_font=$(get_current_font 2>/dev/null || echo "")

  get_history | jq -c --arg font "$font" --arg current "$current_font" --arg machine "$(get_machine_id)" "$_JQ_TIMELINE_DEFS"'
    ([apply_spans($machine; $current) | select(.font == $font)]) as $spans |
    ($spans | map(.seconds // 0) | add // 0) as $usage |
    ($spans | map(select(.starts_session)) | length) as $sessions |
    (map(select(.action == "apply" and .font == $font)) | last) as $last |

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

  get_history | jq -c --arg font "$font" --arg current "$current_font" --arg machine "$(get_machine_id)" "$_JQ_TIMELINE_DEFS"'
    [apply_spans($machine; $current) | select(.font == $font and .seconds != null)]
    | group_by(.month)
    | map({key: .[0].month, value: (map(.seconds) | add)})
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

  get_history | jq -c --argjson usage "$usage_map" "$_JQ_TIMELINE_DEFS"'
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

  get_history | jq -c --arg current "$current_font" --arg machine "$(get_machine_id)" "$_JQ_TIMELINE_DEFS"'
    [apply_spans($machine; $current) | select(.seconds != null) | .machine //= "unknown"]
    | group_by(.machine)
    | map(
        (group_by(.font) | map({font: .[0].font, usage: (map(.seconds) | add)}) | max_by(.usage)) as $top |
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

# The latest apply of each of the most recently applied fonts, newest first, as
# one JSON array. unique_by would re-sort by font name, so the first sighting of
# each font is kept by hand instead.
get_recently_used() {
  local limit="${1:-10}"

  get_history | jq -c --argjson limit "$limit" '
    map(select(.action == "apply")) |
    sort_by(.ts) | reverse |
    reduce .[] as $apply ([];
      if any(.[]; .font == $apply.font) then . else . + [$apply] end) |
    .[:$limit]
  '
}

# This machine's latest apply, as one history row, or nothing.
get_machine_last_apply() {
  get_history | jq -c --arg machine "$(get_machine_id)" \
    'map(select(.action == "apply" and .machine == $machine)) | last // empty'
}

# The latest apply of a font made from a terminal. A scheduled apply has none to
# describe.
get_last_terminal_context() {
  local font="$1"

  get_history | jq --arg font "$font" '
    map(select(.font == $font and .action == "apply" and .terminal != null)) |
    sort_by(.ts) | last // {}
  '
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

# One font's entry from list_rejected_fonts, which is what the unreject picker's
# preview reads, or {} when the font is not rejected.
get_rejected_font_info() {
  local font="$1"

  list_rejected_fonts | jq -s --arg font "$font" '
    map(select(.font == $font)) | first // {}
  '
}

list_rejected_fonts() {
  get_history | jq -c '
    group_by(.font) |
    map(
      . as $actions |
      ($actions | map(select(.action == "reject" or .action == "unreject")) | sort_by(.ts) | last) as $last |
      if $last.action == "reject" then
        {
          font: .[0].font,
          rejected_date: $last.ts,
          reason: $last.message,
          platforms: [$actions[].platform] | unique
        }
      else
        null
      end
    ) |
    map(select(. != null)) |
    sort_by(.rejected_date) | reverse |
    .[]
  '
}

# Rejected font names, one per line. One jq over the whole history, rather than
# one per font in the registry.
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
# The axis is time since last apply, not apply count. In a real history the
# managed fonts' apply counts bunch together, with most of them level on the
# same count. A count that flat separates nothing, and the font it does single
# out is one just added at zero applies.
compute_font_weights() {
  local names_json
  names_json=$(jq -R . | jq -s -c .)

  get_history | jq -r \
    --argjson names "$names_json" \
    --argjson scale "$FONT_RECENCY_SCALE_DAYS" \
    --argjson cap "$FONT_RECENCY_CAP_DAYS" "$_JQ_TIMELINE_DEFS"'
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
