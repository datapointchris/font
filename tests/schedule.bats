#!/usr/bin/env bats
# When the schedule changes the font: the hold each kind of apply earns, the presence check, and
# how font rank counts the turns it gave each font.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
  source "$FONT_ROOT/lib/schedule.sh"
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

@test "a hand apply holds the next change 12 hours, a scheduled one 6, and only this machine's count" {
  # No trigger is how every apply before the schedule reads, and it was applied by hand.
  add_history_record "2026-01-01T00:00:00Z" "Hand Mono" apply "" testbox
  add_apply_record "2099-01-01T00:00:00Z" "Elsewhere Mono" schedule otherbox
  run pipeline "schedule_last_apply | jq -c '[.font, .trigger, .at, .due - .at]'"
  assert_output '["Hand Mono","manual",1767225600,43200]'

  # Written the way the timer writes it, so the key the reader expects is pinned.
  log_action apply "Timer Mono" "" schedule
  run pipeline "schedule_last_apply | jq -c '[.font, .trigger, .due - .at]'"
  assert_output '["Timer Mono","schedule",21600]'
}

@test "a due change waits while the session is idle or locked, and goes ahead while it is active" {
  export PLATFORM=archlinux
  add_apply_record "2026-01-01T00:00:00Z" "Timer Mono" schedule
  local due=$((1767225600 + 6 * 3600))

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
