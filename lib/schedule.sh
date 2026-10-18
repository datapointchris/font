#!/usr/bin/env bash
# A timer that changes the font while the user is present, one schedule per machine.

set -euo pipefail

[[ -n "${_FONT_SCHEDULE_SOURCED:-}" ]] && return 0
_FONT_SCHEDULE_SOURCED=1

FONT_SCHEDULE_TURN_HOURS=6
FONT_SCHEDULE_HOLD_HOURS=12
FONT_SCHEDULE_CHECK_MINUTES=5
# theme's timer checks on the five-minute marks, and both tools restart waybar.
# Two restarts at one moment can each kill the old bar and start a new one,
# leaving two bars, so this one checks two minutes later.
FONT_SCHEDULE_CHECK_OFFSET_MINUTES=2
# macOS reads input idleness itself. The hypridle listener in the help uses the same figure.
FONT_SCHEDULE_IDLE_SECONDS=600

FONT_SCHEDULE_UNIT="font-schedule"
FONT_SCHEDULE_LABEL="com.datapointchris.font-schedule"
FONT_SCHEDULE_STATE_FILE="$FONT_STATE_DIR/schedule.json"

# The service manager that runs the timer, or nothing. WSL has no display session to read.
schedule_supervisor() {
  case "$(detect_platform)" in
    macos) echo "launchd" ;;
    wsl) ;;
    *)
      if command -v systemctl &>/dev/null && command -v loginctl &>/dev/null; then
        echo "systemd"
      fi
      ;;
  esac
}

_schedule_systemd_dir() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
}

_schedule_plist() {
  echo "$HOME/Library/LaunchAgents/$FONT_SCHEDULE_LABEL.plist"
}

_schedule_definition_file() {
  case "$(schedule_supervisor)" in
    systemd) echo "$(_schedule_systemd_dir)/$FONT_SCHEDULE_UNIT.timer" ;;
    launchd) _schedule_plist ;;
    *) return 1 ;;
  esac
}

# On means the timer's definition is installed.
schedule_is_on() {
  local definition
  definition=$(_schedule_definition_file) && [[ -f "$definition" ]]
}

# A weekday alone is ambiguous more than six days away, so those get the date.
_schedule_clock() {
  jq -nr --argjson t "$1" '
    if ($t - now) > -518400 and ($t - now) < 518400 then $t | strflocaltime("%a %H:%M")
    else $t | strflocaltime("%Y-%m-%d %H:%M")
    end'
}

# GNU stat first, then BSD's, since macOS may carry either on PATH.
_schedule_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# This machine's latest apply as {font, trigger, at, due}. A row with no trigger was applied by hand.
schedule_last_apply() {
  get_machine_last_apply | jq -c \
    --argjson turn "$((FONT_SCHEDULE_TURN_HOURS * 3600))" \
    --argjson hold "$((FONT_SCHEDULE_HOLD_HOURS * 3600))" "$_JQ_TIMELINE_DEFS"'
    (.trigger // "manual") as $trigger
    | (.ts | parse_ts) as $at
    | {
        font,
        trigger: $trigger,
        at: $at,
        due: ($at + (if $trigger == "schedule" then $turn else $hold end))
      }'
}

# Prints why the user counts as away and succeeds, or prints "active" and fails.
schedule_away_reason() {
  if [[ "$(detect_platform)" == "macos" ]]; then
    local idle
    idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }' || true)
    if [[ "${idle:-0}" -ge "$FONT_SCHEDULE_IDLE_SECONDS" ]]; then
      echo "no input for $(format_duration "$idle")"
      return 0
    fi
  else
    local session hints
    session=$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null || true)
    if [[ -z "$session" ]]; then
      echo "no display session"
      return 0
    fi
    hints=$(loginctl show-session "$session" -p IdleHint -p LockedHint 2>/dev/null || true)
    if [[ "$hints" == *"LockedHint=yes"* ]]; then
      echo "session $session is locked"
      return 0
    fi
    if [[ "$hints" == *"IdleHint=yes"* ]]; then
      echo "session $session is idle"
      return 0
    fi
  fi

  echo "active"
  return 1
}

# Prints "<verdict>\t<due epoch>\t<reason>" at a moment in epoch seconds.
# The verdict is waiting, away (due but nobody present) or due.
schedule_decide() {
  local now="$1"
  local due
  due=$(schedule_last_apply | jq -r '.due')
  due="${due:-$now}"

  if [[ "$now" -lt "$due" ]]; then
    printf 'waiting\t%s\t\n' "$due"
    return 0
  fi

  local reason
  if reason=$(schedule_away_reason); then
    printf 'away\t%s\t%s\n' "$due" "$reason"
    return 0
  fi

  printf 'due\t%s\t\n' "$due"
}

# Replaced through a rename, so `font schedule status` never reads half a file.
_schedule_record() {
  local outcome="$1" detail="$2"
  mkdir -p "$FONT_STATE_DIR"
  local partial="$FONT_SCHEDULE_STATE_FILE.$$"
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg outcome "$outcome" \
    --arg detail "$detail" \
    '{ts: $ts, outcome: $outcome, detail: $detail}' >"$partial"
  mv "$partial" "$FONT_SCHEDULE_STATE_FILE"
}

# The user manager carries only what the session imported. Without these, the restarted bar exits.
_schedule_missing_desktop_env() {
  [[ "$(detect_platform)" == "macos" ]] && return 0
  local missing=()
  [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || missing+=(WAYLAND_DISPLAY DISPLAY)
  if command -v hyprctl &>/dev/null && pgrep -u "$(id -u)" -x Hyprland &>/dev/null \
    && ! hyprctl version &>/dev/null; then
    missing+=(HYPRLAND_INSTANCE_SIGNATURE)
  fi
  echo "${missing[*]}"
}

# One check, which is what the timer runs.
schedule_run() {
  local verdict due reason
  IFS=$'\t' read -r verdict due reason < <(schedule_decide "$(date +%s)")

  case "$verdict" in
    waiting)
      _schedule_record waiting "next change due $(_schedule_clock "$due")"
      echo "waiting: next change due $(_schedule_clock "$due")"
      return 0
      ;;
    away)
      _schedule_record away "due since $(_schedule_clock "$due"), $reason"
      echo "away: due since $(_schedule_clock "$due"), $reason"
      return 0
      ;;
  esac

  local missing
  missing=$(_schedule_missing_desktop_env)
  if [[ -n "$missing" ]]; then
    local blocked="no usable $missing, so a change could not reach the desktop."
    blocked+=" From a terminal on the desktop, run: systemctl --user import-environment $missing"
    _schedule_record blocked "$blocked"
    echo "blocked: $blocked" >&2
    return 1
  fi

  # The draw weighs every machine's applies.
  sync_pull &>/dev/null || true

  local started status=0
  started=$(date +%s)
  # Backgrounded and waited on: called in a condition, the apply would run with errexit off.
  random_font schedule &
  wait "$!" || status=$?

  # The history row is what the apply produced, so it decides the outcome.
  local last
  last=$(schedule_last_apply)
  if [[ -n "$last" ]] \
    && [[ "$(jq -r '.trigger' <<<"$last")" == "schedule" ]] \
    && [[ "$(jq -r '.at' <<<"$last")" -ge "$started" ]]; then
    _schedule_record applied "$(jq -r '.font' <<<"$last")"
    # In the foreground, because the unit ends any process left behind.
    sync_push &>/dev/null || true
    return 0
  fi

  _schedule_record failed "the apply exited $status without writing its history row"
  echo "failed: the apply exited $status without writing its history row" >&2
  return 1
}

# The line `font apply` prints while the schedule is on.
schedule_next_change_line() {
  local last
  last=$(schedule_last_apply)
  [[ -z "$last" ]] && return 0

  local due hours=$FONT_SCHEDULE_HOLD_HOURS
  due=$(jq -r '.due' <<<"$last")
  [[ "$(jq -r '.trigger' <<<"$last")" == "schedule" ]] && hours=$FONT_SCHEDULE_TURN_HOURS
  echo "Schedule: next change after $(_schedule_clock "$due") (${hours} h, once you are active)"
}

_schedule_write_systemd() {
  local dir
  dir=$(_schedule_systemd_dir)
  mkdir -p "$dir"

  # The enabling shell's PATH, since the user manager's lacks where jq and gh
  # usually live. FONT_ENV carries dev mode, so a timer turned on from a
  # development checkout reads and writes .dev-data like every other command.
  local environment="Environment=\"PATH=$PATH\""
  if _is_dev_mode; then
    environment+=$'\nEnvironment="FONT_ENV=development"'
  fi

  cat >"$dir/$FONT_SCHEDULE_UNIT.service" <<EOF
[Unit]
Description=Change the font when its scheduled turn is due

[Service]
Type=oneshot
$environment
ExecStart="$FONT_APP_DIR/bin/font" schedule run
EOF

  cat >"$dir/$FONT_SCHEDULE_UNIT.timer" <<EOF
[Unit]
Description=Check every $FONT_SCHEDULE_CHECK_MINUTES minutes whether the font's turn is due

[Timer]
OnCalendar=*:$FONT_SCHEDULE_CHECK_OFFSET_MINUTES/$FONT_SCHEDULE_CHECK_MINUTES

[Install]
WantedBy=timers.target
EOF
}

_schedule_write_launchd() {
  local plist
  plist=$(_schedule_plist)
  mkdir -p "$(dirname "$plist")"

  local environment="    <key>PATH</key>
    <string>$PATH</string>"
  if _is_dev_mode; then
    environment+="
    <key>FONT_ENV</key>
    <string>development</string>"
  fi

  # AbandonProcessGroup stops launchd killing what the apply restarted when the job exits.
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$FONT_SCHEDULE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$FONT_APP_DIR/bin/font</string>
    <string>schedule</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
$environment
  </dict>
  <key>StartInterval</key>
  <integer>$((FONT_SCHEDULE_CHECK_MINUTES * 60))</integer>
  <key>AbandonProcessGroup</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>$FONT_STATE_DIR/schedule.log</string>
</dict>
</plist>
EOF
}

_schedule_unsupported() {
  echo "Error: the schedule needs systemd and logind, or launchd on macOS" >&2
  if [[ "$(detect_platform)" == "wsl" ]]; then
    echo "  WSL has no display session to tell whether you are present." >&2
  fi
  return 1
}

schedule_on() {
  case "$(schedule_supervisor)" in
    systemd)
      _schedule_write_systemd
      systemctl --user daemon-reload
      systemctl --user --quiet enable "$FONT_SCHEDULE_UNIT.timer"
      systemctl --user restart "$FONT_SCHEDULE_UNIT.timer"
      ;;
    launchd)
      _schedule_write_launchd
      launchctl bootout "gui/$(id -u)/$FONT_SCHEDULE_LABEL" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$(_schedule_plist)"
      ;;
    *)
      _schedule_unsupported
      return 1
      ;;
  esac

  echo "✓ Schedule on, checking every $FONT_SCHEDULE_CHECK_MINUTES minutes"
  echo "  A scheduled font gets $FONT_SCHEDULE_TURN_HOURS h and one applied by hand $FONT_SCHEDULE_HOLD_HOURS h."
  echo "  A due change waits until you are active."
  _schedule_warn_idle_hint
}

schedule_off() {
  case "$(schedule_supervisor)" in
    systemd)
      local dir
      dir=$(_schedule_systemd_dir)
      systemctl --user --quiet disable --now "$FONT_SCHEDULE_UNIT.timer" 2>/dev/null || true
      rm -f "$dir/$FONT_SCHEDULE_UNIT.service" "$dir/$FONT_SCHEDULE_UNIT.timer"
      systemctl --user daemon-reload
      ;;
    launchd)
      launchctl bootout "gui/$(id -u)/$FONT_SCHEDULE_LABEL" 2>/dev/null || true
      rm -f "$(_schedule_plist)"
      ;;
    *)
      _schedule_unsupported
      return 1
      ;;
  esac

  echo "✓ Schedule off"
}

# IdleSinceHint 0 means IdleHint has not changed since login, which is how an unset hint looks.
_schedule_warn_idle_hint() {
  [[ "$(schedule_supervisor)" == "systemd" ]] || return 0

  local session since
  session=$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null || true)
  [[ -n "$session" ]] || return 0
  since=$(loginctl show-session "$session" -p IdleSinceHint --value 2>/dev/null || true)
  if [[ "$since" == "0" ]]; then
    echo "  ! IdleHint has not changed since login, so every check may read you as active."
    echo "    An idle daemon has to set it: see font schedule --help"
  fi
}

_schedule_timer_state() {
  case "$(schedule_supervisor)" in
    systemd)
      echo "timer $(systemctl --user is-active "$FONT_SCHEDULE_UNIT.timer" 2>/dev/null || true)"
      ;;
    launchd)
      if launchctl print "gui/$(id -u)/$FONT_SCHEDULE_LABEL" &>/dev/null; then
        echo "agent loaded"
      else
        echo "agent not loaded"
      fi
      ;;
  esac
}

schedule_status() {
  echo ""
  echo "Font Schedule"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ -z "$(schedule_supervisor)" ]]; then
    echo "Status: not supported on $(detect_platform)"
    return 0
  fi

  local on=false
  schedule_is_on && on=true
  if [[ "$on" == true ]]; then
    echo "Status: On ✓ ($(_schedule_timer_state))"
  else
    echo "Status: Off"
  fi

  local last now
  last=$(schedule_last_apply)
  now=$(date +%s)
  if [[ -n "$last" ]]; then
    local font at due how="by hand"
    font=$(jq -r '.font' <<<"$last")
    at=$(jq -r '.at' <<<"$last")
    due=$(jq -r '.due' <<<"$last")
    [[ "$(jq -r '.trigger' <<<"$last")" == "schedule" ]] && how="by the schedule"
    echo "Current: $font, applied $how $(_schedule_clock "$at")"
    if [[ "$on" == true ]]; then
      if [[ "$now" -lt "$due" ]]; then
        echo "Next change: after $(_schedule_clock "$due"), once you are active"
      else
        echo "Next change: due since $(_schedule_clock "$due"), at the first check while you are active"
      fi
    fi
  fi

  local reason
  if reason=$(schedule_away_reason); then
    echo "Presence: away ($reason)"
  else
    echo "Presence: active"
  fi
  _schedule_warn_idle_hint

  local last_seen=0
  if [[ -f "$FONT_SCHEDULE_STATE_FILE" ]]; then
    local outcome detail
    last_seen=$(jq -r '.ts | fromdateiso8601' "$FONT_SCHEDULE_STATE_FILE")
    outcome=$(jq -r '.outcome' "$FONT_SCHEDULE_STATE_FILE")
    detail=$(jq -r '.detail' "$FONT_SCHEDULE_STATE_FILE")
    echo "Last check: $(_schedule_clock "$last_seen"), $outcome: $detail"
  elif [[ "$on" == true ]]; then
    echo "Last check: none yet"
  fi

  # A check from before the timer was installed says nothing about whether it runs.
  if [[ "$on" == true ]]; then
    local installed quiet
    installed=$(_schedule_mtime "$(_schedule_definition_file)")
    [[ "$installed" -gt "$last_seen" ]] && last_seen=$installed
    quiet=$((now - last_seen))
    if [[ "$quiet" -gt $((FONT_SCHEDULE_CHECK_MINUTES * 60 * 3)) ]]; then
      echo "  ! No check for $(format_duration "$quiet"), so the timer is not running."
    fi
  fi

  if [[ "$on" == false ]]; then
    echo ""
    echo "Turn it on with: font schedule on"
  fi
}
