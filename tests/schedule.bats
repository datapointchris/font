#!/usr/bin/env bats
# When the schedule changes the font: the turn each kind of apply leads to, the presence check,
# and how font rank counts the turns it gave each font.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
  source "$FONT_ROOT/lib/schedule.sh"
  # Turns are local hours. A POSIX zone needs no tzdata: 04:00 local is 09:00Z.
  export TZ=EST5
}

# Epoch seconds at an hour of 2026-01-01 UTC, past 24 into the next day.
utc_hour() {
  echo $((1767225600 + $1 * 3600))
}

# This machine, as get_machine_id reads it.
uname() { echo testbox; }

# A logind whose display session is 2 and carries the hints in SESSION_HINTS.
loginctl() {
  case "$1" in
    show-user) echo 2 ;;
    show-session) printf '%s\n' "${SESSION_HINTS[@]}" ;;
  esac
}

@test "the next turn follows a scheduled apply, waits out a hand apply's hold, and skips a missed window" {
  # No trigger is how every apply before the schedule reads, and it was applied by hand.
  add_history_record "2026-01-01T00:00:00Z" "Hand Mono" apply "" testbox
  add_apply_record "2099-01-01T00:00:00Z" "Elsewhere Mono" schedule otherbox
  # 19:00 local plus the 12-hour hold is 07:00, so the 12:00 turn.
  run schedule_next_turn "$(utc_hour 0)"
  assert_output "$(utc_hour 17)"

  add_apply_record "2026-01-01T17:10:00Z" "Timer Mono" schedule
  run schedule_next_turn "$(utc_hour 17)"
  assert_output "$(utc_hour 25)"

  # Away until 21:30 local, past the 20:00 turn's hour, so the 04:00 turn.
  run schedule_next_turn "$(($(utc_hour 26) + 1800))"
  assert_output "$(utc_hour 33)"

  # Written the way the timer writes it, so the key the reader expects is pinned.
  log_action apply "Timer Mono" "" schedule
  run pipeline "schedule_last_apply | jq -r '.trigger'"
  assert_output "schedule"
}

@test "a due change waits while the session is idle or locked, and goes ahead while it is active" {
  export PLATFORM=archlinux
  add_apply_record "2026-01-01T17:10:00Z" "Timer Mono" schedule
  local due
  due=$(utc_hour 25)

  run pipeline "schedule_decide $((due - 60)) | cut -f1"
  assert_output "waiting"

  SESSION_HINTS=(IdleHint=yes LockedHint=no)
  run pipeline "schedule_decide $due | cut -f1"
  assert_output "away"

  SESSION_HINTS=(IdleHint=no LockedHint=yes)
  run pipeline "schedule_decide $due | cut -f1"
  assert_output "away"

  SESSION_HINTS=(IdleHint=no LockedHint=no)
  run pipeline "schedule_decide $due | cut -f1"
  assert_output "due"
}

@test "a turn ends at the next apply of another font on its own machine, and one still running is not counted" {
  add_apply_record "2026-01-01T00:00:00Z" "Turn Mono" schedule
  add_apply_record "2026-01-01T01:00:00Z" "Other Mono" manual otherbox
  add_apply_record "2026-01-01T02:00:00Z" "Turn Mono" manual
  add_apply_record "2026-01-01T03:00:00Z" "Hand Mono" manual
  add_apply_record "2026-01-01T04:00:00Z" "Kept Mono" schedule
  add_apply_record "2026-01-01T10:00:00Z" "Turn Mono" schedule
  add_apply_record "2026-01-01T11:00:00Z" "Hand Mono" manual
  add_apply_record "2026-01-01T12:00:00Z" "Running Mono" schedule
  run pipeline "get_schedule_turns | jq -sc 'map([.font, .turns, .kept, .switched, .median_switch_seconds])'"
  # Turn Mono's first turn runs three hours and its second one, so the median is two.
  assert_output '[["Kept Mono",1,1,0,null],["Turn Mono",2,0,2,7200]]'
}
