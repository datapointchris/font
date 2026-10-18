#!/usr/bin/env bats
# When the schedule changes the font: the hold each kind of apply earns, and the presence check.

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
